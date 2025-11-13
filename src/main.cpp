#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <iostream>
#include <string>
#include <vector>
#include <chrono>
#include <filesystem> // 需要 C++17

// --- 日志库 ---
#include <spdlog/spdlog.h>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>

// Lua / LuaJIT
#include <lua.hpp>

// LuaFileSystem
#include <lfs.h>

// 我们的进程工具库
#include <proc_utils.h>

// ------------------------------------------------------------------
// 日志系统初始化
// ------------------------------------------------------------------
void InitializeLogger(const std::string& exe_dir)
{
    try
    {
        std::vector<spdlog::sink_ptr> sinks;

        // sink 1: 控制台输出
        auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
        console_sink->set_level(spdlog::level::trace); // 控制台显示所有级别的日志
        sinks.push_back(console_sink);

        // sink 2: 文件输出
        auto        t  = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
        std::tm     tm = *std::localtime(&t);
        std::string log_filename =
            "peshell_" + std::to_string(tm.tm_year + 1900) + "-" +
            std::to_string(tm.tm_mon + 1) + "-" + std::to_string(tm.tm_mday) + ".log";
        
        std::filesystem::path log_path = std::filesystem::path(exe_dir) / "logs";
        std::filesystem::create_directory(log_path);

        auto file_sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>((log_path / log_filename).string(), true);
        
        // ########## 关键修改 ##########
        // 将文件接收器的级别也设置为 trace，以确保所有日志都能被写入。
        file_sink->set_level(spdlog::level::trace);
        // ############################

        sinks.push_back(file_sink);

        auto logger = std::make_shared<spdlog::logger>("peshell", begin(sinks), end(sinks));
        logger->set_level(spdlog::level::trace);

        // 将刷新策略设置为 trace 级别。
        // 这意味着任何日志一旦被记录，就会立即写入文件。
        logger->flush_on(spdlog::level::trace);

        spdlog::set_default_logger(logger);
        spdlog::info("Logger initialized successfully. Outputting to console and file. Flush policy: TRACE.");
    }
    catch (const spdlog::spdlog_ex& ex)
    {
        std::cerr << "Log initialization failed: " << ex.what() << std::endl;
    }
}


// ------------------------------------------------------------------
// 辅助函数
// ------------------------------------------------------------------

/**
 * @brief 一个非阻塞的等待函数，可以在等待时处理 Windows 消息循环。
 * @param duration_ms 等待的毫秒数。
 */
void SafeSleepWithMessageLoop(int duration_ms)
{
    // 使用 GetTickCount64 避免32位计时器溢出问题
    ULONGLONG start_time = GetTickCount64();
    DWORD     remaining_time;

    do
    {
        // 计算剩余等待时间
        ULONGLONG elapsed = GetTickCount64() - start_time;
        if (elapsed >= (ULONGLONG)duration_ms)
        {
            break; // 等待时间到
        }
        remaining_time = (DWORD)(duration_ms - elapsed);

        // 等待消息或超时
        DWORD wait_result = MsgWaitForMultipleObjects(0, NULL, FALSE, remaining_time, QS_ALLINPUT);

        // 如果有消息到达 (WAIT_OBJECT_0 + 0)
        if (wait_result == WAIT_OBJECT_0)
        {
            MSG msg;
            // 处理所有当前队列中的消息
            while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
            {
                if (msg.message == WM_QUIT)
                {
                    // 如果收到退出消息，应立即停止等待
                    return;
                }
                TranslateMessage(&msg);
                DispatchMessage(&msg);
            }
        }
        // 如果是超时或其他情况，循环会继续或在下次检查时退出
    } while (true);
}

/**
 * @brief 将 Lua 栈上指定索引的 UTF-8 字符串转换为 std::vector<wchar_t>。
 *        能正确处理 C++ 端所需的宽字符和 nullptr。
 * @param L Lua state。
 * @param index 字符串在 Lua 栈上的索引。
 * @return 转换后的宽字符串 vector，以 L'\0' 结尾。
 */
std::vector<wchar_t> Utf8ToWide(lua_State* L, int index)
{
    if (lua_isnoneornil(L, index))
    {
        // 如果 Lua 端是 nil，返回一个只包含 L'\0' 的 vector，代表空指针
        return {L'\0'};
    }

    const char* str = luaL_checkstring(L, index);
    if (!str)
    {
        return {L'\0'};
    }

    // 计算所需缓冲区大小
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
    if (size_needed <= 0)
    {
        return {L'\0'};
    }

    std::vector<wchar_t> buffer(size_needed);
    // 执行转换
    MultiByteToWideChar(CP_UTF8, 0, str, -1, &buffer[0], size_needed);
    return buffer;
}

// ------------------------------------------------------------------
// C++ 函数，用于绑定到 Lua
// ------------------------------------------------------------------

namespace LuaBindings
{
    static int pesh_sleep(lua_State* L)
    {
        int ms = (int)luaL_checkinteger(L, 1);
        SafeSleepWithMessageLoop(ms);
        return 0;
    }

    static int pesh_process_exists(lua_State* L)
    {
        auto         wide_str = Utf8ToWide(L, 1);
        unsigned int pid      = ProcUtils_ProcessExists(wide_str.data());
        lua_pushinteger(L, pid);
        return 1;
    }

    static int pesh_process_close(lua_State* L)
    {
        auto         wide_str  = Utf8ToWide(L, 1);
        unsigned int exit_code = (unsigned int)luaL_optinteger(L, 2, 0);
        bool         result    = ProcUtils_ProcessClose(wide_str.data(), exit_code);
        lua_pushboolean(L, result);
        return 1;
    }

    static int pesh_process_wait_close(lua_State* L)
    {
        auto wide_str   = Utf8ToWide(L, 1);
        int  timeout_ms = (int)luaL_optinteger(L, 2, -1);
        bool result     = ProcUtils_ProcessWaitClose(wide_str.data(), timeout_ms);
        lua_pushboolean(L, result);
        return 1;
    }

    static int pesh_exec(lua_State* L)
    {
        auto command_w      = Utf8ToWide(L, 1);
        auto working_dir_w  = Utf8ToWide(L, 2);
        int  show_mode      = (int)luaL_optinteger(L, 3, SW_SHOWNORMAL);
        bool wait           = lua_toboolean(L, 4); // nil 会被转为 false
        auto desktop_name_w = Utf8ToWide(L, 5);

        unsigned int pid = ProcUtils_Exec(command_w.data(), lua_isnoneornil(L, 2) ? nullptr : working_dir_w.data(),
                                          show_mode, wait, lua_isnoneornil(L, 5) ? nullptr : desktop_name_w.data());

        lua_pushinteger(L, pid);
        return 1;
    }
    
    // --- 日志函数绑定 ---
    static int pesh_log_trace(lua_State* L) { spdlog::trace(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_debug(lua_State* L) { spdlog::debug(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_info(lua_State* L) { spdlog::info(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_warn(lua_State* L) { spdlog::warn(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_error(lua_State* L) { spdlog::error(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_critical(lua_State* L) { spdlog::critical(luaL_checkstring(L, 1)); return 0; }

} // namespace LuaBindings

// ------------------------------------------------------------------
// 主程序入口
// ------------------------------------------------------------------

int main(int argc, char* argv[])
{
    // --- 智能定位路径 ---
    char exe_path_buf[MAX_PATH];
    GetModuleFileNameA(NULL, exe_path_buf, MAX_PATH);
    std::string exe_path = exe_path_buf;
    size_t      last_slash = exe_path.find_last_of("\\/");
    std::string exe_dir    = (std::string::npos != last_slash) ? exe_path.substr(0, last_slash) : ".";

    // --- 初始化日志系统 ---
    InitializeLogger(exe_dir);

    spdlog::info("PEShell v3.0 starting...");
    spdlog::info("Executable directory: {}", exe_dir);

    // 1. 初始化 LuaJIT
    lua_State* L = luaL_newstate();
    if (!L)
    {
        spdlog::critical("Failed to create Lua state.");
        MessageBoxA(NULL, "Failed to create Lua state.", "PEShell Critical Error", MB_ICONERROR | MB_OK);
        return 1;
    }
    luaL_openlibs(L); // 加载标准库
    spdlog::debug("LuaJIT state created and standard libraries opened.");


    // 2. 注册 LuaFileSystem (lfs)
    lua_pushcfunction(L, luaopen_lfs);
    lua_pushstring(L, "lfs");
    lua_call(L, 1, 1); // 调用 luaopen_lfs("lfs")
    // 将 lfs 模块同时设置为全局变量和 package.loaded 中的条目
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");
    lua_pushvalue(L, -3);
    lua_setfield(L, -2, "lfs");
    lua_pop(L, 2); // 弹出 package 和 loaded
    lua_setglobal(L, "lfs");
    spdlog::debug("LuaFileSystem (lfs) module registered.");


    // 3. 注册我们自己的 C++ 函数到全局表 `pesh_native`
    static const struct luaL_Reg pesh_native_lib[] = {
        {"sleep", LuaBindings::pesh_sleep},
        {"process_exists", LuaBindings::pesh_process_exists},
        {"process_close", LuaBindings::pesh_process_close},
        {"process_wait_close", LuaBindings::pesh_process_wait_close},
        {"exec", LuaBindings::pesh_exec},
        // --- 日志绑定 ---
        {"log_trace", LuaBindings::pesh_log_trace},
        {"log_debug", LuaBindings::pesh_log_debug},
        {"log_info", LuaBindings::pesh_log_info},
        {"log_warn", LuaBindings::pesh_log_warn},
        {"log_error", LuaBindings::pesh_log_error},
        {"log_critical", LuaBindings::pesh_log_critical},
        {NULL, NULL} // 哨兵
    };
    lua_newtable(L);
    luaL_setfuncs(L, pesh_native_lib, 0);
    lua_setglobal(L, "pesh_native");
    spdlog::debug("Native C++ functions registered to 'pesh_native' table.");

    // 4. 设置 Lua 的 package.path
    std::string init_script_path = exe_dir + "\\scripts\\init.lua";
    std::string scripts_path = exe_dir + "\\scripts";
    size_t pos = 0;
    while ((pos = scripts_path.find('\\', pos)) != std::string::npos)
    {
        scripts_path.replace(pos, 1, "\\\\");
        pos += 2;
    }
    std::string package_path_update = "package.path = package.path .. ';" + scripts_path + "\\\\?.lua'";
    luaL_dostring(L, package_path_update.c_str());
    spdlog::debug("Lua package.path updated to include scripts directory.");


    // 5. 执行入口脚本
    spdlog::info("Executing entry script: {}", init_script_path);
    int result = luaL_dofile(L, init_script_path.c_str());

    if (result != LUA_OK)
    {
        const char* error_msg = lua_tostring(L, -1);
        spdlog::critical("Lua script error: {}", error_msg);
        // 错误信息已经打印到控制台和日志文件，弹窗是可选的
        MessageBoxA(NULL, error_msg, "PEShell Lua Error", MB_ICONERROR | MB_OK);
    }
    else
    {
        spdlog::info("Entry script finished successfully.");
    }

    // 6. 关闭 LuaJIT
    lua_close(L);
    spdlog::info("PEShell shutting down.");

    return (result == LUA_OK) ? 0 : 1;
}