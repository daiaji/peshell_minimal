/*****************************************************************
 *                    !! IMPORTANT !!                            *
 *   WINDOWS HEADERS MUST BE INCLUDED FIRST to avoid conflicts.    *
 *****************************************************************/
// clang-format off
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
// clang-format on

/*****************************************************************
 *                 Third-party Library Headers                   *
 *****************************************************************/

// C++ Standard Library
#include <chrono>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

// spdlog
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/spdlog.h>

// Lua / LuaJIT
// This must come before any library that depends on it (like lfs)
#include <lua.hpp>

// LuaFileSystem
#include <lfs.h>

/*****************************************************************
 *                    Project-specific Headers                   *
 *****************************************************************/
#include <proc_utils.h>

// Handle metatable names
#define PROCESS_HANDLE_METATABLE "PEShell.ProcessHandle"
#define EVENT_HANDLE_METATABLE "PEShell.EventHandle"

// ------------------------------------------------------------------
// The rest of the file remains completely unchanged.
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

namespace LuaBindings
{
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
            if (wait_result == WAIT_OBJECT_0)
            {
            }
            else if (wait_result == WAIT_OBJECT_0 + 1)
            {
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
            {
                break;
            }
        } while (true);
        return 0;
    }
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
    static int process_handle_gc(lua_State* L)
    {
        HANDLE* pHandle = static_cast<HANDLE*>(luaL_checkudata(L, 1, PROCESS_HANDLE_METATABLE));
        if (pHandle && *pHandle && *pHandle != INVALID_HANDLE_VALUE)
        {
            spdlog::trace("GC: Closing process handle {:p}", *pHandle);
            ::CloseHandle(*pHandle);
            *pHandle = INVALID_HANDLE_VALUE;
        }
        return 0;
    }
    static int event_handle_gc(lua_State* L)
    {
        HANDLE* pHandle = static_cast<HANDLE*>(luaL_checkudata(L, 1, EVENT_HANDLE_METATABLE));
        if (pHandle && *pHandle && *pHandle != INVALID_HANDLE_VALUE)
        {
            spdlog::trace("GC: Closing event handle {:p}", *pHandle);
            ::CloseHandle(*pHandle);
            *pHandle = INVALID_HANDLE_VALUE;
        }
        return 0;
    }
    static int pesh_close_handle(lua_State* L)
    {
        HANDLE* pHandle = static_cast<HANDLE*>(lua_touserdata(L, 1));
        if (pHandle && *pHandle && *pHandle != INVALID_HANDLE_VALUE)
        {
            ::CloseHandle(*pHandle);
            *pHandle = INVALID_HANDLE_VALUE;
        }
        return 0;
    }
    static int pesh_commandline_to_argv(lua_State* L)
    {
        auto    command_line_w = Utf8ToWide(L, 1);
        int     argc;
        LPWSTR* argv_w = CommandLineToArgvW(command_line_w.data(), &argc);
        if (argv_w == NULL)
        {
            lua_pushnil(L);
            return 1;
        }

        lua_newtable(L);
        for (int i = 0; i < argc; i++)
        {
            WideToUtf8(L, argv_w[i]);
            lua_rawseti(L, -2, i + 1);
        }

        LocalFree(argv_w);
        return 1;
    }
    static int pesh_get_current_pid(lua_State* L)
    {
        lua_pushinteger(L, GetCurrentProcessId());
        return 1;
    }
    static int pesh_get_exe_path(lua_State* L)
    {
        wchar_t path_buf[MAX_PATH];
        if (GetModuleFileNameW(NULL, path_buf, MAX_PATH) == 0)
        {
            lua_pushnil(L);
        }
        else
        {
            WideToUtf8(L, path_buf);
        }
        return 1;
    }
    static int pesh_find_all_processes(lua_State* L)
    {
        auto process_name_w = Utf8ToWide(L, 1);
        int  count          = ProcUtils_FindAllProcesses(process_name_w.data(), NULL, 0);
        if (count <= 0)
        {
            lua_pushnil(L);
            return 1;
        }

        std::vector<DWORD> pids(count);
        int                found = ProcUtils_FindAllProcesses(process_name_w.data(), pids.data(), count);
        if (found <= 0)
        {
            lua_pushnil(L);
            return 1;
        }

        lua_newtable(L);
        for (int i = 0; i < found; i++)
        {
            lua_pushinteger(L, pids[i]);
            lua_rawseti(L, -2, i + 1);
        }
        return 1;
    }
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
    static int pesh_open_process_by_name(lua_State* L)
    {
        auto   process_name_w = Utf8ToWide(L, 1);
        DWORD  desired_access = PROCESS_QUERY_INFORMATION | SYNCHRONIZE;
        HANDLE handle         = ProcUtils_OpenProcessByName(process_name_w.data(), desired_access);

        if (handle == NULL)
        {
            lua_pushnil(L);
            return 1;
        }

        DWORD pid = GetProcessId(handle);
        if (pid == 0)
        {
            CloseHandle(handle);
            lua_pushnil(L);
            return 1;
        }

        lua_newtable(L);
        lua_pushinteger(L, pid);
        lua_setfield(L, -2, "pid");

        HANDLE* pHandle = static_cast<HANDLE*>(lua_newuserdata(L, sizeof(HANDLE)));
        *pHandle        = handle;
        luaL_getmetatable(L, PROCESS_HANDLE_METATABLE);
        lua_setmetatable(L, -2);

        lua_setfield(L, -2, "handle");
        return 1;
    }
    static int pesh_create_event(lua_State* L)
    {
        auto   event_name_w = Utf8ToWide(L, 1);
        HANDLE hEvent       = CreateEventW(NULL, TRUE, FALSE, event_name_w.data());
        if (hEvent == NULL)
        {
            spdlog::error("Failed to create named event. Error: {}", GetLastError());
            lua_pushnil(L);
            return 1;
        }
        HANDLE* pHandle = static_cast<HANDLE*>(lua_newuserdata(L, sizeof(HANDLE)));
        *pHandle        = hEvent;
        luaL_getmetatable(L, EVENT_HANDLE_METATABLE);
        lua_setmetatable(L, -2);
        return 1;
    }
    static int pesh_open_event(lua_State* L)
    {
        auto   event_name_w = Utf8ToWide(L, 1);
        HANDLE hEvent       = OpenEventW(EVENT_MODIFY_STATE, FALSE, event_name_w.data());
        if (hEvent == NULL)
        {
            lua_pushnil(L);
            return 1;
        }
        HANDLE* pHandle = static_cast<HANDLE*>(lua_newuserdata(L, sizeof(HANDLE)));
        *pHandle        = hEvent;
        luaL_getmetatable(L, EVENT_HANDLE_METATABLE);
        lua_setmetatable(L, -2);
        return 1;
    }
    static int pesh_set_event(lua_State* L)
    {
        HANDLE* pHandle = static_cast<HANDLE*>(luaL_checkudata(L, 1, EVENT_HANDLE_METATABLE));
        if (pHandle && *pHandle)
        {
            lua_pushboolean(L, SetEvent(*pHandle));
        }
        else
        {
            lua_pushboolean(L, false);
        }
        return 1;
    }
    static int pesh_wait_for_multiple_objects(lua_State* L)
    {
        luaL_checktype(L, 1, LUA_TTABLE);
        int   timeout_ms = (int)luaL_optinteger(L, 2, -1);
        DWORD timeout_dw = (timeout_ms < 0) ? INFINITE : (DWORD)timeout_ms;

        std::vector<HANDLE> handles;
        int                 n = (int)lua_objlen(L, 1);
        for (int i = 1; i <= n; i++)
        {
            lua_rawgeti(L, 1, i);
            void* udata = lua_touserdata(L, -1);
            if (udata)
            {
                handles.push_back(*static_cast<HANDLE*>(udata));
            }
            lua_pop(L, 1);
        }

        if (handles.empty())
        {
            lua_pushnil(L);
            lua_pushstring(L, "No valid handles provided.");
            return 2;
        }

        ULONGLONG start_time = GetTickCount64();

        while (true)
        {
            ULONGLONG elapsed        = GetTickCount64() - start_time;
            DWORD     remaining_time = (timeout_dw == INFINITE || elapsed < timeout_dw)
                                           ? (timeout_dw == INFINITE ? INFINITE : timeout_dw - (DWORD)elapsed)
                                           : 0;

            DWORD wait_result =
                MsgWaitForMultipleObjects((DWORD)handles.size(), handles.data(), FALSE, remaining_time, QS_ALLINPUT);

            if (wait_result >= WAIT_OBJECT_0 && wait_result < (WAIT_OBJECT_0 + handles.size()))
            {
                lua_pushinteger(L, wait_result - WAIT_OBJECT_0 + 1);
                return 1;
            }

            if (wait_result == (WAIT_OBJECT_0 + handles.size()))
            {
                MSG msg;
                while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
                {
                    if (msg.message == WM_QUIT)
                    {
                        lua_pushnil(L);
                        lua_pushstring(L, "WM_QUIT received.");
                        return 2;
                    }
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
            }
            else
            {
                lua_pushnil(L);
                lua_pushstring(L, "Wait timed out or failed.");
                return 2;
            }

            if (remaining_time == 0 && timeout_dw != INFINITE)
            {
                lua_pushnil(L);
                lua_pushstring(L, "Wait timed out.");
                return 2;
            }
        }
    }
    static int pesh_post_quit_message(lua_State* L)
    {
        int exit_code = (int)luaL_optinteger(L, 1, 0);
        PostQuitMessage(exit_code);
        return 0;
    }
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

lua_State* InitializeLuaState(const std::string& exe_dir)
{
    lua_State* L = luaL_newstate();
    if (!L)
    {
        spdlog::critical("Failed to create Lua state.");
        return nullptr;
    }
    luaL_openlibs(L);

    luaL_newmetatable(L, PROCESS_HANDLE_METATABLE);
    lua_pushcfunction(L, LuaBindings::process_handle_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);

    luaL_newmetatable(L, EVENT_HANDLE_METATABLE);
    lua_pushcfunction(L, LuaBindings::event_handle_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);

    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");
    lua_pushcfunction(L, luaopen_lfs);
    lua_setfield(L, -2, "lfs");
    lua_pop(L, 2);

    static const struct luaL_Reg pesh_native_lib[] = {
        {"sleep", LuaBindings::pesh_sleep},
        {"get_current_pid", LuaBindings::pesh_get_current_pid},
        {"get_exe_path", LuaBindings::pesh_get_exe_path},
        {"find_all_processes", LuaBindings::pesh_find_all_processes},
        {"create_process", LuaBindings::pesh_create_process},
        {"open_process_by_name", LuaBindings::pesh_open_process_by_name},
        {"commandline_to_argv", LuaBindings::pesh_commandline_to_argv},
        {"close_handle", LuaBindings::pesh_close_handle},
        {"process_exists", LuaBindings::pesh_process_exists},
        {"process_close", LuaBindings::pesh_process_close},
        {"process_close_tree", LuaBindings::pesh_process_close_tree},
        {"fs_copy", LuaBindings::pesh_fs_copy},
        {"fs_mkdirs", LuaBindings::pesh_fs_mkdirs},
        {"create_event", LuaBindings::pesh_create_event},
        {"open_event", LuaBindings::pesh_open_event},
        {"set_event", LuaBindings::pesh_set_event},
        {"post_quit_message", LuaBindings::pesh_post_quit_message},
        {"wait_for_multiple_objects", LuaBindings::pesh_wait_for_multiple_objects},
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

int main(int argc, char* argv[])
{
    char exe_path_buf[MAX_PATH];
    GetModuleFileNameA(NULL, exe_path_buf, MAX_PATH);
    std::string exe_path   = exe_path_buf;
    size_t      last_slash = exe_path.find_last_of("\\/");
    std::string exe_dir    = (std::string::npos != last_slash) ? exe_path.substr(0, last_slash) : ".";

    InitializeLogger(exe_dir);
    spdlog::info("PEShell v3.1 [Guardian IPC Fix] starting...");
    spdlog::info("Executable directory: {}", exe_dir);

    lua_State* L = InitializeLuaState(exe_dir);
    if (!L)
    {
        return 1;
    }

    if (luaL_dofile(L, (exe_dir + "\\scripts\\prelude.lua").c_str()) != LUA_OK)
    {
        const char* error_msg = lua_tostring(L, -1);
        spdlog::critical("Failed to load prelude script (prelude.lua): {}", error_msg);
        MessageBoxA(NULL, error_msg, "PEShell Critical Error", MB_ICONERROR | MB_OK);
        lua_close(L);
        return 1;
    }

    int  return_code  = 0;
    bool is_main_mode = (argc > 1 && strcmp(argv[1], "main") == 0);

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
        int num_args_to_push = argc - 2;
        for (int i = 2; i < argc; ++i)
        {
            lua_pushstring(L, argv[i]);
        }

        if (lua_pcall(L, num_args_to_push, 1, 0) != LUA_OK)
        {
            const char* error_msg = lua_tostring(L, -1);
            spdlog::critical("Error executing command '{}': {}", sub_command, error_msg);
            MessageBoxA(NULL, error_msg, "PEShell Lua Error", MB_ICONERROR | MB_OK);
            return_code = 1;
        }
        else
        {
            if (lua_isnumber(L, -1))
            {
                return_code = (int)lua_tointeger(L, -1);
            }
            lua_pop(L, 1);
        }
    }

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