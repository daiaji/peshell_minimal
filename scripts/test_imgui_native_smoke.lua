local plugin = _G.pesh.plugin.load("imgui")

local status = plugin.probe()
assert(status and status.available == true, status and status.error or "imgui probe failed")

local result, err = plugin.native_smoke({ frames = 3, cwd = "." })
assert(result, err)
assert((result.frames or 0) > 0, "native smoke rendered no frames")

return true
