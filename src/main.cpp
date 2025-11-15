#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <chrono>
#include <filesystem> // 需要 C++17
#include <iostream>
#include <string>
#include <vector>

// --- 日志库 ---
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/spdlog.h>

// Lua / LuaJIT
#include <lua.hpp>

// LuaFileSystem
#include <lfs.h>

// 我们的进程工具库
#include <proc_utils.h>

// 句柄管理的元表名称
#define PROCESS_HANDLE_METATABLE "PEShell.ProcessHandle"

// ------------------------------------------------------------------
// 日志系统初始化
// ------------------------------------------------------------------
void InitializeLogger(const std::string& exe_dir)
{
    try
    {
        std::vector<spdlog::sink_ptr> sinks;
        auto                          console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
        console_sink->set_level(spdlog::level::trace);
        sinks.push_back(console_sink);

        std::filesystem::path log_path = std::filesystem::path(exe_dir) / "logs";
        std::filesystem::create_directory(log_path);
        auto file_sink =
            std::make_shared<spdlog::sinks::basic_file_sink_mt>((log_path / "peshell_latest.log").string(), true);
        file_sink->set_level(spdlog::level::trace);
        sinks.push_back(file_sink);

        auto logger = std::make_shared<spdlog::logger>("peshell", begin(sinks), end(sinks));
        logger->set_level(spdlog::level::trace);
        logger->flush_on(spdlog::level::trace);

        spdlog::set_default_logger(logger);
        spdlog::info("Logger initialized successfully.");
    }
    catch (const spdlog::spdlog_ex& ex)
    {
        std::cerr << "Log initialization failed: " << ex.what() << std::endl;
    }
}

// ------------------------------------------------------------------
// 辅助函数 (UTF-8 <-> WideChar 转换)
// ------------------------------------------------------------------
std::vector<wchar_t> Utf8ToWide(lua_State* L, int index)
{
    if (lua_isnoneornil(L, index))
    {
        return {L'\0'};
    }
    const char* str = luaL_checkstring(L, index);
    if (!str)
    {
        return {L'\0'};
    }
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
    if (size_needed <= 0)
    {
        return {L'\0'};
    }
    std::vector<wchar_t> buffer(size_needed);
    MultiByteToWideChar(CP_UTF8, 0, str, -1, &buffer[0], size_needed);
    return buffer;
}

void WideToUtf8(lua_State* L, const wchar_t* wide_str)
{
    if (!wide_str)
    {
        lua_pushnil(L);
        return;
    }
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wide_str, -1, NULL, 0, NULL, NULL);
    if (size_needed <= 0)
    {
        lua_pushstring(L, "");
        return;
    }
    std::vector<char> buffer(size_needed);
    WideCharToMultiByte(CP_UTF8, 0, wide_str, -1, &buffer[0], size_needed, NULL, NULL);
    lua_pushstring(L, buffer.data());
}

// ------------------------------------------------------------------
// C++ 函数，用于绑定到 Lua
// ------------------------------------------------------------------
namespace LuaBindings
{
    // 带有消息循环的休眠
    static int pesh_sleep(lua_State* L)
    {
        int       duration_ms = (int)luaL_checkinteger(L, 1);
        ULONGLONG start_time  = GetTickCount64();
        do
        {
            ULONGLONG elapsed = GetTickCount64() - start_time;
            if (elapsed >= (ULONGLONG)duration_ms)
                break;

            DWORD remaining_time = (DWORD)(duration_ms - elapsed);
            DWORD wait_result    = MsgWaitForMultipleObjects(0, NULL, FALSE, remaining_time, QS_ALLINPUT);
            if (wait_result == WAIT_OBJECT_0 + 0)
            { // Timeout
                // Continue loop
            }
            else if (wait_result == WAIT_OBJECT_0 + 1)
            { // Message
                MSG msg;
                while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
                {
                    if (msg.message == WM_QUIT)
                        return 0;
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
            }
            else
            { // Error
                break;
            }
        } while (true);
        return 0;
    }

    // 日志函数绑定
    static int pesh_log_trace(lua_State* L)
    {
        spdlog::trace(luaL_checkstring(L, 1));
        return 0;
    }
    static int pesh_log_debug(lua_State* L)
    {
        spdlog::debug(luaL_checkstring(L, 1));
        return 0;
    }
    static int pesh_log_info(lua_State* L)
    {
        spdlog::info(luaL_checkstring(L, 1));
        return 0;
    }
    static int pesh_log_warn(lua_State* L)
    {
        spdlog::warn(luaL_checkstring(L, 1));
        return 0;
    }
    static int pesh_log_error(lua_State* L)
    {
        spdlog::error(luaL_checkstring(L, 1));
        return 0;
    }
    static int pesh_log_critical(lua_State* L)
    {
        spdlog::critical(luaL_checkstring(L, 1));
        return 0;
    }

    // 句柄的垃圾回收 (GC) 函数
    static int process_handle_gc(lua_State* L)
    {
        HANDLE* pHandle = static_cast<HANDLE*>(luaL_checkudata(L, 1, PROCESS_HANDLE_METATABLE));
        if (pHandle && *pHandle && *pHandle != INVALID_HANDLE_VALUE)
        {
            spdlog::trace("GC: Closing process handle {:p}", *pHandle);
            ::CloseHandle(*pHandle);
            *pHandle = INVALID_HANDLE_VALUE; // 防止重复关闭
        }
        return 0;
    }

    // 允许 Lua 显式关闭句柄
    static int pesh_close_handle(lua_State* L)
    {
        HANDLE* pHandle = static_cast<HANDLE*>(luaL_checkudata(L, 1, PROCESS_HANDLE_METATABLE));
        if (pHandle && *pHandle && *pHandle != INVALID_HANDLE_VALUE)
        {
            ::CloseHandle(*pHandle);
            *pHandle = INVALID_HANDLE_VALUE;
        }
        return 0;
    }

    // 使用 CreateProcess 启动进程
    static int pesh_create_process(lua_State* L)
    {
        auto command_w      = Utf8ToWide(L, 1);
        auto working_dir_w  = Utf8ToWide(L, 2);
        int  show_mode      = (int)luaL_optinteger(L, 3, SW_SHOWNORMAL);
        auto desktop_name_w = Utf8ToWide(L, 4);

        ProcUtils_ProcessResult result =
            ProcUtils_CreateProcess(command_w.data(), lua_isnoneornil(L, 2) ? nullptr : working_dir_w.data(), show_mode,
                                    lua_isnoneornil(L, 4) ? nullptr : desktop_name_w.data());

        if (result.pid == 0)
        {
            lua_pushnil(L);
            return 1;
        }

        lua_newtable(L);
        lua_pushinteger(L, result.pid);
        lua_setfield(L, -2, "pid");

        HANDLE* pHandle = static_cast<HANDLE*>(lua_newuserdata(L, sizeof(HANDLE)));
        *pHandle        = static_cast<HANDLE>(result.process_handle);
        luaL_getmetatable(L, PROCESS_HANDLE_METATABLE);
        lua_setmetatable(L, -2);

        lua_setfield(L, -2, "handle");
        return 1;
    }

    // 基于句柄的、带消息循环的等待函数
    static int pesh_wait_for_handle(lua_State* L)
    {
        HANDLE* pHandle    = static_cast<HANDLE*>(luaL_checkudata(L, 1, PROCESS_HANDLE_METATABLE));
        int     timeout_ms = (int)luaL_optinteger(L, 2, -1);
        HANDLE  handle     = *pHandle;

        if (!handle || handle == INVALID_HANDLE_VALUE)
        {
            lua_pushboolean(L, false);
            return 1;
        }

        ULONGLONG start_time = GetTickCount64();

        while (true)
        {
            ULONGLONG elapsed        = GetTickCount64() - start_time;
            DWORD     remaining_time = (timeout_ms < 0 || (ULONGLONG)timeout_ms > elapsed)
                                           ? (timeout_ms < 0 ? INFINITE : (DWORD)(timeout_ms - elapsed))
                                           : 0;

            DWORD wait_result = MsgWaitForMultipleObjects(1, &handle, FALSE, remaining_time, QS_ALLINPUT);

            if (wait_result == WAIT_OBJECT_0)
            {
                lua_pushboolean(L, true); // 进程已结束
                return 1;
            }
            if (wait_result == WAIT_OBJECT_0 + 1)
            {
                MSG msg;
                while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
                {
                    if (msg.message == WM_QUIT)
                    {
                        lua_pushboolean(L, false);
                        return 1;
                    }
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
            }
            else
            {
                lua_pushboolean(L, false); // 超时或错误
                return 1;
            }

            if (remaining_time == 0 && timeout_ms >= 0)
            {
                lua_pushboolean(L, false);
                return 1;
            }
        }
    }

    // 其他 proc_utils 函数绑定
    static int pesh_process_exists(lua_State* L)
    {
        lua_pushinteger(L, ProcUtils_ProcessExists(Utf8ToWide(L, 1).data()));
        return 1;
    }
    static int pesh_process_close(lua_State* L)
    {
        lua_pushboolean(L, ProcUtils_ProcessClose(Utf8ToWide(L, 1).data(), (unsigned int)luaL_optinteger(L, 2, 0)));
        return 1;
    }
    static int pesh_process_close_tree(lua_State* L)
    {
        lua_pushboolean(L, ProcUtils_ProcessCloseTree(Utf8ToWide(L, 1).data()));
        return 1;
    }

    // 文件系统原生函数绑定
    static int pesh_fs_copy(lua_State* L)
    {
        auto source_w      = Utf8ToWide(L, 1);
        auto destination_w = Utf8ToWide(L, 2);
        try
        {
            auto options = std::filesystem::copy_options::recursive | std::filesystem::copy_options::overwrite_existing;
            std::filesystem::copy(std::filesystem::path(source_w.data()), std::filesystem::path(destination_w.data()),
                                  options);
            lua_pushboolean(L, true);
        }
        catch (const std::filesystem::filesystem_error& e)
        {
            spdlog::error("Native fs_copy failed: {}", e.what());
            lua_pushboolean(L, false);
        }
        return 1;
    }

    static int pesh_fs_mkdirs(lua_State* L)
    {
        auto path_w = Utf8ToWide(L, 1);
        try
        {
            bool result = std::filesystem::create_directories(std::filesystem::path(path_w.data()));
            lua_pushboolean(L, result);
        }
        catch (const std::filesystem::filesystem_error& e)
        {
            spdlog::error("Native fs_mkdirs failed: {}", e.what());
            lua_pushboolean(L, false);
        }
        return 1;
    }

} // namespace LuaBindings

// ------------------------------------------------------------------
// Lua 状态初始化
// ------------------------------------------------------------------
lua_State* InitializeLuaState(const std::string& exe_dir)
{
    lua_State* L = luaL_newstate();
    if (!L)
    {
        spdlog::critical("Failed to create Lua state.");
        return nullptr;
    }
    luaL_openlibs(L);

    // 注册句柄元表及其 __gc 方法
    luaL_newmetatable(L, PROCESS_HANDLE_METATABLE);
    lua_pushcfunction(L, LuaBindings::process_handle_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);

    // 预加载静态链接的 lfs 模块
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");
    lua_pushcfunction(L, luaopen_lfs);
    lua_setfield(L, -2, "lfs");
    lua_pop(L, 2);

    // 将所有 C++ 绑定注册到全局表 pesh_native
    static const struct luaL_Reg pesh_native_lib[] = {{"sleep", LuaBindings::pesh_sleep},
                                                      {"create_process", LuaBindings::pesh_create_process},
                                                      {"wait_for_handle", LuaBindings::pesh_wait_for_handle},
                                                      {"close_handle", LuaBindings::pesh_close_handle},
                                                      {"process_exists", LuaBindings::pesh_process_exists},
                                                      {"process_close", LuaBindings::pesh_process_close},
                                                      {"process_close_tree", LuaBindings::pesh_process_close_tree},

                                                      // 添加缺失的文件系统绑定
                                                      {"fs_copy", LuaBindings::pesh_fs_copy},
                                                      {"fs_mkdirs", LuaBindings::pesh_fs_mkdirs},

                                                      // 日志函数绑定
                                                      {"log_trace", LuaBindings::pesh_log_trace},
                                                      {"log_debug", LuaBindings::pesh_log_debug},
                                                      {"log_info", LuaBindings::pesh_log_info},
                                                      {"log_warn", LuaBindings::pesh_log_warn},
                                                      {"log_error", LuaBindings::pesh_log_error},
                                                      {"log_critical", LuaBindings::pesh_log_critical},

                                                      {NULL, NULL}};
    lua_newtable(L);
    luaL_setfuncs(L, pesh_native_lib, 0);
    lua_setglobal(L, "pesh_native");

    // 设置 Lua 的 package.path
    std::string scripts_path = exe_dir + "\\scripts";
    size_t      pos          = 0;
    while ((pos = scripts_path.find('\\', pos)) != std::string::npos)
    {
        scripts_path.replace(pos, 1, "\\\\");
        pos += 2;
    }
    std::string package_path_update = "package.path = package.path .. ';" + scripts_path + "\\\\?.lua'";
    luaL_dostring(L, package_path_update.c_str());

    return L;
}

// ------------------------------------------------------------------
// 主程序入口
// ------------------------------------------------------------------
int main(int argc, char* argv[])
{
    char exe_path_buf[MAX_PATH];
    GetModuleFileNameA(NULL, exe_path_buf, MAX_PATH);
    std::string exe_path   = exe_path_buf;
    size_t      last_slash = exe_path.find_last_of("\\/");
    std::string exe_dir    = (std::string::npos != last_slash) ? exe_path.substr(0, last_slash) : ".";

    InitializeLogger(exe_dir);
    spdlog::info("PEShell v3.1 [Final Fix] starting...");
    spdlog::info("Executable directory: {}", exe_dir);

    lua_State* L = InitializeLuaState(exe_dir);
    if (!L)
    {
        return 1;
    }

    std::string prelude_script = exe_dir + "\\scripts\\prelude.lua";
    if (luaL_dofile(L, prelude_script.c_str()) != LUA_OK)
    {
        const char* error_msg = lua_tostring(L, -1);
        spdlog::critical("Failed to load prelude script (prelude.lua): {}", error_msg);
        MessageBoxA(NULL, error_msg, "PEShell Critical Error", MB_ICONERROR | MB_OK);
        lua_close(L);
        return 1;
    }

    int         return_code = 0;
    const char* sub_command = (argc > 1) ? argv[1] : "help";

    lua_getglobal(L, "PESHELL_COMMANDS");
    lua_getfield(L, -1, sub_command);

    if (!lua_isfunction(L, -1))
    {
        spdlog::error("Unknown command: '{}'", sub_command);
        lua_getglobal(L, "PESHELL_COMMANDS");
        lua_getfield(L, -1, "help");
        if (lua_isfunction(L, -1))
            lua_pcall(L, 0, 0, 0);
        return_code = 1;
    }
    else
    {
        int num_args = argc - 2;
        for (int i = 2; i < argc; ++i)
        {
            lua_pushstring(L, argv[i]);
        }
        if (lua_pcall(L, num_args, 1, 0) != LUA_OK)
        {
            const char* error_msg = lua_tostring(L, -1);
            spdlog::critical("Error executing command '{}': {}", sub_command, error_msg);
            MessageBoxA(NULL, error_msg, "PEShell Lua Error", MB_ICONERROR | MB_OK);
            return_code = 1;
        }
        else
        {
            // 获取 Lua 命令的返回值作为退出码
            if (lua_isnumber(L, -1))
            {
                return_code = (int)lua_tointeger(L, -1);
            }
            lua_pop(L, 1);
        }
    }

    bool is_main_mode = (argc > 1 && strcmp(argv[1], "main") == 0);
    if (is_main_mode && return_code == 0)
    {
        spdlog::info("Initial script finished. Entering persistent message loop (guardian mode).");
        MSG msg;
        while (GetMessage(&msg, NULL, 0, 0))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        spdlog::info("Received WM_QUIT. Main message loop is terminating.");
        return_code = (int)msg.wParam;
    }

    lua_close(L);
    spdlog::info("PEShell shutting down with exit code {}.", return_code);
    return return_code;
}