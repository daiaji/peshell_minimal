-- scripts/test_unicode_fs.lua
-- 专项测试：验证文件系统 API 对 Unicode (中文/Emoji) 的支持能力

local lu = require("luaunit")
local log = _G.log
local pesh = _G.pesh
local fs = pesh.plugin.load("fs")
local path = require("pl.path")

-- 强制控制台输出为 UTF-8，防止日志打印乱码误导判断
os.execute("chcp 65001 > nul")

-- 构造高难度的测试路径：
-- 1. 包含空格
-- 2. 包含中文
-- 3. 包含 Emoji (🚀)，这对很多老旧 API 是毁灭性的打击
local temp_root = os.getenv("TEMP") or "."
local unicode_dir_name = "_peshell_unicode_test_中文目录 🚀"
local unicode_file_name = "测试文档_📄.txt"

local src_dir = path.join(temp_root, unicode_dir_name)
local src_file = path.join(src_dir, unicode_file_name)
local dst_dir = path.join(temp_root, unicode_dir_name .. "_副本")

TestUnicodeFS = {}

function TestUnicodeFS:setUp()
    -- 确保环境干净
    if fs.exists(src_dir) then fs.delete(src_dir) end
    if fs.exists(dst_dir) then fs.delete(dst_dir) end
end

function TestUnicodeFS:tearDown()
    -- 测试后清理（注释掉这一行可以保留文件以便手动检查）
    fs.delete(src_dir)
    fs.delete(dst_dir)
end

function TestUnicodeFS:testFullCycle()
    log.info("===========================================================")
    log.info("  UNICODE FILE SYSTEM TEST")
    log.info("  Source Dir:  ", src_dir)
    log.info("  Source File: ", src_file)
    log.info("===========================================================")

    -- 1. 测试目录创建 (fs.mkdir)
    log.info("[1/5] Creating Unicode directory...")
    local ok, err = fs.mkdir(src_dir)
    lu.assertTrue(ok, "fs.mkdir failed: " .. tostring(err))
    lu.assertTrue(fs.is_dir(src_dir), "fs.is_dir returned false for created dir")
    log.info("  -> OK.")

    -- 2. 测试文件写入 (fs.write_file)
    log.info("[2/5] Writing Unicode file content...")
    local content = "Hello World! \n你好世界! \nEmoji Check: 🌍✨"
    ok, err = fs.write_file(src_file, content)
    lu.assertTrue(ok, "fs.write_file failed: " .. tostring(err))
    lu.assertTrue(fs.exists(src_file), "File check failed after write")
    
    -- 验证文件大小不为0
    local size = fs.get_size(src_file)
    lu.assertTrue(size > 0, "File size should be > 0")
    log.info("  -> OK. File size: ", size)

    -- 3. 测试文件读取 (fs.read_file)
    log.info("[3/5] Reading back file content...")
    local read_content, err_read = fs.read_file(src_file)
    lu.assertNotIsNil(read_content, "fs.read_file returned nil: " .. tostring(err_read))
    lu.assertEquals(read_content, content, "Content mismatch! Encoding issue?")
    log.info("  -> OK.")

    -- 4. 测试递归复制 (fs.copy)
    -- 这是最容易挂掉的地方：如果底层用了不支持 Unicode 的目录遍历器，这里会找不到文件。
    log.info("[4/5] Recursive Copy (Dir -> Dir)...")
    ok, err = fs.copy(src_dir, dst_dir)
    lu.assertTrue(ok, "fs.copy recursive failed: " .. tostring(err))

    local copied_file = path.join(dst_dir, unicode_file_name)
    lu.assertTrue(fs.exists(copied_file), "Copied file missing in destination")
    
    local read_copy = fs.read_file(copied_file)
    lu.assertEquals(read_copy, content, "Copied file content mismatch")
    log.info("  -> OK.")

    -- 5. 测试删除 (fs.delete)
    log.info("[5/5] Deleting Unicode directories...")
    ok, err = fs.delete(dst_dir)
    lu.assertTrue(ok, "fs.delete (copy) failed: " .. tostring(err))
    lu.assertFalse(fs.exists(dst_dir), "Copy dir still exists")
    log.info("  -> OK.")
end

os.exit(lu.LuaUnit.run())