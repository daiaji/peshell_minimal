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
        auto        t            = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
        std::tm     tm           = *std::localtime(&t);
        std::string log_filename = "peshell_" + std::to_string(tm.tm_year + 1900) + "-" +
                                   std::to_string(tm.tm_mon + 1) + "-" + std::to_string(tm.tm_mday) + ".log";

        std::filesystem::path log_path = std::filesystem::path(exe_dir) / "logs";
        std::filesystem::create_directory(log_path);

        auto file_sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>((log_path / log_filename).string(), true);
        file_sink->set_level(spdlog::level::trace);
        sinks.push_back(file_sink);

        auto logger = std::make_shared<spdlog::logger>("peshell", begin(sinks), end(sinks));
        logger->set_level(spdlog::level::trace);
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
void SafeSleepWithMessageLoop(int duration_ms)
{
    ULONGLONG start_time = GetTickCount64();
    DWORD     remaining_time;
    do
    {
        ULONGLONG elapsed = GetTickCount64() - start_time;
        if (elapsed >= (ULONGLONG)duration_ms)
        {
            break;
        }
        remaining_time    = (DWORD)(duration_ms - elapsed);
        DWORD wait_result = MsgWaitForMultipleObjects(0, NULL, FALSE, remaining_time, QS_ALLINPUT);
        if (wait_result == WAIT_OBJECT_0)
        {
            MSG msg;
            while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
            {
                if (msg.message == WM_QUIT)
                {
                    return;
                }
                TranslateMessage(&msg);
                DispatchMessage(&msg);
            }
        }
    } while (true);
}

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
    if (!wide_str) {
        lua_pushnil(L);
        return;
    }
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wide_str, -1, NULL, 0, NULL, NULL);
    if (size_needed <= 0) {
        lua_pushstring(L, "");
        return;
    }
    std::vector<char> buffer(size_needed);
    WideCharToMultiByte(CP_UTF8, 0, wide_str, -1, &buffer[0], size_needed, NULL, NULL);
    lua_pushstring(L, buffer.data());
}


// --- C++ 函数，用于绑定到 Lua (完整版) ---
namespace LuaBindings
{
    static int pesh_sleep(lua_State* L) { SafeSleepWithMessageLoop((int)luaL_checkinteger(L, 1)); return 0; }
    static int pesh_process_exists(lua_State* L) { lua_pushinteger(L, ProcUtils_ProcessExists(Utf8ToWide(L, 1).data())); return 1; }
    static int pesh_process_close(lua_State* L) { lua_pushboolean(L, ProcUtils_ProcessClose(Utf8ToWide(L, 1).data(), (unsigned int)luaL_optinteger(L, 2, 0))); return 1; }
    static int pesh_process_wait_close(lua_State* L) { lua_pushboolean(L, ProcUtils_ProcessWaitClose(Utf8ToWide(L, 1).data(), (int)luaL_optinteger(L, 2, -1))); return 1; }
    static int pesh_exec(lua_State* L) {
        auto command_w = Utf8ToWide(L, 1);
        auto working_dir_w = Utf8ToWide(L, 2);
        int show_mode = (int)luaL_optinteger(L, 3, SW_SHOWNORMAL);
        bool wait = lua_toboolean(L, 4);
        auto desktop_name_w = Utf8ToWide(L, 5);
        unsigned int pid = ProcUtils_Exec(command_w.data(), lua_isnoneornil(L, 2) ? nullptr : working_dir_w.data(), show_mode, wait, lua_isnoneornil(L, 5) ? nullptr : desktop_name_w.data());
        lua_pushinteger(L, pid);
        return 1;
    }
    static int pesh_log_trace(lua_State* L) { spdlog::trace(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_debug(lua_State* L) { spdlog::debug(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_info(lua_State* L) { spdlog::info(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_warn(lua_State* L) { spdlog::warn(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_error(lua_State* L) { spdlog::error(luaL_checkstring(L, 1)); return 0; }
    static int pesh_log_critical(lua_State* L) { spdlog::critical(luaL_checkstring(L, 1)); return 0; }
    
    static int pesh_process_wait(lua_State* L)
    {
        auto wide_str = Utf8ToWide(L, 1);
        int timeout_ms = (int)luaL_optinteger(L, 2, -1);
        unsigned int pid = ProcUtils_ProcessWait(wide_str.data(), timeout_ms);
        lua_pushinteger(L, pid);
        return 1;
    }

    static int pesh_process_get_path(lua_State* L)
    {
        unsigned int pid = (unsigned int)luaL_checkinteger(L, 1);
        wchar_t path_buffer[MAX_PATH];
        if (ProcUtils_ProcessGetPath(pid, path_buffer, MAX_PATH)) {
            WideToUtf8(L, path_buffer);
        } else {
            lua_pushnil(L);
        }
        return 1;
    }

    static int pesh_process_get_parent(lua_State* L)
    {
        auto wide_str = Utf8ToWide(L, 1);
        unsigned int parent_pid = ProcUtils_ProcessGetParent(wide_str.data());
        lua_pushinteger(L, parent_pid);
        return 1;
    }

    static int pesh_process_set_priority(lua_State* L)
    {
        auto wide_str = Utf8ToWide(L, 1);
        const char* priority_char_str = luaL_checkstring(L, 2);
        wchar_t priority_char = (priority_char_str && *priority_char_str) ? priority_char_str[0] : L'N';
        bool result = ProcUtils_ProcessSetPriority(wide_str.data(), priority_char);
        lua_pushboolean(L, result);
        return 1;
    }
    
    static int pesh_process_close_tree(lua_State* L)
    {
        auto wide_str = Utf8ToWide(L, 1);
        bool result = ProcUtils_ProcessCloseTree(wide_str.data());
        lua_pushboolean(L, result);
        return 1;
    }

} // namespace LuaBindings

lua_State* InitializeLuaState(const std::string& exe_dir)
{
    lua_State* L = luaL_newstate();
    if (!L)
    {
        spdlog::critical("Failed to create Lua state.");
        MessageBoxA(NULL, "Failed to create Lua state.", "PEShell Critical Error", MB_ICONERROR | MB_OK);
        return nullptr;
    }
    luaL_openlibs(L);

    lua_pushcfunction(L, luaopen_lfs);
    lua_pushstring(L, "lfs");
    lua_call(L, 1, 1);
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");
    lua_pushvalue(L, -3);
    lua_setfield(L, -2, "lfs");
    lua_pop(L, 2);
    lua_setglobal(L, "lfs");

    static const struct luaL_Reg pesh_native_lib[] = {
        {"sleep", LuaBindings::pesh_sleep},
        {"process_exists", LuaBindings::pesh_process_exists},
        {"process_close", LuaBindings::pesh_process_close},
        {"process_wait_close", LuaBindings::pesh_process_wait_close},
        {"exec", LuaBindings::pesh_exec},
        {"log_trace", LuaBindings::pesh_log_trace},
        {"log_debug", LuaBindings::pesh_log_debug},
        {"log_info", LuaBindings::pesh_log_info},
        {"log_warn", LuaBindings::pesh_log_warn},
        {"log_error", LuaBindings::pesh_log_error},
        {"log_critical", LuaBindings::pesh_log_critical},
        {"process_wait", LuaBindings::pesh_process_wait},
        {"process_get_path", LuaBindings::pesh_process_get_path},
        {"process_get_parent", LuaBindings::pesh_process_get_parent},
        {"process_set_priority", LuaBindings::pesh_process_set_priority},
        {"process_close_tree", LuaBindings::pesh_process_close_tree},
        {NULL, NULL}
    };
    lua_newtable(L);
    luaL_setfuncs(L, pesh_native_lib, 0);
    lua_setglobal(L, "pesh_native");
    spdlog::debug("All native C++ functions registered to 'pesh_native' table.");

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
    spdlog::info("PEShell v3.1 starting...");
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

    int return_code = 0;

    if (argc < 2)
    {
        spdlog::info("No subcommand provided. Displaying help.");
        lua_getglobal(L, "PESHELL_COMMANDS");
        lua_getfield(L, -1, "help");

        if (lua_isfunction(L, -1))
        {
            if (lua_pcall(L, 0, 0, 0) != LUA_OK)
            {
                const char* error_msg = lua_tostring(L, -1);
                spdlog::error("Error executing 'help' command: {}", error_msg);
            }
        }
        else
        {
            spdlog::warn("'help' command not found.");
        }
    }
    else
    {
        const char* sub_command = argv[1];
        lua_getglobal(L, "PESHELL_COMMANDS");
        if (!lua_istable(L, -1))
        {
            spdlog::critical("'PESHELL_COMMANDS' table not found after running prelude.lua!");
            lua_close(L);
            return 1;
        }

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

            if (lua_pcall(L, num_args, 0, 0) != LUA_OK)
            {
                const char* error_msg = lua_tostring(L, -1);
                spdlog::critical("Error executing command '{}': {}", sub_command, error_msg);
                MessageBoxA(NULL, error_msg, "PEShell Lua Error", MB_ICONERROR | MB_OK);
                return_code = 1;
            }
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
    spdlog::info("PEShell shutting down.");
    return return_code;
}