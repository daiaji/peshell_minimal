/*****************************************************************
 *                    !! IMPORTANT !!                            *
 *   WINDOWS HEADERS MUST BE INCLUDED FIRST to avoid conflicts.    *
 *****************************************************************/
// clang-format off
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <timeapi.h> // For timeBeginPeriod/timeEndPeriod
// clang-format on

/*****************************************************************
 *                 Third-party Library Headers                   *
 *****************************************************************/
#include <ctpl_stl.h>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/spdlog.h>

#include <chrono>
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

// =================================================================================
//  异步任务调度器核心数据结构
// =================================================================================
struct AsyncTaskResult
{
    lua_State*  co;
    bool        success;
    std::string data;
    std::string error;
};

struct WaitOperation
{
    lua_State*          co;
    std::vector<HANDLE> handles;
};

// 全局状态
std::queue<AsyncTaskResult>    g_completed_tasks;
std::mutex                     g_completed_tasks_mutex;
HANDLE                         g_hTaskCompletedEvent = NULL;
std::vector<HANDLE>            g_wait_handles_cache;
std::map<HANDLE, WaitOperation> g_wait_operations;
std::mutex                     g_wait_operations_mutex;
ctpl::thread_pool              g_thread_pool(std::thread::hardware_concurrency());
static volatile bool           g_handle_list_dirty = true;

// 函数前置声明
void         InitializeLogger(const std::string& log_dir);
lua_State*   InitializeLuaState(const std::string& package_root_dir);
std::wstring Utf8ToWide(const std::string& str);

namespace LuaBindings
{
    // =================================================================================
    //  CORE C++ BINDINGS
    // =================================================================================

    struct SafeHandle
    {
        HANDLE h;
    };

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
                spdlog::debug("WORKER (thread {}): Starting async copy from '{}' to '{}'", id, src_path, dst_path);
                BOOL copy_success = CopyFileW(Utf8ToWide(src_path).c_str(), Utf8ToWide(dst_path).c_str(), FALSE);

                std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                if (copy_success)
                {
                    g_completed_tasks.push({co_to_wake, true, "Copy successful", ""});
                }
                else
                {
                    DWORD       error_code = GetLastError();
                    std::string err_msg    = "Copy failed with Win32 error code: " + std::to_string(error_code);
                    g_completed_tasks.push({co_to_wake, false, "", err_msg});
                }
                SetEvent(g_hTaskCompletedEvent);
            });
        }
        else if (strcmp(worker_name, "file_read_worker") == 0)
        {
            std::string filepath(luaL_checkstring(L, 2));
            lua_State*  co_to_wake = lua_tothread(L, 3);

            g_thread_pool.push([filepath, co_to_wake](int id) {
                spdlog::debug("WORKER (thread {}): Starting async read from '{}'", id, filepath);

                std::ifstream file(Utf8ToWide(filepath), std::ios::binary | std::ios::ate);
                if (file)
                {
                    std::streamsize size = file.tellg();
                    file.seekg(0, std::ios::beg);
                    std::string buffer(size, '\0');
                    if (file.read(&buffer[0], size))
                    {
                        std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                        g_completed_tasks.push({co_to_wake, true, std::move(buffer), ""});
                    }
                    else
                    {
                        std::string                 err_msg = "File read failed for: " + filepath;
                        std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                        g_completed_tasks.push({co_to_wake, false, "", err_msg});
                    }
                }
                else
                {
                    std::string                 err_msg = "File open failed for: " + filepath;
                    std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                    g_completed_tasks.push({co_to_wake, false, "", err_msg});
                }
                SetEvent(g_hTaskCompletedEvent);
            });
        }
        else if (strcmp(worker_name, "process_wait_worker") == 0)
        {
            if (lua_type(L, 2) != LUA_TCDATA) return luaL_error(L, "Arg 2 must be a process handle (cdata)");
            lua_State* co_to_wake = lua_tothread(L, 3);
            auto*      handle_obj = static_cast<SafeHandle*>(const_cast<void*>(lua_topointer(L, 2)));

            if (!handle_obj || !handle_obj->h)
            {
                std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                g_completed_tasks.push({co_to_wake, false, "", "Invalid or closed process handle provided."});
                SetEvent(g_hTaskCompletedEvent);
                return 0;
            }

            HANDLE hProcess = handle_obj->h;

            g_thread_pool.push([hProcess, co_to_wake](int id) {
                spdlog::debug("WORKER (thread {}): Starting async wait for process handle {:p}", id, (void*)hProcess);
                DWORD waitResult = WaitForSingleObject(hProcess, INFINITE);

                std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                if (waitResult == WAIT_OBJECT_0)
                {
                    g_completed_tasks.push({co_to_wake, true, "Process exited", ""});
                }
                else
                {
                    DWORD       error_code = GetLastError();
                    std::string err_msg = "WaitForSingleObject failed with Win32 error: " + std::to_string(error_code);
                    g_completed_tasks.push({co_to_wake, false, "", err_msg});
                }
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
        while (lua_next(L, 2) != 0)
        {
            if (lua_type(L, -1) == LUA_TCDATA)
            {
                auto* handle_obj = static_cast<SafeHandle*>(const_cast<void*>(lua_topointer(L, -1)));
                if (handle_obj && handle_obj->h)
                {
                    op.handles.push_back(handle_obj->h);
                }
            }
            lua_pop(L, 1);
        }

        if (op.handles.empty())
        {
            lua_pushboolean(co, false);
            lua_pushstring(co, "No valid handles provided to wait on.");
            int status = lua_resume(co, 2);
            if (status != LUA_OK && status != LUA_YIELD)
            {
                spdlog::error("Error resuming coroutine with empty handle error: {}", lua_tostring(co, -1));
            }
            return 0;
        }

        {
            std::lock_guard<std::mutex> lock(g_wait_operations_mutex);
            for (HANDLE h : op.handles)
            {
                g_wait_operations[h] = op;
            }
            g_handle_list_dirty = true;
        }

        spdlog::trace("SCHEDULER: Coroutine {:p} is now waiting on {} handle(s).", (void*)co, op.handles.size());
        return 0;
    }

    static int pesh_wait_for_multiple_objects_blocking(lua_State* L)
    {
        if (!lua_istable(L, 1)) return luaL_error(L, "Arg 1 must be a table of FFI SafeHandles");
        int   timeout_ms = (int)luaL_optinteger(L, 2, -1);
        DWORD timeout_dw = (timeout_ms < 0) ? INFINITE : (DWORD)timeout_ms;

        std::vector<HANDLE> handles;
        lua_pushnil(L);
        while (lua_next(L, 1) != 0)
        {
            if (lua_type(L, -1) == LUA_TCDATA)
            {
                auto* handle_obj = static_cast<SafeHandle*>(const_cast<void*>(lua_topointer(L, -1)));
                if (handle_obj && handle_obj->h)
                {
                    handles.push_back(handle_obj->h);
                }
            }
            lua_pop(L, 1);
        }

        if (handles.empty())
        {
            lua_pushnil(L);
            lua_pushstring(L, "No valid handles provided to wait on.");
            return 2;
        }

        DWORD wait_result = WaitForMultipleObjects((DWORD)handles.size(), handles.data(), FALSE, timeout_dw);

        if (wait_result >= WAIT_OBJECT_0 && wait_result < (WAIT_OBJECT_0 + handles.size()))
        {
            lua_pushinteger(L, wait_result - WAIT_OBJECT_0 + 1);
            return 1;
        }
        else if (wait_result == WAIT_TIMEOUT)
        {
            lua_pushnil(L);
            lua_pushstring(L, "Wait timed out.");
            return 2;
        }
        else
        {
            lua_pushnil(L);
            lua_pushstring(L, ("Wait failed with Win32 error code: " + std::to_string(GetLastError())).c_str());
            return 2;
        }
    }


    static int pesh_reset_thread(lua_State* L)
    {
#ifdef HAVE_LUA_RESETTHREAD
        if (!lua_isthread(L, 1)) return luaL_argerror(L, 1, "thread expected");
        lua_State* co = lua_tothread(L, 1);
        lua_resetthread(L, co);
        lua_pushboolean(L, 1);
#else
        spdlog::warn("lua_resetthread is not available in this LuaJIT build.");
        lua_pushboolean(L, 0);
#endif
        return 1;
    }

#define DEFINE_LOG_FUNC(name, level)                                     \
    static int pesh_log_##name(lua_State* L)                             \
    {                                                                    \
        spdlog::level(luaL_checkstring(L, 1)); \
        return 0;                                                        \
    }

    DEFINE_LOG_FUNC(trace, trace)
    DEFINE_LOG_FUNC(debug, debug)
    DEFINE_LOG_FUNC(info, info)
    DEFINE_LOG_FUNC(warn, warn)
    DEFINE_LOG_FUNC(error, error)
    DEFINE_LOG_FUNC(critical, critical)

} // namespace LuaBindings

lua_State* InitializeLuaState(const std::string& package_root_dir)
{
    lua_State* L = luaL_newstate();
    if (!L)
    {
        spdlog::critical("Failed to create Lua state.");
        return nullptr;
    }
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

    // [[ 核心修正 ]]
    // 将 EXE 所在的目录（即 bin 目录）传递给 Lua，而不是整个包的根目录。
    // prelude.lua 将基于此进行相对路径计算。
    std::filesystem::path exe_dir = std::filesystem::path(package_root_dir) / "bin";
    lua_pushstring(L, exe_dir.string().c_str());
    lua_setglobal(L, "PESHELL_EXE_DIR");

    return L;
}

int main(int argc, char* argv[])
{
    timeBeginPeriod(1);

    char exe_path_buf[MAX_PATH];
    GetModuleFileNameA(NULL, exe_path_buf, MAX_PATH);
    std::filesystem::path exe_fs_path(exe_path_buf);
    std::filesystem::path bin_dir = exe_fs_path.parent_path();
    // [[ 核心修正 ]]
    // 包的根目录现在是 bin 目录的父目录。
    std::filesystem::path package_root = bin_dir.parent_path();
    std::string           package_root_str = package_root.string();

    InitializeLogger(package_root_str);
    spdlog::info("PEShell v5.5 (Self-Contained Package Model) starting...");
    spdlog::info("Package Root: {}", package_root_str);

    lua_State* L = InitializeLuaState(package_root_str);
    if (!L) return 1;

    g_hTaskCompletedEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
    if (!g_hTaskCompletedEvent)
    {
        spdlog::critical("Failed to create task completion event.");
        lua_close(L);
        return 1;
    }

    // [[ 核心修正 ]]
    // 直接构建出自包含结构下的 prelude.lua 路径，不再需要任何回退逻辑。
    std::string prelude_path = (package_root / "share" / "lua" / "5.1" / "prelude.lua").string();
    
    spdlog::info("Attempting to load prelude from: {}", prelude_path);
    if (luaL_dofile(L, prelude_path.c_str()) != LUA_OK)
    {
        const char* error_msg = lua_tostring(L, -1);
        spdlog::critical("Failed to load prelude script '{}': {}", prelude_path, error_msg);
        MessageBoxA(NULL, error_msg, "PEShell Critical Error", MB_ICONERROR | MB_OK);
        lua_close(L);
        return 1;
    }

    lua_getglobal(L, "DispatchCommand");
    for (int i = 1; i < argc; ++i)
    {
        lua_pushstring(L, argv[i]);
    }

    int return_code = 0;
    if (lua_pcall(L, argc - 1, 1, 0) != LUA_OK)
    {
        const char* error_msg = lua_tostring(L, -1);
        spdlog::critical("Error executing command dispatcher: {}", error_msg);
        return_code = 1;
    }
    else
    {
        return_code = lua_isnumber(L, -1) ? (int)lua_tointeger(L, -1) : 0;
        lua_pop(L, 1);
    }

    bool is_main_mode = (argc > 1 && strcmp(argv[1], "main") == 0);
    if (is_main_mode && return_code == 0)
    {
        spdlog::info("Entering persistent message and task loop.");
        MSG  msg;
        bool is_running = true;
        while (is_running)
        {
            if (g_handle_list_dirty)
            {
                std::lock_guard<std::mutex> lock(g_wait_operations_mutex);
                g_wait_handles_cache.clear();
                g_wait_handles_cache.push_back(g_hTaskCompletedEvent);
                for (auto const& [handle, op] : g_wait_operations)
                {
                    g_wait_handles_cache.push_back(handle);
                }
                g_handle_list_dirty = false;
                spdlog::trace("SCHEDULER: Refreshed wait list, now waiting on {} handles.", g_wait_handles_cache.size());
            }

            DWORD wait_result = MsgWaitForMultipleObjects(
                static_cast<DWORD>(g_wait_handles_cache.size()), g_wait_handles_cache.data(), FALSE, INFINITE, QS_ALLINPUT);

            if (wait_result >= WAIT_OBJECT_0 && wait_result < (WAIT_OBJECT_0 + g_wait_handles_cache.size()))
            {
                HANDLE signaled_handle = g_wait_handles_cache[wait_result - WAIT_OBJECT_0];

                if (signaled_handle == g_hTaskCompletedEvent)
                {
                    std::queue<AsyncTaskResult> tasks_to_process;
                    {
                        std::lock_guard<std::mutex> lock(g_completed_tasks_mutex);
                        tasks_to_process.swap(g_completed_tasks);
                    }
                    while (!tasks_to_process.empty())
                    {
                        AsyncTaskResult result = tasks_to_process.front();
                        tasks_to_process.pop();
                        if (lua_status(result.co) != LUA_YIELD)
                        {
                            spdlog::warn("Coroutine {:p} is not in a yield state, cannot resume.", (void*)result.co);
                            continue;
                        }

                        int resume_status = 0;
                        if (result.success)
                        {
                            lua_pushboolean(result.co, true);
                            lua_pushlstring(result.co, result.data.c_str(), result.data.length());
                            resume_status = lua_resume(result.co, 2);
                        }
                        else
                        {
                            lua_pushboolean(result.co, false);
                            lua_pushstring(result.co, result.error.c_str());
                            resume_status = lua_resume(result.co, 2);
                        }

                        if (resume_status != LUA_YIELD && resume_status != LUA_OK)
                        {
                            spdlog::error("Error resuming coroutine after async task: {}",
                                          lua_tostring(result.co, -1));
                        }
                    }
                }
                else
                {
                    WaitOperation op_to_resume;
                    bool          found = false;
                    {
                        std::lock_guard<std::mutex> lock(g_wait_operations_mutex);
                        if (g_wait_operations.count(signaled_handle))
                        {
                            op_to_resume = g_wait_operations.at(signaled_handle);
                            for (HANDLE h : op_to_resume.handles)
                            {
                                g_wait_operations.erase(h);
                            }
                            g_handle_list_dirty = true;
                            found               = true;
                        }
                    }

                    if (found)
                    {
                        if (lua_status(op_to_resume.co) != LUA_YIELD)
                        {
                            spdlog::warn("Coroutine {:p} is not in a yield state, cannot resume.",
                                         (void*)op_to_resume.co);
                            continue;
                        }
                        spdlog::trace("SCHEDULER: Resuming coroutine {:p} due to handle signal.",
                                      (void*)op_to_resume.co);
                        lua_pushboolean(op_to_resume.co, true);
                        int signaled_idx = 0;
                        for (size_t i = 0; i < op_to_resume.handles.size(); ++i)
                        {
                            if (op_to_resume.handles[i] == signaled_handle)
                            {
                                signaled_idx = i + 1;
                                break;
                            }
                        }
                        lua_pushinteger(op_to_resume.co, signaled_idx);

                        int resume_status = lua_resume(op_to_resume.co, 2);
                        if (resume_status != LUA_YIELD && resume_status != LUA_OK)
                        {
                            spdlog::error("Error resuming coroutine: {}", lua_tostring(op_to_resume.co, -1));
                        }
                    }
                }
            }
            else if (wait_result == (WAIT_OBJECT_0 + g_wait_handles_cache.size()))
            {
                while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
                {
                    if (msg.message == WM_QUIT)
                    {
                        is_running = false;
                        break;
                    }
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
            }
            else
            {
                spdlog::error("MsgWaitForMultipleObjects returned an unexpected value: {}. Error code: {}",
                              wait_result,
                              GetLastError());
                break;
            }
        }
        spdlog::info("Scheduler loop is terminating due to WM_QUIT or an error.");
    }

    g_thread_pool.stop(true);
    CloseHandle(g_hTaskCompletedEvent);
    timeEndPeriod(1);
    lua_close(L);
    spdlog::info("PEShell shutting down with exit code {}.", return_code);
    return return_code;
}

void InitializeLogger(const std::string& package_root_dir)
{
    try
    {
        std::vector<spdlog::sink_ptr> sinks;
        auto                          console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
        console_sink->set_level(spdlog::level::trace);
        sinks.push_back(console_sink);
        
        std::filesystem::path log_path = std::filesystem::path(package_root_dir) / "logs";
        std::filesystem::create_directory(log_path);
        auto file_sink =
            std::make_shared<spdlog::sinks::basic_file_sink_mt>((log_path / "peshell_latest.log").string(), true);
        file_sink->set_level(spdlog::level::trace);
        sinks.push_back(file_sink);

        auto logger = std::make_shared<spdlog::logger>("peshell", begin(sinks), end(sinks));
        logger->set_level(spdlog::level::trace);
        logger->flush_on(spdlog::level::trace);

        spdlog::set_default_logger(logger);
    }
    catch (const spdlog::spdlog_ex& ex)
    {
        std::cerr << "Log initialization failed: " << ex.what() << std::endl;
    }
}

std::wstring Utf8ToWide(const std::string& str)
{
    if (str.empty()) return std::wstring();
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}