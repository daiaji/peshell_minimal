#include "logging.h"

// clang-format off
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <timeapi.h>
// clang-format on

#include <ctpl_stl.h>
#include <spdlog/spdlog.h>

#include <filesystem>
#include <fstream> 
#include <iostream>
#include <lua.hpp>
#include <map>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

#ifndef LUA_TCDATA
#define LUA_TCDATA 10
#endif

#if defined(LUA_JITLIBNAME) && defined(OPENRESTY_LUAJIT)
#define HAVE_LUA_RESETTHREAD 1
#endif

struct AsyncTaskResult
{
    lua_State*  co;
    bool        success;
    std::string data;
    std::string error_msg;
};

struct WaitOperation
{
    lua_State*          co;
    std::vector<HANDLE> handles;
};

std::queue<AsyncTaskResult>     g_completed_tasks;
std::mutex                      g_completed_tasks_mutex;
HANDLE                          g_hTaskCompletedEvent = NULL;
std::vector<HANDLE>             g_wait_handles_cache;
std::map<HANDLE, WaitOperation> g_wait_operations;
std::mutex                      g_wait_operations_mutex;
ctpl::thread_pool               g_thread_pool(std::thread::hardware_concurrency());
static volatile bool            g_handle_list_dirty = true;

lua_State*   InitializeLuaState(const std::string& package_root_dir);
std::wstring Utf8ToWide(const std::string& str);

namespace LuaBindings
{
    struct SafeHandle { HANDLE h; };

    static int pesh_sleep(lua_State* L)
    {
        int duration_ms = (int)luaL_checkinteger(L, 1);
        Sleep(duration_ms);
        return 0;
    }

    static int pesh_dispatch_worker(lua_State* L)
    {
        const char* worker_name = luaL_checkstring(L, 1);

        if (strcmp(worker_name, "file_copy_worker") == 0)
        {
            std::string src_path(luaL_checkstring(L, 2));
            std::string dst_path(luaL_checkstring(L, 3));
            lua_State*  co_to_wake = lua_tothread(L, 4);

            g_thread_pool.push([src_path, dst_path, co_to_wake](int id) {
                (void)id; 
                spdlog::debug("WORKER: Async copy '{}' -> '{}'", src_path, dst_path);
                BOOL copy_success = CopyFileW(Utf8ToWide(src_path).c_str(), Utf8ToWide(dst_path).c_str(), FALSE);

                std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                if (copy_success) g_completed_tasks.push({co_to_wake, true, "Copy successful", ""});
                else g_completed_tasks.push({co_to_wake, false, "", "Copy failed: " + std::to_string(GetLastError())});
                SetEvent(g_hTaskCompletedEvent);
            });
        }
        else if (strcmp(worker_name, "file_read_worker") == 0)
        {
            std::string filepath(luaL_checkstring(L, 2));
            lua_State*  co_to_wake = lua_tothread(L, 3);

            g_thread_pool.push([filepath, co_to_wake](int id) {
                (void)id;
                spdlog::debug("WORKER: Async read '{}'", filepath);
                std::ifstream file(Utf8ToWide(filepath), std::ios::binary | std::ios::ate);
                if (file) {
                    std::streamsize size = file.tellg();
                    file.seekg(0, std::ios::beg);
                    std::string buffer(size, '\0');
                    if (file.read(&buffer[0], size)) {
                        std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                        g_completed_tasks.push({co_to_wake, true, std::move(buffer), ""});
                    } else {
                        std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                        g_completed_tasks.push({co_to_wake, false, "", "File read failed: " + filepath});
                    }
                } else {
                    std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                    g_completed_tasks.push({co_to_wake, false, "", "File open failed: " + filepath});
                }
                SetEvent(g_hTaskCompletedEvent);
            });
        }
        else if (strcmp(worker_name, "timer_worker") == 0)
        {
            int duration_ms = (int)luaL_checkinteger(L, 2);
            lua_State* co_to_wake = lua_tothread(L, 3);
            g_thread_pool.push([duration_ms, co_to_wake](int id) {
                (void)id;
                Sleep(duration_ms);
                std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                g_completed_tasks.push({co_to_wake, true, "Timer expired", ""});
                SetEvent(g_hTaskCompletedEvent);
            });
        }
        return 0;
    }

    static int pesh_wait_for_multiple_objects_async(lua_State* L)
    {
        lua_State* co = lua_tothread(L, 1);
        if (!co) return luaL_error(L, "Arg 1 must be a coroutine");
        if (!lua_istable(L, 2)) return luaL_error(L, "Arg 2 must be a table of FFI SafeHandles");

        WaitOperation op;
        op.co = co;

        lua_pushnil(L);
        while (lua_next(L, 2) != 0) {
            if (lua_type(L, -1) == LUA_TCDATA) {
                auto* handle_obj = static_cast<SafeHandle*>(const_cast<void*>(lua_topointer(L, -1)));
                if (handle_obj && handle_obj->h) op.handles.push_back(handle_obj->h);
            }
            lua_pop(L, 1);
        }

        if (op.handles.empty()) {
            lua_pushboolean(co, false);
            lua_pushstring(co, "No valid handles provided.");
            lua_resume(co, 2);
            return 0;
        }

        {
            std::lock_guard<std::mutex> lock(g_wait_operations_mutex);
            for (HANDLE h : op.handles) g_wait_operations[h] = op;
            g_handle_list_dirty = true;
        }
        return 0;
    }

    static int pesh_wait_for_multiple_objects_blocking(lua_State* L)
    {
        if (!lua_istable(L, 1)) return luaL_error(L, "Arg 1 must be table");
        int timeout_ms = (int)luaL_optinteger(L, 2, -1);
        DWORD timeout_dw = (timeout_ms < 0) ? INFINITE : (DWORD)timeout_ms;

        std::vector<HANDLE> handles;
        lua_pushnil(L);
        while (lua_next(L, 1) != 0) {
            if (lua_type(L, -1) == LUA_TCDATA) {
                auto* handle_obj = static_cast<SafeHandle*>(const_cast<void*>(lua_topointer(L, -1)));
                if (handle_obj && handle_obj->h) handles.push_back(handle_obj->h);
            }
            lua_pop(L, 1);
        }

        if (handles.empty()) { lua_pushnil(L); lua_pushstring(L, "No handles"); return 2; }

        DWORD res = WaitForMultipleObjects((DWORD)handles.size(), handles.data(), FALSE, timeout_dw);
        if (res >= WAIT_OBJECT_0 && res < (WAIT_OBJECT_0 + handles.size())) {
            lua_pushinteger(L, res - WAIT_OBJECT_0 + 1);
            return 1;
        } else if (res == WAIT_TIMEOUT) {
            lua_pushnil(L); lua_pushstring(L, "Timeout"); return 2;
        } else {
            lua_pushnil(L); lua_pushstring(L, "Failed"); return 2;
        }
    }

    static int pesh_reset_thread(lua_State* L)
    {
#ifdef HAVE_LUA_RESETTHREAD
        if (!lua_isthread(L, 1)) return luaL_argerror(L, 1, "thread expected");
        lua_resetthread(L, lua_tothread(L, 1));
        lua_pushboolean(L, 1);
#else
        lua_pushboolean(L, 0);
#endif
        return 1;
    }

#define DEFINE_LOG_FUNC(name, level) \
    static int pesh_log_##name(lua_State* L) { spdlog::level(luaL_checkstring(L, 1)); return 0; }

    DEFINE_LOG_FUNC(trace, trace)
    DEFINE_LOG_FUNC(debug, debug)
    DEFINE_LOG_FUNC(info, info)
    DEFINE_LOG_FUNC(warn, warn)
    DEFINE_LOG_FUNC(error, error)
    DEFINE_LOG_FUNC(critical, critical)
}

lua_State* InitializeLuaState(const std::string& package_root_dir)
{
    lua_State* L = luaL_newstate();
    if (!L) { spdlog::critical("Failed to create Lua state."); return nullptr; }
    luaL_openlibs(L);

    static const struct luaL_Reg pesh_native_lib[] = {
        {"sleep", LuaBindings::pesh_sleep},
        {"wait_for_multiple_objects", LuaBindings::pesh_wait_for_multiple_objects_async},
        {"wait_for_multiple_objects_blocking", LuaBindings::pesh_wait_for_multiple_objects_blocking},
        {"dispatch_worker", LuaBindings::pesh_dispatch_worker},
        {"reset_thread", LuaBindings::pesh_reset_thread},
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

    std::filesystem::path exe_dir = std::filesystem::path(package_root_dir) / "bin";
    lua_pushstring(L, exe_dir.string().c_str());
    lua_setglobal(L, "PESHELL_EXE_DIR");

    return L;
}

int main(int argc, char* argv[])
{
    timeBeginPeriod(1);
    DWORD pid = GetCurrentProcessId();
    char exe_path_buf[MAX_PATH];
    GetModuleFileNameA(NULL, exe_path_buf, MAX_PATH);
    std::filesystem::path package_root = std::filesystem::path(exe_path_buf).parent_path().parent_path();
    std::string package_root_str = package_root.string();

    InitializeLogger(package_root_str, pid, argc, argv);
    spdlog::info("PEShell v7.0 (Lua-Ext) starting...");

    lua_State* L = InitializeLuaState(package_root_str);
    if (!L) { ShutdownLogger(); return 1; }

    g_hTaskCompletedEvent = CreateEvent(NULL, FALSE, FALSE, NULL);

    std::string prelude_path = (package_root / "share" / "lua" / "5.1" / "prelude.lua").string();
    if (luaL_dofile(L, prelude_path.c_str()) != LUA_OK) {
        spdlog::critical("Failed to load prelude: {}", lua_tostring(L, -1));
        lua_close(L);
        ShutdownLogger();
        return 1;
    }

    lua_getglobal(L, "DispatchCommand");
    for (int i = 1; i < argc; ++i) lua_pushstring(L, argv[i]);

    int return_code = 0;
    if (lua_pcall(L, argc - 1, 1, 0) != LUA_OK) {
        spdlog::critical("Dispatcher error: {}", lua_tostring(L, -1));
        return_code = 1;
    } else {
        return_code = lua_isnumber(L, -1) ? (int)lua_tointeger(L, -1) : 0;
        lua_pop(L, 1);
    }

    bool is_main_mode = (argc > 1 && strcmp(argv[1], "main") == 0);
    if (is_main_mode && return_code == 0)
    {
        spdlog::info("Entering persistent loop.");
        MSG msg;
        bool is_running = true;
        while (is_running)
        {
            if (g_handle_list_dirty) {
                std::lock_guard<std::mutex> lock(g_wait_operations_mutex);
                g_wait_handles_cache.clear();
                g_wait_handles_cache.push_back(g_hTaskCompletedEvent);
                for (auto const& [handle, op] : g_wait_operations) g_wait_handles_cache.push_back(handle);
                g_handle_list_dirty = false;
            }

            DWORD res = MsgWaitForMultipleObjects((DWORD)g_wait_handles_cache.size(), g_wait_handles_cache.data(), FALSE, INFINITE, QS_ALLINPUT);

            if (res >= WAIT_OBJECT_0 && res < (WAIT_OBJECT_0 + g_wait_handles_cache.size()))
            {
                HANDLE h = g_wait_handles_cache[res - WAIT_OBJECT_0];
                if (h == g_hTaskCompletedEvent) {
                    std::queue<AsyncTaskResult> tasks;
                    { std::lock_guard<std::mutex> lock(g_completed_tasks_mutex); tasks.swap(g_completed_tasks); }
                    while (!tasks.empty()) {
                        AsyncTaskResult r = tasks.front(); tasks.pop();
                        if (lua_status(r.co) != LUA_YIELD) continue;
                        lua_pushboolean(r.co, r.success);
                        if(r.success) lua_pushlstring(r.co, r.data.c_str(), r.data.length());
                        else lua_pushstring(r.co, r.error_msg.c_str());
                        lua_resume(r.co, 2);
                    }
                } else {
                    WaitOperation op;
                    bool found = false;
                    {
                        std::lock_guard<std::mutex> lock(g_wait_operations_mutex);
                        if (g_wait_operations.count(h)) {
                            op = g_wait_operations.at(h);
                            for (HANDLE hh : op.handles) g_wait_operations.erase(hh);
                            g_handle_list_dirty = true;
                            found = true;
                        }
                    }
                    if (found && lua_status(op.co) == LUA_YIELD) {
                        lua_pushboolean(op.co, true);
                        int idx = 0;
                        for(size_t i=0; i<op.handles.size(); ++i) if(op.handles[i]==h) { idx=i+1; break; }
                        lua_pushinteger(op.co, idx);
                        lua_resume(op.co, 2);
                    }
                }
            }
            else if (res == (WAIT_OBJECT_0 + g_wait_handles_cache.size())) {
                while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
                    if (msg.message == WM_QUIT) { is_running = false; break; }
                    TranslateMessage(&msg); DispatchMessage(&msg);
                }
            }
        }
    }

    g_thread_pool.stop(true);
    if (g_hTaskCompletedEvent) CloseHandle(g_hTaskCompletedEvent);
    if (L) lua_close(L);
    ShutdownLogger();
    timeEndPeriod(1);
    return return_code;
}

std::wstring Utf8ToWide(const std::string& str)
{
    if (str.empty()) return std::wstring();
    int size = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstr(size, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstr[0], size);
    return wstr;
}