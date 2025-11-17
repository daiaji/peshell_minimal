-- peshell-minimal-dev-1.rockspec
--
-- 这是一个元数据文件，主要用于定义项目的依赖关系。
-- CI 流程会读取 'dependencies' 部分来安装第三方库。
-- 'build' 部分在 CI 中被忽略，因为我们采用手动组装的方式。

package = "peshell-minimal"
version = "dev-1"

-- source URL 保持不变，因为它可能被其他工具使用
source = {
    url = "git://."
}

description = {
    summary = "一个使用 LuaJIT 和 FFI 的模块化 WinPE 自动化引擎。",
    detailed = [[
        PEShell 是一个为 Windows PE 设计的轻量级、可编写脚本的环境。
        它利用 LuaJIT 实现高性能脚本执行，并通过 FFI 深度集成 Win32 API。
        该项目旨在成为 PECMD 等传统 PE 脚本工具的现代化替代品。
    ]],
    homepage = "https://github.com/daiaji/peshell_minimal",
    license = "MIT"
}

-- 这是 CI 流程唯一关心的部分
dependencies = {
    "lua >= 5.1, < 5.2",
    "penlight",
    "luafilesystem",
    "luaunit"
}

-- [[ 核心修正 ]]
-- 将 build 类型改为 "builtin"，并清空 build 表。
-- 这明确表示此 rockspec 文件本身不执行任何编译或安装操作。
-- 所有构建逻辑都由外部脚本（如 ci.yml）通过调用 cmake 来处理。
build = {
    type = "builtin"
}