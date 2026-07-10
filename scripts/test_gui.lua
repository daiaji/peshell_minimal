package.path = "./scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;" .. package.path

local gui_mod = require("ui.gui")

local gui = gui_mod.create({ title = "Deploy" })
local image = gui:AddEdit("vImage", "C:\\image.wim")
local confirm = gui:AddCheckbox("vFormat", "Format target")
local progress = gui:AddProgress("vProgress", "Deploying")
local log = gui:AddLogView("vLog", "Log")
local readonly = gui:AddEdit("vReadonly ReadOnly Password WantTab Limit12 Number", "123")
local mode = gui:AddDropDownList("vMode AltSubmit", "Mode")

assert(gui:Get("Image") == image)
assert(image:GetValue() == "C:\\image.wim")
assert(confirm:GetValue() == false)
assert(progress:GetValue() == 0)
assert(log.type == "LogView")
assert(readonly.read_only == true)
assert(readonly.password == true)
assert(readonly.want_tab == true)
assert(readonly.limit == 12)
assert(readonly.number == true)
mode:SetItems({ "Apply", "Audit" })
mode:Choose(2)
assert(mode:GetValue() == 2)

local changed
confirm:OnEvent("Change", function(control, value)
    changed = control.name .. ":" .. tostring(value)
end)
confirm:SetValue(true)
assert(changed == "Format:true")

local shown = false
gui:OnEvent("Show", function() shown = true end)
gui:Show()
assert(shown == true)
assert(gui.visible == true)

progress:SetValue(42)
local values = gui:Submit()
assert(values.Image == "C:\\image.wim")
assert(values.Format == true)
assert(values.Progress == 42)

image:Move({ x = 10, y = 20, w = 300, h = 24 })
assert(image.x == 10)
assert(image.y == 20)
assert(image.w == 300)
assert(image.h == 24)
image:Focus()
assert(gui.focused == image)
assert(gui:FocusedCtrl() == image)
image:LoseFocus()
assert(gui.focused == nil)
image:Opt("Hidden Disabled")
assert(image.visible == false)
assert(image.enabled == false)
image:SetVisible(true):SetEnabled(true)
image:SetFont("s10", "Segoe UI")
assert(image.font.name == "Segoe UI")
local ix, iy, iw, ih = image:GetPos()
assert(ix == 10 and iy == 20 and iw == 300 and ih == 24)

local list = gui:AddListView("vTargets Grid Sort", "Targets")
list:SetColumns({ "Disk", "Size" })
assert(list.grid == true)
assert(list.sort == true)
assert(list:ColumnCount() == 2)
assert(list:AddRow({ "Disk 1", "64G" }) == 1)
assert(list:AddRow({ "Disk 0", "128G" }) == 2)
assert(list:InsertRow(2, { "Disk 2", "16G" }) == 2)
assert(list:GetRow(2)[1] == "Disk 2")
list:SetRow(2, { "Disk 3", "32G" })
assert(list:GetRow(2)[1] == "Disk 3")
assert(list:RowCount() == 3)
assert(list:GetCell(1, 1) == "Disk 1")
list:SetCell(1, 2, "32G")
assert(list:GetCell(1, 2) == "32G")
list:SetSelection(2)
assert(list:GetSelection() == 2)
list:SortRows(1)
assert(list:GetCell(1, 1) == "Disk 0")
list:DeleteColumn(2)
assert(list:ColumnCount() == 1)
list:DeleteRow(2)
assert(list:RowCount() == 2)

local tree = gui:AddTreeView("vTree WantF2")
assert(tree.want_f2 == true)
local root = tree:AddNode(nil, "Root", { path = "C:\\" })
local child = tree:AddNode(root, "Child", { path = "C:\\Windows" })
assert(tree:GetNode(root).children[1] == child)
assert(tree:GetParent(child) == root)
assert(tree:GetChildren(root)[1] == child)
assert(tree:SetNodeData(child, { path = "C:\\Win" }) == true)
assert(tree:GetNodeData(child).path == "C:\\Win")
assert(tree:Expand(root, true) == true)
assert(tree:GetNode(root).expanded == true)
assert(tree:Toggle(root) == true)
assert(tree:GetNode(root).expanded == false)
assert(tree:SetNodeText(child, "Windows") == true)
assert(tree:GetNode(child).text == "Windows")
tree:SetSelection(child)
assert(tree:GetSelection() == child)

local status = gui:AddStatusBar({ name = "Status", parts = { "Ready", "0%" } })
assert(status:GetPartText(1) == "Ready")
status:SetPartText(2, "42%")
assert(status:GetPartText(2) == "42%")
assert(status:PartCount() == 2)

local tab = gui:AddTab("vMainTab")
local page1 = tab:AddPage("Deploy")
local page2 = tab:AddPage("Log")
assert(page1 == 1)
assert(page2 == 2)
assert(tab:PageCount() == 2)
tab:UsePage(2)
assert(tab.current_page == 2)
assert(gui.current_tab == tab)
local tab_child = gui:AddText("vTabText", "Inside tab")
assert(tab.pages[2].controls[1] == tab_child)

progress:SetRange(0, 200)
progress:SetValue(50)
local rmin, rmax = progress:GetRange()
assert(rmin == 0 and rmax == 200)

local path_picker = gui:AddPathPicker({ name = "ImagePath", path = "C:\\boot.wim", filter = "%.wim$" })
assert(path_picker:GetValue() == "C:\\boot.wim")
path_picker:SetPath("D:\\install.wim")
assert(path_picker.path == "D:\\install.wim")
path_picker:SetFilter("%.esd$")
assert(path_picker.filter == "%.esd$")
local picker_model = path_picker:OpenPicker({
    cwd = "C:\\",
    fs = {
        list_dirs = function() return {} end,
        list_files = function() return { "C:\\install.esd" } end,
    },
})
assert(picker_model.open == true)
path_picker:ClosePicker()
assert(path_picker.picker == nil)

local log_view = gui:AddLogView("vTaskLog")
assert(log_view:AppendLog("started", "info") == 1)
assert(log_view.logs[1].text == "started")

local disk_list = gui:AddDiskList("vDiskList")
disk_list:SetDisks({ { index = 0, label = "System" }, { index = 1, label = "USB" } })
assert(disk_list:AddDisk({ index = 2, label = "VHD" }) == 3)
assert(disk_list:GetDisk(3).label == "VHD")
assert(disk_list:MarkDanger(1, "system disk") == true)
assert(disk_list.disks[1].danger == true)
disk_list:SetTarget(disk_list.disks[2])
assert(disk_list:GetTarget().label == "USB")

local confirmed
local confirm_dialog = gui:AddConfirmDialog("vConfirm", "Apply changes")
confirm_dialog:SetPlan({ { action = "format" }, { action = "apply_image" } }, { "destructive" })
confirm_dialog:OnEvent("Confirm", function() confirmed = true end)
assert(confirm_dialog:Confirm() == true)
assert(confirm_dialog.result == "confirm")
assert(confirmed == true)
assert(confirm_dialog:Cancel() == false)
assert(confirm_dialog.result == "cancel")
assert(gui:Submit().Confirm == nil)

local group = gui:AddGroupBox("vGroup", "Options")
local slider = gui:AddSlider("vScale Range0-200", "Scale")
local updown = gui:AddUpDown("vCopies Range1-9", "Copies")
local hotkey = gui:AddHotkey("vShortcut", "Ctrl+Alt+D")
local datetime = gui:AddDateTime("vWhen", "20260709")
local monthcal = gui:AddMonthCal("vCalendar", "202607")
local picture = gui:AddPic({ name = "Logo", path = "logo.png" })
picture:SetTexture("texture-id", 128, 64)
local link = gui:AddLink("vDocs", "Docs")
local custom_drawn = false
local custom = gui:AddCustom({ name = "Custom", draw = function() custom_drawn = true end }, "Custom")
assert(group.type == "GroupBox")
assert(slider.min == 0 and slider.max == 200)
assert(updown.min == 1 and updown.max == 9)
assert(hotkey:GetValue() == "Ctrl+Alt+D")
assert(datetime:GetValue() == "20260709")
assert(monthcal:GetValue() == "202607")
assert(picture.path == "logo.png")
assert(link.type == "Link")
assert(custom.type == "Custom")

local clicked = false
local button = gui:AddButton("vStart", "Start")
button:OnEvent("Click", function() clicked = true end)

local calls = {}
local ig = {
    igBegin = function(title)
        calls.title = title
        return true
    end,
    igText = function(_, text)
        calls.text = calls.text or {}
        calls.text[#calls.text + 1] = text
    end,
    igButton = function(label)
        calls.buttons = calls.buttons or {}
        calls.buttons[#calls.buttons + 1] = label
        return label == "Start"
    end,
    igProgressBar = function(value)
        calls.progress = value
    end,
    igEnd = function()
        calls.ended = true
    end,
}

assert(gui:Draw(ig) == true)
assert(calls.title == "Deploy")
assert(calls.progress == 0.25)
assert(clicked == true)
assert(calls.ended == true)

local rich_calls = {}
local rich_ig = {
    ImVec2 = function(x, y) return { x = x, y = y } end,
    igBegin = function() return true end,
    igEnd = function() rich_calls.end_window = true end,
    igText = function() end,
    igButton = function(label) return label == "Confirm" end,
    igInputText = function(label, buf)
        rich_calls.input = label
        return false
    end,
    igInputTextMultiline = function(label)
        rich_calls.input_multi = label
        return false
    end,
    igCheckbox = function(label, ref)
        rich_calls.checkbox = label
        ref[0] = false
        return true
    end,
    igRadioButton_Bool = function(label)
        rich_calls.radio = label
        return true
    end,
    igProgressBar = function(value) rich_calls.progress = value end,
    igImage = function(texture, size)
        rich_calls.image = texture
        rich_calls.image_w = size.x
    end,
    igSliderInt = function(label, ref)
        rich_calls.slider = label
        ref[0] = 77
        return true
    end,
    igBeginCombo = function(label, preview)
        rich_calls.combo = label .. ":" .. preview
        return true
    end,
    igEndCombo = function() rich_calls.end_combo = true end,
    igSelectable_Bool = function(label)
        rich_calls.selectable = rich_calls.selectable or {}
        rich_calls.selectable[#rich_calls.selectable + 1] = label
        return label == "Apply"
    end,
    igBeginTable = function(label, columns)
        rich_calls.tables = rich_calls.tables or {}
        rich_calls.tables[#rich_calls.tables + 1] = label .. ":" .. tostring(columns)
        return true
    end,
    igTableSetupColumn = function(column)
        rich_calls.columns = rich_calls.columns or {}
        rich_calls.columns[#rich_calls.columns + 1] = column
    end,
    igTableHeadersRow = function() rich_calls.headers = true end,
    igTableNextRow = function() rich_calls.rows = (rich_calls.rows or 0) + 1 end,
    igTableSetColumnIndex = function(index) rich_calls.last_column = index end,
    igEndTable = function() rich_calls.end_table = true end,
    igTreeNode_Str = function(label)
        rich_calls.tree = rich_calls.tree or {}
        rich_calls.tree[#rich_calls.tree + 1] = label
        return true
    end,
    igTreePop = function() rich_calls.tree_pop = (rich_calls.tree_pop or 0) + 1 end,
    igBeginTabBar = function(label)
        rich_calls.tab_bar = label
        return true
    end,
    igBeginTabItem = function(label)
        rich_calls.tab_item = label
        return true
    end,
    igEndTabItem = function() rich_calls.end_tab_item = true end,
    igEndTabBar = function() rich_calls.end_tab_bar = true end,
    igOpenPopup_Str = function(title) rich_calls.open_popup = title end,
    igBeginPopupModal = function(title) rich_calls.modal = title; return true end,
    igCloseCurrentPopup = function() rich_calls.close_popup = true end,
    igEndPopup = function() rich_calls.end_popup = true end,
    igSameLine = function() rich_calls.same_line = true end,
}

confirm:SetValue(true)
local radio = gui:AddRadio("vRadio", "Radio")
gui:Draw(rich_ig)
assert(confirm:GetValue() == false)
assert(rich_calls.checkbox == "Format target")
assert(rich_calls.combo:find("Mode", 1, true))
local saw_targets = false
for _, table_label in ipairs(rich_calls.tables or {}) do
    if table_label:find("Targets", 1, true) then saw_targets = true end
end
assert(saw_targets)
assert(rich_calls.end_table == true)
assert(rich_calls.tree[1] == "Root")
assert(rich_calls.end_tab_bar == true)
assert(confirm_dialog.result == "confirm")
assert(radio:GetValue() == true)
assert(slider:GetValue() == 77)
assert(rich_calls.image == "texture-id")
assert(rich_calls.modal == "Apply changes")
assert(rich_calls.end_popup == true)
assert(custom_drawn == true)

gui:Move({ x = 1, y = 2, w = 800, h = 600 })
local gx, gy, gw, gh = gui:GetPos()
assert(gx == 1 and gy == 2 and gw == 800 and gh == 600)
local cx, cy, cw, ch = gui:GetClientPos()
assert(cx == 0 and cy == 0 and cw == 800 and ch == 600)
gui:SetFont("s12", "Segoe UI")
assert(gui.font.name == "Segoe UI")
gui:Opt("Disabled")
assert(gui.options.enabled == false)
gui:Minimize(); assert(gui.window_state == "minimized")
gui:Maximize(); assert(gui.window_state == "maximized")
gui:Restore(); assert(gui.window_state == "normal")
gui:Flash(); assert(gui.flash == true)

local closed = false
gui:OnEvent("Close", function() closed = true end)
gui:Close()
assert(gui.visible == false)
assert(gui.closed == true)
assert(closed == true)

gui:Destroy()
assert(#gui.controls == 0)
assert(gui:Get("Image") == nil)

return true
