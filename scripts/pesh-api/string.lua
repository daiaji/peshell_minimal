-- scripts/pesh-api/string.lua
-- 字符串处理 API 模块 (修正版 v2)

local M = {}
local log = require("pesh-api.log")

--- (LPOS/RPOS) 查找子串的位置
function M.find_pos(source, sub, start_index, is_plain)
    return string.find(source, sub, start_index, is_plain)
end

--- (LSTR/RSTR/MSTR) 截取子串
function M.sub(source, start, length)
    local len = length or -1
    return string.sub(source, start, start + len - 1)
end

--- (MSTR 分割) 按分隔符分割字符串
function M.split(source, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(source, delimiter, from)
    while delim_from do
        table.insert(result, string.sub(source, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(source, delimiter, from)
    end
    table.insert(result, string.sub(source, from))
    return result
end

--- (SED) 正则表达式替换
function M.replace_regex(source, pattern, replacement, count)
    return string.gsub(source, pattern, replacement, count)
end

-- ########## 关键修正 ##########

--- (STRL) 获取 UTF-8 字符串的字符长度
function M.length(source)
    -- Lua 5.1/LuaJIT 的 # 默认计算字节数。
    -- 我们需要一个能识别 UTF-8 多字节序列的函数来计算字符数。
    local len = 0
    local i = 1
    while i <= #source do
        local byte = string.byte(source, i)
        if byte < 128 then     -- 0xxxxxxx (ASCII)
            i = i + 1
        elseif byte < 224 then -- 110xxxxx 10xxxxxx (2-byte)
            i = i + 2
        elseif byte < 240 then -- 1110xxxx 10xxxxxx 10xxxxxx (3-byte)
            i = i + 3
        else                   -- 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx (4-byte)
            i = i + 4
        end
        len = len + 1
    end
    return len
end

--- (STRL -m) 获取字节长度
function M.byte_length(source)
    return string.len(source)
end

-- ############################

--- (CODE) 编码转换 (占位符)
function M.convert_encoding(source, from_encoding, to_encoding)
    log.warn("string.convert_encoding is a placeholder. A full implementation requires a C library like 'lua-iconv'.")
    -- 在实际项目中，这里会使用 FFI 调用 iconv 库
    return source
end

return M
