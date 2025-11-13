#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <iostream>
#include <string>
#include <vector>

// Lua / LuaJIT
#include <lua.hpp>

// LuaFileSystem
#include <lfs.h>

// 我们的进程工具库
#include <proc_utils.h>

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

} // namespace LuaBindings

// ------------------------------------------------------------------
// 主程序入口
// ------------------------------------------------------------------

// 为 Release 模式设置 WinMain 入口，避免黑框
#if defined(NDEBUG) || defined(_NDEBUG)
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
#else
int main(int argc, char* argv[])
#endif
{
    // 1. 初始化 LuaJIT
    lua_State* L = luaL_newstate();
    if (!L)
    {
        MessageBoxA(NULL, "Failed to create Lua state.", "PEShell Critical Error", MB_ICONERROR | MB_OK);
        return 1;
    }
    luaL_openlibs(L); // 加载标准库

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

    // 3. 注册我们自己的 C++ 函数到全局表 `pesh_native`
    static const struct luaL_Reg pesh_native_lib[] = {
        {"sleep", LuaBindings::pesh_sleep},
        {"process_exists", LuaBindings::pesh_process_exists},
        {"process_close", LuaBindings::pesh_process_close},
        {"process_wait_close", LuaBindings::pesh_process_wait_close},
        {"exec", LuaBindings::pesh_exec},
        {NULL, NULL} // 哨兵
    };
    lua_newtable(L);
    luaL_setfuncs(L, pesh_native_lib, 0);
    lua_setglobal(L, "pesh_native");

    // 4. 智能定位脚本路径并设置 Lua 的 package.path
    char exe_path_buf[MAX_PATH];
    GetModuleFileNameA(NULL, exe_path_buf, MAX_PATH);
    std::string exe_path = exe_path_buf;

    size_t      last_slash = exe_path.find_last_of("\\/");
    std::string exe_dir    = (std::string::npos != last_slash) ? exe_path.substr(0, last_slash) : ".";

    // 构造 init.lua 的完整路径
    std::string init_script_path = exe_dir + "\\scripts\\init.lua";

    // 构造 scripts 目录的路径，并添加到 package.path
    std::string scripts_path = exe_dir + "\\scripts";

    // Lua 路径需要使用双反斜杠作为分隔符
    size_t pos = 0;
    while ((pos = scripts_path.find('\\', pos)) != std::string::npos)
    {
        scripts_path.replace(pos, 1, "\\\\");
        pos += 2;
    }

    // 更新 package.path，使其能找到 `pesh-api` 目录下的模块
    std::string package_path_update = "package.path = package.path .. ';" + scripts_path + "\\\\?.lua'";
    luaL_dostring(L, package_path_update.c_str());

    // 5. 执行入口脚本
    int result = luaL_dofile(L, init_script_path.c_str());

    if (result != LUA_OK)
    {
        const char* error_msg = lua_tostring(L, -1);
        std::cerr << "Lua script error: " << error_msg << std::endl;
        MessageBoxA(NULL, error_msg, "PEShell Lua Error", MB_ICONERROR | MB_OK);
    }

    // 6. 关闭 LuaJIT
    lua_close(L);

    return (result == LUA_OK) ? 0 : 1;
}