-- .luacheckrc
-- Modern configuration for luacheck, returning a table.

return {
    -- ===================================
    -- 规则定义 (Rules)
    -- ===================================

    -- 设置标准库环境为 LuaJIT，以便识别 `bit`, `ffi` 等特有库
    std = "luajit",

    -- 定义额外的全局变量，避免 luacheck 误报为未定义
    -- `pesh_native` 是 C++ 暴露的原生接口
    -- `lfs` 是 LuaFileSystem 库
    globals = {
        "pesh_native",
        "lfs"
    },

    -- 忽略指定的警告代码
    ignore = {
        "212", -- 'unused argument' (忽略未使用的函数参数警告)
        "021"  -- 'line contains only whitespace' (忽略仅包含空白字符的行的警告)
    },

    -- ===================================
    -- 目标文件 (Targets)
    -- ===================================

    -- 当命令行没有指定文件或目录时，默认检查 `scripts/` 目录
    -- 这解决了在项目根目录直接运行 `luacheck` 时报错的问题
    files = {
        "scripts/"
    }
}