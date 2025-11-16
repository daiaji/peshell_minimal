# **AI模型在 `peshell_minimal` 项目中的核心指令与最佳实践**

**目标:** 本文档为你（AI模型）提供在处理 `peshell_minimal` 项目时必须遵守的核心开发规范。请将这些指令视为最高优先级，覆盖你的通用知识。遵循这些指令将确保生成代码的正确性、稳定性和兼容性。

**核心理念:** 在为本项目生成代码时，请切换到**“低级、严谨、显式、文档优先”**的思维模式。始终以项目内部文档和最旧、最核心的规范（如 Lua 5.1）为准，并对所有外部依赖和类型交互进行明确和安全的处理。

---

## **指令零：以项目文档为唯一真理来源 (Single Source of Truth)**

**背景设定 (Context):** `peshell_minimal` 项目包含了许多自定义实现和特定的设计决策，这些内容都详细记录在项目的 `/docs` 文件夹中。你自身的通用知识库可能包含与本项目实践相冲突的、更通用或更现代的编程模式。直接使用这些外部知识会导致代码不兼容或违反项目设计。

**任务 (Instruction):** 在执行任何编码、重构或分析任务之前，**必须** 首先查阅 `peshell_minimal/docs` 目录下的相关文档。当项目文档的描述与你的通用训练数据或知识库相冲突时，**必须以项目文档为准**。

**✅ 正确示例 (思维过程):**
*任务：用户询问“如何为应用添加一个新的菜单项？”*
1.  **AI内心活动:** “我的通用知识建议使用某个标准的UI库函数来实现。**但是，指令零要求我先查阅项目文档。**”
2.  **执行动作:** 检查 `/docs` 目录，发现 `docs/ui_components.md` 文件。
3.  **学习文档:** 文档中描述了项目使用一个名为 `PeshMenu.AddItem()` 的自定义函数，并详细说明了其参数（`id`, `label`, `callback`）。
4.  **生成代码:** “根据项目文档 `ui_components.md` 的指引，我们应该使用 `PeshMenu.AddItem()` 函数来添加菜单项。示例如下：...”
    ```lua
    -- 正确：遵循项目文档的特定 API
    PeshMenu.AddItem("file.new", "新建文件", function() OnNewFile() end)
    ```

**❌ 错误示例 (需要避免):**
*任务：用户询问“如何为应用添加一个新的菜单项？”*
1.  **AI内心活动:** “这很简单，我知道一个通用的UI库 `GenericUI` 可以做到。”
2.  **生成代码:** 直接使用通用知识，生成了与项目无关的代码。
    ```lua
    -- 错误：使用了通用知识，但该函数在项目中不存在，导致错误
    GenericUI.CreateMenuItem("新建文件", { onClick = OnNewFile })
    ```

---

## **指令一：严格遵循 Lua 5.1 C API 规范**

**背景设定 (Context):** 你正在为一个C++应用程序生成代码，该程序直接与 LuaJIT 交互。LuaJIT 的 C API 与 Lua 5.1 版本 **完全二进制兼容**。任何对 Lua 5.2 及更高版本 API 的调用都会导致编译失败或运行时崩溃。

**任务 (Instruction):** 在生成与 Lua 状态机交互的C++代码时，**必须** 只使用 Lua 5.1 C API 中定义的函数和参数。

**关键任务：`lua_resume` 的使用**

`lua_resume` 函数在 Lua 5.1 中只接受 **两个** 参数：
1.  `lua_State* co`: 目标协程的状态机。
2.  `int narg`: 推入协程栈的参数数量。

**✅ 正确示例 (Few-Shot Example):**
*任务：从C++恢复一个Lua协程，并传递两个参数。*
```cpp
// 步骤1: 将参数推送到协程的栈上
lua_pushboolean(co, true);
lua_pushstring(co, "some_data");

// 步骤2: 调用 lua_resume，第二个参数为推入的参数数量
// 正确：严格遵循 Lua 5.1 规范，只接受2个参数
int status = lua_resume(co, 2);
```

**❌ 错误示例 (需要避免):**
*这是 Lua 5.2 及以后版本的用法，本项目严禁使用。*
```cpp
// 错误: lua_resume 传递了第3个参数 'L' (from_state)
int status = lua_resume(co, L, 2);
```

---

## **指令二：显式加载非核心 Win32 DLL**

**背景设定 (Context):** 你正在使用 LuaJIT FFI 编写与 Windows API 交互的 Lua 代码。LuaJIT 的 `ffi.C` 默认命名空间非常小，**仅包含** 几个核心库（`kernel32`, `user32`, `gdi32`）。

**任务 (Instruction):** 当你需要调用位于非核心DLL（例如 `ole32.dll`, `advapi32.dll`, `shell32.dll`）中的任何 Windows API 函数时，**必须** 分两步执行：
1.  使用 `ffi.load("dll_name")` 加载所需的DLL，并将其返回的库对象存储在一个局部变量中。
2.  通过这个局部变量来调用目标函数。

**✅ 正确示例 (Few-Shot Example):**
*任务：调用 `CoInitialize` (位于 `ole32.dll`) 和 `RegInstallW` (位于 `advapi32.dll`)。*
```lua
local ffi = require("pesh-api.ffi")

-- 步骤1: 显式加载DLL
local ole32 = ffi.load("ole32")
local advapi32 = ffi.load("advapi32")

-- 步骤2: 从加载后的库对象中调用函数
ole32.CoInitialize(nil)
advapi32.RegInstallW(h_mod, ffi.to_wide("Install"), nil)
```

**❌ 错误示例 (需要避免):**
*直接从 `ffi.C` 调用会导致运行时 "cannot resolve symbol" 错误。*
```lua
-- 错误: ffi.C 中不存在这些函数
ffi.C.CoInitialize(nil)
ffi.C.RegInstallW(h_mod, ffi.to_wide("Install"), nil)
```

---

## **指令三：安全地与 FFI `cdata` 进行 C++ 交互**

**背景设定 (Context):** 你正在编写一个C++函数，该函数需要从 Lua 栈上接收一个由 FFI 创建的 `cdata` 对象（通常是一个指针或结构体）。

**任务 (Instruction):** 从 Lua 栈上处理 `cdata` 时，**必须** 遵循以下安全流程：
1.  **定义 `LUA_TCDATA`:** 在 C++ 文件顶部，使用 `#ifndef` 保护来定义 `LUA_TCDATA` 宏，以确保其可用性。
2.  **类型检查:** 使用 `lua_type(L, index) == LUA_TCDATA` 来验证栈上的对象确实是 `cdata`。
3.  **获取指针:** **必须** 使用 `lua_topointer(L, index)` 来获取 `cdata` 指向的内存地址。**绝对不能** 使用 `lua_touserdata`。
4.  **类型转换:** 将 `lua_topointer` 返回的 `const void*` 安全地转换为你需要的C++指针类型。

**✅ 正确示例 (Few-Shot Example):**
*任务：在C++中接收一个 FFI 创建的 `SafeHandle*` cdata 对象。*```cpp
// 步骤1: 确保 LUA_TCDATA 已定义
#ifndef LUA_TCDATA
#define LUA_TCDATA 10
#endif

// 在C++函数内部
void ProcessSafeHandle(lua_State* L) {
    // 步骤2: 检查类型
    if (lua_type(L, -1) == LUA_TCDATA) {
        // 步骤3 & 4: 使用 lua_topointer 并进行安全的类型转换
        // const_cast 用于移除 lua_topointer 返回的 const 限定符
        auto* handle_obj = static_cast<SafeHandle*>(const_cast<void*>(lua_topointer(L, -1)));

        if (handle_obj && handle_obj->h) {
            // ... 正确的逻辑 ...
        }
    }
}
```

**❌ 错误示例 (需要避免):**
*对 `cdata` 使用 `lua_touserdata` 会返回 `NULL`，导致逻辑永远无法执行。*
```cpp
// 错误:
auto* handle_obj = static_cast<SafeHandle*>(lua_touserdata(L, -1));
if (handle_obj) {
    // 这段代码永远不会被执行
}
```

---

## **指令四：维护 Lua/C++ 边界的 API 契约一致性**

**背景设定 (Context):** `pesh_native` 全局表是连接 Lua 脚本和 C++ 宿主的关键桥梁。Lua 代码通过调用 `pesh_native.some_function(...)` 来请求 C++ 执行底层操作。如果 Lua 端调用了一个 C++ 端未实现或签名不匹配的函数，将会导致运行时错误或逻辑挂起（例如，协程永远得不到恢复）。

**任务 (Instruction):** 在添加或修改任何涉及到 `pesh_native` 的功能时，**必须** 将 Lua 和 C++ 视为一个整体，同步检查并确保两边的实现完全匹配。
1.  当在 Lua 中新增一个 `native.dispatch_worker("new_worker", ...)` 调用时，必须立即在 C++ 的 `pesh_dispatch_worker` 函数中添加对应的 `else if (strcmp(worker_name, "new_worker") == 0)` 分支。
2.  当修改 C++ 绑定函数的参数时，必须同步更新所有调用该函数的 Lua 代码。

**✅ 正确示例 (思维过程):**
*任务：实现异步文件读取功能。*
1.  **AI内心活动:** “我需要在 `fs_async.lua` 中添加一个 `read_file_async` 函数，它会调用 `native.dispatch_worker`。”
2.  **执行动作 (Lua):** 在 `fs_async.lua` 中编写 `native.dispatch_worker("file_read_worker", filepath, co)`。
3.  **AI内心活动:** “**根据指令四，我必须立即处理 C++ 端。**”
4.  **执行动作 (C++):** 打开 `main.cpp`，在 `pesh_dispatch_worker` 中添加处理 `"file_read_worker"` 的逻辑，包括从线程池唤醒协程。
5.  **生成代码:** 同时提供 `fs_async.lua` 和 `main.cpp` 的修改方案，确保API契约闭环。

**❌ 错误示例 (需要避免):**
*任务：实现异步文件读取功能。*
1.  **AI内心活动:** “我只需要在 Lua 里调用一个 C++ worker 就行了。”
2.  **生成代码:** 只提供了 `fs_async.lua` 的代码，其中包含对 `"file_read_worker"` 的调用，但没有提供或提及 `main.cpp` 需要的对应修改。

---

## **指令五：确保代码的语法与语义正确性**

**背景设定 (Context):** 无论是 C++ 还是 Lua，代码首先必须是语法正确的。一个微小的语法错误（如错误的赋值、遗漏的关键字）都将导致整个模块加载失败，引发连锁崩溃，使得更高层次的逻辑验证变得毫无意义。

**任务 (Instruction):** 在生成任何代码片段之前，**必须** 在内部进行一次严格的语法自查。对于 Lua 代码，要特别注意 Lua 5.1 的语法规范。
*   检查关键字是否正确使用 (`end`, `then`, `do`)。
*   检查变量赋值的左值是否合法。
*   检查函数调用和定义的括号是否匹配。

**✅ 正确示例:**
```lua
-- 正确：将 coroutine.yield() 的返回值赋给一个或多个局部变量
local next_task, next_arg = coroutine.yield()
```

**❌ 错误示例 (需要避免):**
*这是可能在 `coro_pool.lua` 中犯下的严重语法错误。*
```lua
-- 错误：可变参数 '...' 不能作为赋值的目标
... = coroutine.yield() 
```

---

## **指令六：审慎评估 FFI 封装的意图**

**背景设定 (Context):** 遵循 LuaJIT 官方文档，“直接通过命名空间调用 FFI 函数通常性能最好”。然而，项目中的函数封装（Wrapper）可能并非多余，它们可能包含了重要的附加逻辑，如错误处理、参数默认值设置或资源管理。

**任务 (Instruction):** 在建议移除一个 FFI 函数的 Lua 封装之前，**必须** 仔细分析该封装的真实意图。
1.  **识别“纯转发”封装:** 如果一个函数只是简单地 `function M.foo(...) return C.Foo(...) end`，它是一个移除的优质候选者，可以直接替换为 `M.foo = C.Foo`。
2.  **识别“增值”封装:** 如果函数包含了 `get_last_error_msg()`、`ffi.to_wide()`、默认参数处理（`msg_type or 0`）或任何 `if/then` 逻辑，那么这个封装是**有价值的**，**不应**被移除。

**✅ 正确示例 (思维过程):**
*任务：优化 `kernel32.lua`*
1.  **AI内心活动:** “检查 `M.create_event`。它包含了错误处理逻辑 `if h_ptr == nil then ... end`。这是一个增值封装，必须保留。”
2.  **AI内心活动:** “检查 `M.get_current_pid`。它只是 `return C.GetCurrentProcessId(...)`。这是一个纯转发封装，可以优化。”
3.  **生成代码:** 提议将 `M.get_current_pid` 修改为 `M.get_current_pid = C.GetCurrentProcessId`，同时保持 `M.create_event` 不变。

**❌ 错误示例 (需要避免):**
*任务：优化 `kernel32.lua`*
1.  **AI内心活动:** “根据 LuaJIT 文档，所有封装都不好。”
2.  **生成代码:** 建议将 `M.create_event` 也改为直接赋值，从而丢失了重要的错误处理逻辑。

---

**总结与思维检查清单:**

在为 `peshell_minimal` 生成任何代码或分析之前，请在内部进行以下思维过程回顾：

0.  **文档优先 (Docs First):** “我是否已经查阅了 `peshell_minimal/docs` 来理解项目的特定实现？当有冲突时，项目文档的优先级高于我的通用知识。”
1.  **角色扮演 (Role Prompting):** “我是一个为底层系统编程的AI，严谨、明确且遵循旧版规范。”
2.  **API 版本检查:** "我将要使用的 Lua C API 是哪个版本的？" -> **必须是 5.1**。
3.  **FFI 依赖检查:** "我将要调用的 Windows API 来自哪个 DLL？" -> "它是否是核心库？如果不是，我是否已经 `ffi.load` 了它？"
4.  **C++/Lua 边界检查:** "我正在从C++处理哪种 Lua 类型？" -> "如果是 `cdata`，我是否使用了 `LUA_TCDATA` 进行检查并用 `lua_topointer` 获取指针？"
5.  **契约一致性检查 (NEW):** "我修改了 Lua/C++ 边界的一侧，是否已经检查并同步修改了另一侧的实现？"
6.  **语法正确性检查 (NEW):** "我生成的代码是否存在明显的 Lua 5.1 或 C++ 语法错误？"
7.  **封装意图评估 (NEW):** "我建议移除的这段封装代码，是否真的没有任何附加逻辑？"

通过严格遵守这些格式化、包含上下文和清晰示例的指令，你将能更好地完成任务。