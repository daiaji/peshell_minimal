local M = {}
local bit = require("bit")

local function vec2(ig, x, y)
    return { x = x, y = y }
end

local function has(ig, name)
    if not ig then return false end
    local ok, value = pcall(function() return ig[name] end)
    return ok and type(value) == "function"
end

local function bool_ref(value)
    local ok, ffi = pcall(require, "ffi")
    if not ok then return nil end
    return ffi.new("bool[1]", value == true)
end

local function text_buffer(control)
    local ok, ffi = pcall(require, "ffi")
    if not ok then return nil end
    local size = math.max((control.limit or 1024) + 1, #(control.value or control.text or "") + 16)
    if not control._text_buffer or control._text_buffer_size ~= size then
        control._text_buffer = ffi.new("char[?]", size)
        control._text_buffer_size = size
    end
    ffi.fill(control._text_buffer, size)
    ffi.copy(control._text_buffer, tostring(control.value or control.text or ""), size - 1)
    return control._text_buffer, size, ffi
end

local INPUT_FLAGS = {
    chars_decimal = 1,
    readonly = bit.lshift(1, 14),
    password = bit.lshift(1, 15),
    enter_returns_true = bit.lshift(1, 6),
}

local function input_flags(control)
    local flags = 0
    if control.read_only then flags = bit.bor(flags, INPUT_FLAGS.readonly) end
    if control.password then flags = bit.bor(flags, INPUT_FLAGS.password) end
    if control.number then flags = bit.bor(flags, INPUT_FLAGS.chars_decimal) end
    if control.enter_returns_true then flags = bit.bor(flags, INPUT_FLAGS.enter_returns_true) end
    return flags
end

local function draw_input_text(ig, label, control)
    local fn = control.multi and "igInputTextMultiline" or "igInputText"
    if not has(ig, fn) then return false end
    local buf, size, ffi = text_buffer(control)
    if not buf then return false end
    local flags = input_flags(control)
    local ok, changed
    if control.multi then
        ok, changed = pcall(ig[fn], label, buf, size, vec2(ig, control.w or 0, control.h or 0), flags, nil, nil)
    else
        ok, changed = pcall(ig[fn], label, buf, size, flags, nil, nil)
    end
    if not ok then return false end
    if changed then control:SetValue(ffi.string(buf)) end
    return true
end

local function number_ref(value, ctype)
    local ok, ffi = pcall(require, "ffi")
    if not ok then return nil end
    return ffi.new((ctype or "int") .. "[1]", value or 0), ffi
end

local function draw_checkbox(ig, label, value)
    if has(ig, "igCheckbox") then
        local ref = bool_ref(value)
        if ref then
            local changed = ig.igCheckbox(label, ref)
            return ref[0] == true, changed
        end
    end
    if ig.igButton((value and "[x] " or "[ ] ") .. label, vec2(ig, 0, 0)) then
        return not value, true
    end
    return value, false
end

local function draw_radio(ig, label, value)
    if has(ig, "igRadioButton_Bool") then
        if ig.igRadioButton_Bool(label, value == true) then return true, true end
    elseif has(ig, "igRadioButton") then
        if ig.igRadioButton(label, value == true) then return true, true end
    elseif ig.igButton((value and "(*) " or "( ) ") .. label, vec2(ig, 0, 0)) then
        return true, true
    end
    return value, false
end

local function draw_selectable(ig, label, selected)
    if has(ig, "igSelectable_Bool") then return ig.igSelectable_Bool(label, selected == true) end
    if has(ig, "igSelectable") then return ig.igSelectable(label, selected == true) end
    return ig.igButton(label, vec2(ig, 0, 0))
end

local function copy_array(values)
    local out = {}
    for i, value in ipairs(values or {}) do out[i] = value end
    return out
end

local function parse_options(opts)
    if type(opts) == "table" then return opts end
    local parsed = {}
    if type(opts) ~= "string" then return parsed end
    for token in opts:gmatch("%S+") do
        local name = token:match("^[vV](.+)")
        if name then
            parsed.name = name
        elseif token:lower() == "disabled" then
            parsed.enabled = false
        elseif token:lower() == "hidden" then
            parsed.visible = false
        elseif token:lower() == "checked" then
            parsed.value = true
        elseif token:lower() == "readonly" then
            parsed.read_only = true
        elseif token:lower() == "altsubmit" then
            parsed.alt_submit = true
        elseif token:lower() == "multi" then
            parsed.multi = true
        elseif token:lower() == "password" then
            parsed.password = true
        elseif token:lower() == "wanttab" then
            parsed.want_tab = true
        elseif token:lower() == "wantf2" then
            parsed.want_f2 = true
        elseif token:lower() == "grid" then
            parsed.grid = true
        elseif token:lower() == "sort" then
            parsed.sort = true
        elseif token:lower() == "number" then
            parsed.number = true
        elseif token:lower() == "default" then
            parsed.default = true
        elseif token:lower() == "vertical" then
            parsed.vertical = true
        elseif token:lower() == "inverted" or token:lower() == "invert" then
            parsed.inverted = true
        elseif token:match("^[gG]roup.+") then
            parsed.group = token:sub(6)
        elseif token:match("^[rR]ange%-?%d+%-%-?%d+") then
            local min_value, max_value = token:match("^[rR]ange(%-?%d+)%-(%-?%d+)")
            parsed.min = tonumber(min_value)
            parsed.max = tonumber(max_value)
        elseif token:match("^[cC]hoose%d+") then
            parsed.choice = tonumber(token:sub(7))
        elseif token:match("^[lL]imit%d+") then
            parsed.limit = tonumber(token:sub(6))
        elseif token:match("^[wW]%d+") then
            parsed.w = tonumber(token:sub(2))
        elseif token:match("^[hH]%d+") then
            parsed.h = tonumber(token:sub(2))
        elseif token:match("^[xX]%-?%d+") then
            parsed.x = tonumber(token:sub(2))
        elseif token:match("^[yY]%-?%d+") then
            parsed.y = tonumber(token:sub(2))
        end
    end
    return parsed
end

local function fire(target, event, ...)
    local handlers = target.events and target.events[event]
    if not handlers then return true end
    for _, handler in ipairs(handlers) do
        local ok, err = pcall(handler, target, ...)
        if not ok then return nil, err end
    end
    return true
end

local NON_SUBMIT_TYPES = {
    Text = true,
    Button = true,
    GroupBox = true,
    StatusBar = true,
    Picture = true,
    Link = true,
    Custom = true,
    LogView = true,
    ConfirmDialog = true,
}

local function is_submittable(control)
    return not NON_SUBMIT_TYPES[control.type]
end

local Control = {}
Control.__index = Control

function Control:OnEvent(event, callback)
    assert(type(event) == "string", "event must be a string")
    assert(type(callback) == "function", "callback must be a function")
    self.events[event] = self.events[event] or {}
    table.insert(self.events[event], callback)
    return self
end

function Control:Trigger(event, ...)
    return fire(self, event, ...)
end

function Control:Click(info) return fire(self, "Click", info) end
function Control:DoubleClick(info) return fire(self, "DoubleClick", info) end
function Control:RightClick(info) return fire(self, "RightClick", info) end
function Control:ItemActivate(info) return fire(self, "ItemActivate", info) end
function Control:ColClick(column) return fire(self, "ColClick", { column = column }) end

function Control:SetValue(value)
    if self.type == "Radio" and value == true then
        for _, control in ipairs(self.gui.controls or {}) do
            if control ~= self and control.type == "Radio" and control.radio_group == self.radio_group then
                control.value = false
            end
        end
    end
    self.value = value
    fire(self, "Change", value)
    return self
end

function Control:GetValue()
    return self.value
end

function Control:SetItems(items)
    self.items = copy_array(items)
    return self
end

function Control:AddItem(item)
    self.items = self.items or {}
    table.insert(self.items, item)
    return #self.items
end

function Control:Choose(choice)
    if type(choice) == "number" then
        self.selection = choice
        self.value = self.alt_submit and choice or self.items[choice]
    else
        for i, item in ipairs(self.items or {}) do
            if item == choice then
                self.selection = i
                self.value = self.alt_submit and i or item
                break
            end
        end
    end
    fire(self, "Change", self.value)
    return self
end

function Control:GetText()
    return self.text
end

function Control:SetText(text)
    self.text = text or ""
    return self
end

function Control:SetEnabled(enabled)
    self.enabled = enabled ~= false
    return self
end

function Control:SetVisible(visible)
    self.visible = visible ~= false
    return self
end

function Control:Move(opts)
    opts = opts or {}
    if opts.x ~= nil then self.x = opts.x end
    if opts.y ~= nil then self.y = opts.y end
    if opts.w ~= nil then self.w = opts.w end
    if opts.h ~= nil then self.h = opts.h end
    fire(self, "Move", opts)
    return self
end

function Control:GetPos()
    return self.x, self.y, self.w, self.h
end

function Control:Opt(opts)
    local parsed = parse_options(opts or {})
    for key, value in pairs(parsed) do self[key] = value end
    return self
end

function Control:SetFont(opts, name)
    self.font = { options = opts, name = name }
    return self
end

function Control:Focus()
    self.gui.focused = self
    fire(self, "Focus")
    return self
end

function Control:LoseFocus()
    if self.gui.focused == self then self.gui.focused = nil end
    fire(self, "LoseFocus")
    return self
end

function Control:AddRow(row)
    self.rows = self.rows or {}
    table.insert(self.rows, row)
    return #self.rows
end

function Control:InsertRow(index, row)
    self.rows = self.rows or {}
    table.insert(self.rows, index, row)
    return index
end

function Control:GetRow(index)
    return self.rows and self.rows[index]
end

function Control:SetRow(index, row)
    self.rows[index] = row
    fire(self, "Change", { row = index, value = row })
    return self
end

function Control:DeleteRow(index)
    table.remove(self.rows, index)
    if self.selection == index then self.selection = nil end
    return self
end

function Control:Clear()
    self.rows = {}
    self.items = {}
    self.logs = {}
    self.disks = {}
    self.plan_steps = {}
    self.risks = {}
    self.tree_nodes = {}
    self.root_nodes = {}
    self.selection = nil
    return self
end

function Control:SetColumns(columns)
    self.columns = copy_array(columns)
    return self
end

function Control:AddColumn(name)
    self.columns = self.columns or {}
    table.insert(self.columns, name)
    return #self.columns
end

function Control:DeleteColumn(index)
    table.remove(self.columns, index)
    for _, row in ipairs(self.rows or {}) do
        if type(row) == "table" then table.remove(row, index) end
    end
    return self
end

function Control:RowCount()
    return #(self.rows or {})
end

function Control:ColumnCount()
    return #(self.columns or {})
end

function Control:GetCell(row, column)
    local item = self.rows and self.rows[row]
    if type(item) ~= "table" then return nil end
    return item[column]
end

function Control:SetCell(row, column, value)
    self.rows[row] = self.rows[row] or {}
    self.rows[row][column] = value
    fire(self, "Change", { row = row, column = column, value = value })
    return self
end

function Control:SetSelection(selection)
    self.selection = selection
    fire(self, "Change", selection)
    return self
end

function Control:GetSelection()
    return self.selection
end

function Control:SortRows(column, descending)
    table.sort(self.rows, function(a, b)
        local av = type(a) == "table" and a[column] or a
        local bv = type(b) == "table" and b[column] or b
        if descending then return tostring(av) > tostring(bv) end
        return tostring(av) < tostring(bv)
    end)
    return self
end

function Control:AddNode(parent, text, data)
    self.tree_nodes = self.tree_nodes or {}
    self.root_nodes = self.root_nodes or {}
    local id = #self.tree_nodes + 1
    local node = { id = id, parent = parent, text = text or "", data = data, children = {}, expanded = false }
    self.tree_nodes[id] = node
    if parent then
        local parent_node = self.tree_nodes[parent]
        assert(parent_node, "parent node not found")
        table.insert(parent_node.children, id)
    else
        table.insert(self.root_nodes, id)
    end
    return id
end

function Control:DeleteNode(id)
    local node = self.tree_nodes and self.tree_nodes[id]
    if not node then return false end
    local list = node.parent and self.tree_nodes[node.parent].children or self.root_nodes
    for i, child_id in ipairs(list) do
        if child_id == id then table.remove(list, i); break end
    end
    local function remove_tree(node_id)
        local item = self.tree_nodes[node_id]
        if not item then return end
        for _, child_id in ipairs(item.children) do remove_tree(child_id) end
        self.tree_nodes[node_id] = nil
    end
    remove_tree(id)
    if self.selection == id then self.selection = nil end
    return true
end

function Control:Expand(id, expanded)
    local node = self.tree_nodes and self.tree_nodes[id]
    if not node then return false end
    node.expanded = expanded ~= false
    fire(self, node.expanded and "Expand" or "Collapse", id)
    return true
end

function Control:Toggle(id)
    local node = self.tree_nodes and self.tree_nodes[id]
    if not node then return false end
    return self:Expand(id, not node.expanded)
end

function Control:GetNode(id)
    return self.tree_nodes and self.tree_nodes[id]
end

function Control:GetParent(id)
    local node = self:GetNode(id)
    return node and node.parent or nil
end

function Control:GetChildren(id)
    local node = self:GetNode(id)
    return node and copy_array(node.children) or {}
end

function Control:SetNodeData(id, data)
    local node = self:GetNode(id)
    if not node then return false end
    node.data = data
    return true
end

function Control:GetNodeData(id)
    local node = self:GetNode(id)
    return node and node.data or nil
end

function Control:SetNodeText(id, text)
    local node = self:GetNode(id)
    if not node then return false end
    node.text = text or ""
    fire(self, "Change", { node = id, text = node.text })
    return true
end

function Control:SetParts(parts)
    self.parts = copy_array(parts)
    return self
end

function Control:SetPartText(part, text)
    self.parts = self.parts or {}
    self.parts[part] = text or ""
    return self
end

function Control:GetPartText(part)
    return self.parts and self.parts[part]
end

function Control:PartCount()
    return #(self.parts or {})
end

function Control:AddPage(name)
    self.pages = self.pages or {}
    table.insert(self.pages, { name = name, controls = {} })
    if not self.current_page then self.current_page = 1 end
    return #self.pages
end

function Control:DeletePage(page)
    table.remove(self.pages, page)
    if self.current_page and self.current_page > #self.pages then self.current_page = #self.pages end
    return self
end

function Control:PageCount()
    return #(self.pages or {})
end

function Control:UsePage(page)
    assert(self.pages and self.pages[page], "tab page not found")
    self.current_page = page
    self.gui.current_tab = self
    self.gui.current_tab_page = page
    fire(self, "Change", page)
    return self
end

function Control:SetRange(min_value, max_value)
    self.min = min_value or 0
    self.max = max_value or 100
    return self
end

function Control:GetRange()
    return self.min, self.max
end

function Control:GetSubmitValue()
    return self:GetValue()
end

function Control:SetPath(path)
    self.path = path
    self.value = path
    fire(self, "Change", path)
    return self
end

function Control:OpenPicker(opts)
    opts = opts or {}
    local picker = require("ui.widgets.file_picker")
    self.picker = picker.create({
        cwd = opts.cwd or self.cwd or ".",
        mode = opts.mode or self.mode or "open",
        filter = opts.filter or self.filter,
        selected = self.value,
        fs = opts.fs or self.fs,
    })
    return self.picker
end

function Control:ClosePicker()
    self.picker = nil
    return self
end

function Control:SetTexture(texture, width, height)
    self.texture = texture
    self.texture_w = width
    self.texture_h = height
    return self
end

function Control:SetFilter(filter)
    self.filter = filter
    return self
end

function Control:AppendLog(line, level)
    self.logs = self.logs or {}
    table.insert(self.logs, { text = line or "", level = level or "info" })
    self.value = line or ""
    fire(self, "Change", self.logs[#self.logs])
    return #self.logs
end

function Control:SetDisks(disks)
    self.disks = copy_array(disks)
    return self
end

function Control:AddDisk(disk)
    self.disks = self.disks or {}
    table.insert(self.disks, disk)
    return #self.disks
end

function Control:GetDisk(index)
    return self.disks and self.disks[index]
end

function Control:MarkDanger(index, reason)
    local disk = self.disks and self.disks[index]
    if not disk then return false end
    disk.danger = true
    disk.danger_reason = reason
    return true
end

function Control:SetTarget(target)
    self.target = target
    self.value = target
    fire(self, "Change", target)
    return self
end

function Control:GetTarget()
    return self.target
end

function Control:SetPlan(steps, risks)
    self.plan_steps = copy_array(steps)
    self.risks = copy_array(risks)
    return self
end

function Control:Confirm()
    self.result = "confirm"
    self.value = true
    fire(self, "Confirm")
    return true
end

function Control:Cancel()
    self.result = "cancel"
    self.value = false
    fire(self, "Cancel")
    return false
end

local Gui = {}
Gui.__index = Gui

function Gui:OnEvent(event, callback)
    assert(type(event) == "string", "event must be a string")
    assert(type(callback) == "function", "callback must be a function")
    self.events[event] = self.events[event] or {}
    table.insert(self.events[event], callback)
    return self
end

function Gui:Trigger(event, ...)
    return fire(self, event, ...)
end

function Gui:Add(kind, opts, text)
    local options = parse_options(opts)
    local control = setmetatable({
        gui = self,
        type = kind,
        name = options.name,
        text = text or options.text or "",
        value = options.value,
        enabled = options.enabled ~= false,
        visible = options.visible ~= false,
        read_only = options.read_only == true,
        alt_submit = options.alt_submit == true,
        multi = options.multi == true,
        password = options.password == true,
        want_tab = options.want_tab == true,
        want_f2 = options.want_f2 == true,
        grid = options.grid == true,
        sort = options.sort == true,
        number = options.number == true,
        default = options.default == true,
        vertical = options.vertical == true,
        inverted = options.inverted == true,
        limit = options.limit,
        selection = options.choice,
        radio_group = options.group or "default",
        x = options.x,
        y = options.y,
        w = options.w,
        h = options.h,
        items = copy_array(options.items),
        columns = copy_array(options.columns),
        rows = copy_array(options.rows),
        logs = copy_array(options.logs),
        disks = copy_array(options.disks),
        filter = options.filter,
        cwd = options.cwd,
        mode = options.mode,
        fs = options.fs,
        path = options.path,
        texture = options.texture,
        texture_w = options.texture_w,
        texture_h = options.texture_h,
        target = options.target,
        plan_steps = copy_array(options.plan_steps),
        risks = copy_array(options.risks),
        open = options.open ~= false,
        draw = options.draw,
        tree_nodes = {},
        root_nodes = {},
        pages = {},
        parts = copy_array(options.parts),
        min = options.min or 0,
        max = options.max or 100,
        events = {},
    }, Control)
    if control.value == nil then
        if kind == "Checkbox" or kind == "Radio" then control.value = false end
        if kind == "Progress" then control.value = 0 end
        if kind == "Slider" or kind == "UpDown" then control.value = control.min end
        if kind == "Edit" then control.value = control.text end
        if kind == "Hotkey" then control.value = control.text end
        if kind == "DateTime" or kind == "MonthCal" then control.value = control.text ~= "" and control.text or os.date("%Y%m%d") end
        if kind == "PathPicker" then control.value = control.path or control.text end
        if kind == "ConfirmDialog" then control.value = false end
    end
    table.insert(self.controls, control)
    if control.name then self.named[control.name] = control end
    if self.current_tab and kind ~= "Tab" then
        local page = self.current_tab.pages[self.current_tab_page]
        if page then table.insert(page.controls, control) end
    end
    return control
end

function Gui:AddText(opts, text) return self:Add("Text", opts, text) end
function Gui:AddButton(opts, text) return self:Add("Button", opts, text) end
function Gui:AddEdit(opts, text) return self:Add("Edit", opts, text) end
function Gui:AddCheckbox(opts, text) return self:Add("Checkbox", opts, text) end
function Gui:AddCheckBox(opts, text) return self:Add("Checkbox", opts, text) end
function Gui:AddRadio(opts, text) return self:Add("Radio", opts, text) end
function Gui:AddDDL(opts, text) return self:Add("DropDownList", opts, text) end
function Gui:AddDropDownList(opts, text) return self:Add("DropDownList", opts, text) end
function Gui:AddComboBox(opts, text) return self:Add("ComboBox", opts, text) end
function Gui:AddListBox(opts, text) return self:Add("ListBox", opts, text) end
function Gui:AddListView(opts, text) return self:Add("ListView", opts, text) end
function Gui:AddTreeView(opts, text) return self:Add("TreeView", opts, text) end
function Gui:AddGroupBox(opts, text) return self:Add("GroupBox", opts, text) end
function Gui:AddTab(opts, text) return self:Add("Tab", opts, text) end
function Gui:AddTab2(opts, text) return self:Add("Tab", opts, text) end
function Gui:AddTab3(opts, text) return self:Add("Tab", opts, text) end
function Gui:AddSlider(opts, text) return self:Add("Slider", opts, text) end
function Gui:AddUpDown(opts, text) return self:Add("UpDown", opts, text) end
function Gui:AddProgress(opts, text) return self:Add("Progress", opts, text) end
function Gui:AddStatusBar(opts, text) return self:Add("StatusBar", opts, text) end
function Gui:AddPic(opts, text) return self:Add("Picture", opts, text) end
function Gui:AddPicture(opts, text) return self:Add("Picture", opts, text) end
function Gui:AddLink(opts, text) return self:Add("Link", opts, text) end
function Gui:AddHotkey(opts, text) return self:Add("Hotkey", opts, text) end
function Gui:AddDateTime(opts, text) return self:Add("DateTime", opts, text) end
function Gui:AddMonthCal(opts, text) return self:Add("MonthCal", opts, text) end
function Gui:AddCustom(opts, text) return self:Add("Custom", opts, text) end
function Gui:AddLogView(opts, text) return self:Add("LogView", opts, text) end
function Gui:AddPathPicker(opts, text) return self:Add("PathPicker", opts, text) end
function Gui:AddDiskList(opts, text) return self:Add("DiskList", opts, text) end
function Gui:AddConfirmDialog(opts, text) return self:Add("ConfirmDialog", opts, text) end

function Gui:Get(name)
    return self.named[name]
end

function Gui:Show(opts)
    opts = parse_options(opts or {})
    self.visible = true
    self.title = opts.title or self.title
    if opts.x ~= nil then self.x = opts.x end
    if opts.y ~= nil then self.y = opts.y end
    if opts.w ~= nil then self.w = opts.w end
    if opts.h ~= nil then self.h = opts.h end
    fire(self, "Show")
    return self
end

function Gui:Move(opts)
    opts = opts or {}
    if opts.x ~= nil then self.x = opts.x end
    if opts.y ~= nil then self.y = opts.y end
    if opts.w ~= nil then self.w = opts.w end
    if opts.h ~= nil then self.h = opts.h end
    fire(self, "Size", { x = self.x, y = self.y, w = self.w, h = self.h })
    return self
end

function Gui:GetPos()
    return self.x, self.y, self.w, self.h
end

function Gui:GetClientPos()
    return 0, 0, self.w, self.h
end

function Gui:SetFont(opts, name)
    self.font = { options = opts, name = name }
    return self
end

function Gui:Opt(opts)
    local parsed = parse_options(opts or {})
    for key, value in pairs(parsed) do self.options[key] = value end
    return self
end

function Gui:Hide()
    self.visible = false
    return self
end

function Gui:Close()
    self.closed = true
    self.visible = false
    fire(self, "Close")
    return self
end

function Gui:Escape()
    fire(self, "Escape")
    return self:Close()
end

function Gui:Minimize()
    self.window_state = "minimized"
    return self
end

function Gui:Maximize()
    self.window_state = "maximized"
    return self
end

function Gui:Restore()
    self.window_state = "normal"
    return self
end

function Gui:Flash(blink)
    self.flash = blink ~= false
    return self
end

function Gui:FocusedCtrl()
    return self.focused
end

function Gui:Destroy()
    self:Close()
    self.controls = {}
    self.named = {}
    self.current_tab = nil
    self.current_tab_page = nil
    return self
end

function Gui:Submit()
    local values = {}
    for name, control in pairs(self.named) do
        if is_submittable(control) then values[name] = control:GetSubmitValue() end
    end
    self.values = values
    fire(self, "Submit", values)
    return values
end

local function draw_text_control(control, ig)
    if control.type == "Text" then
        ig.igText("%s", control.text)
    elseif control.type == "Button" then
        if ig.igButton(control.text, vec2(ig, control.w or 0, control.h or 0)) then
            fire(control, "Click")
        end
    elseif control.type == "Edit" then
        if not draw_input_text(ig, control.name or control.text or "Edit", control) then ig.igText("%s", control.value or control.text or "") end
    elseif control.type == "Checkbox" then
        local label = control.text or ""
        local value, changed = draw_checkbox(ig, label, control.value)
        if changed then control:SetValue(value) end
    elseif control.type == "Radio" then
        local label = control.text or ""
        local value, changed = draw_radio(ig, label, control.value)
        if changed then control:SetValue(value) end
    elseif control.type == "Progress" then
        if has(ig, "igProgressBar") then
            local span = control.max - control.min
            local ratio = span ~= 0 and ((tonumber(control.value) or 0) - control.min) / span or 0
            ig.igProgressBar(ratio, vec2(ig, control.w or -1, control.h or 0), control.text or "")
        else
            ig.igText("%s", string.format("%s %d%%", control.text or "Progress", tonumber(control.value) or 0))
        end
    elseif control.type == "Slider" then
        local value_ref = number_ref(tonumber(control.value) or 0)
        if value_ref and has(ig, control.vertical and "igVSliderInt" or "igSliderInt") then
            local changed
            if control.vertical then
                changed = ig.igVSliderInt(control.text ~= "" and control.text or control.name or "Slider", vec2(ig, control.w or 24, control.h or 120), value_ref, control.min, control.max, "%d", 0)
            else
                changed = ig.igSliderInt(control.text ~= "" and control.text or control.name or "Slider", value_ref, control.min, control.max, "%d", 0)
            end
            if changed then control:SetValue(tonumber(value_ref[0])) end
        else
            ig.igText("%s", string.format("%s %s", control.text ~= "" and control.text or "Slider", tostring(control.value)))
        end
    elseif control.type == "UpDown" then
        local label = control.text ~= "" and control.text or control.name or "UpDown"
        if ig.igButton("-##" .. label, vec2(ig, 0, 0)) then control:SetValue(math.max(control.min, (tonumber(control.value) or 0) - 1)) end
        if has(ig, "igSameLine") then ig.igSameLine(0, -1) end
        ig.igText("%s", tostring(control.value))
        if has(ig, "igSameLine") then ig.igSameLine(0, -1) end
        if ig.igButton("+##" .. label, vec2(ig, 0, 0)) then control:SetValue(math.min(control.max, (tonumber(control.value) or 0) + 1)) end
    elseif control.type == "GroupBox" then
        if has(ig, "igSeparatorText") then ig.igSeparatorText(control.text) else ig.igText("%s", control.text) end
    elseif control.type == "Hotkey" then
        if not draw_input_text(ig, control.name or control.text or "Hotkey", control) then ig.igText("%s", control.value or "") end
    elseif control.type == "DateTime" or control.type == "MonthCal" then
        if not draw_input_text(ig, control.name or control.text or control.type, control) then ig.igText("%s", control.value or "") end
    elseif control.type == "DropDownList" or control.type == "ComboBox" or control.type == "ListBox" then
        local label = control.text ~= "" and control.text or control.type
        if (control.type == "DropDownList" or control.type == "ComboBox") and has(ig, "igBeginCombo") then
            local preview = tostring(control.items[control.selection or 0] or control.value or "")
            if ig.igBeginCombo(label, preview, 0) then
                for i, item in ipairs(control.items or {}) do
                    if draw_selectable(ig, tostring(item), control.selection == i) then control:Choose(i) end
                end
                if has(ig, "igEndCombo") then ig.igEndCombo() end
            end
        else
            ig.igText("%s", label)
            for i, item in ipairs(control.items or {}) do
                if draw_selectable(ig, tostring(item), control.selection == i) then control:Choose(i) end
            end
        end
    elseif control.type == "ListView" then
        local label = control.text ~= "" and control.text or "ListView"
        if has(ig, "igBeginTable") and ig.igBeginTable(label, math.max(1, #(control.columns or {})), 0) then
            if has(ig, "igTableSetupColumn") then
                for _, column in ipairs(control.columns or {}) do ig.igTableSetupColumn(tostring(column), 0, 0, 0) end
            end
            if has(ig, "igTableHeadersRow") then ig.igTableHeadersRow() end
            for row_index, row in ipairs(control.rows or {}) do
                if has(ig, "igTableNextRow") then ig.igTableNextRow(0, 0) end
                for column_index = 1, math.max(1, #(control.columns or row)) do
                    if has(ig, "igTableSetColumnIndex") then ig.igTableSetColumnIndex(column_index - 1) end
                    local text = tostring(type(row) == "table" and row[column_index] or row)
                    if draw_selectable(ig, text, control.selection == row_index) then control:SetSelection(row_index) end
                end
            end
            if has(ig, "igEndTable") then ig.igEndTable() end
        else
            ig.igText("%s", label)
            for row_index, row in ipairs(control.rows or {}) do
                if draw_selectable(ig, table.concat(row, " | "), control.selection == row_index) then control:SetSelection(row_index) end
            end
        end
    elseif control.type == "TreeView" then
        ig.igText("%s", control.text ~= "" and control.text or "TreeView")
        local function draw_node(node_id)
            local node = control.tree_nodes[node_id]
            if not node then return end
            local opened = true
            if has(ig, "igTreeNode_Str") then opened = ig.igTreeNode_Str(node.text) end
            if draw_selectable(ig, node.text, control.selection == node_id) then control:SetSelection(node_id) end
            if opened then
                for _, child_id in ipairs(node.children or {}) do draw_node(child_id) end
                if has(ig, "igTreePop") then ig.igTreePop() end
            end
        end
        for _, node_id in ipairs(control.root_nodes or {}) do draw_node(node_id) end
    elseif control.type == "StatusBar" then
        ig.igText("%s", table.concat(control.parts or {}, " | "))
    elseif control.type == "Picture" then
        if control.texture and has(ig, "igImage") then
            ig.igImage(control.texture, vec2(ig, control.texture_w or control.w or 64, control.texture_h or control.h or 64))
        else
            ig.igText("%s", control.value or control.path or control.text or "Picture")
        end
    elseif control.type == "Link" then
        local label = control.text ~= "" and control.text or tostring(control.value or "Link")
        if draw_selectable(ig, label, false) then fire(control, "Click", control.value or control.text) end
    elseif control.type == "Custom" then
        if type(control.draw) == "function" then control.draw(control, ig) else ig.igText("%s", control.text ~= "" and control.text or "Custom") end
    elseif control.type == "Tab" then
        local label = control.text ~= "" and control.text or "Tab"
        if has(ig, "igBeginTabBar") and ig.igBeginTabBar(label, 0) then
            for i, page in ipairs(control.pages or {}) do
                if has(ig, "igBeginTabItem") and ig.igBeginTabItem(page.name, nil, 0) then
                    if control.current_page ~= i then control:UsePage(i) end
                    for _, child in ipairs(page.controls or {}) do if child.visible then draw_text_control(child, ig) end end
                    if has(ig, "igEndTabItem") then ig.igEndTabItem() end
                end
            end
            if has(ig, "igEndTabBar") then ig.igEndTabBar() end
        else
            local page = control.pages[control.current_page or 1]
            ig.igText("%s", page and page.name or label)
        end
    elseif control.type == "LogView" then
        for _, line in ipairs(control.logs or {}) do ig.igText("%s", line.text) end
    elseif control.type == "PathPicker" then
        ig.igText("%s", control.value or control.path or control.text or "")
        if has(ig, "igSameLine") then ig.igSameLine(0, -1) end
        if ig.igButton("Browse##" .. (control.name or "PathPicker"), vec2(ig, 0, 0)) then control:OpenPicker() end
        if control.picker then
            local picker = require("ui.widgets.file_picker")
            local selected = picker.draw(control.picker, ig)
            if selected then control:SetPath(selected); control:ClosePicker() end
        end
    elseif control.type == "DiskList" then
        if has(ig, "igBeginTable") and ig.igBeginTable(control.text ~= "" and control.text or "DiskList", 4, 0) then
            if has(ig, "igTableSetupColumn") then
                ig.igTableSetupColumn("Disk", 0, 0, 0)
                ig.igTableSetupColumn("Size", 0, 0, 0)
                ig.igTableSetupColumn("Type", 0, 0, 0)
                ig.igTableSetupColumn("Risk", 0, 0, 0)
            end
            if has(ig, "igTableHeadersRow") then ig.igTableHeadersRow() end
            for i, disk in ipairs(control.disks or {}) do
                if has(ig, "igTableNextRow") then ig.igTableNextRow(0, 0) end
                local fields = {
                    tostring(disk.label or disk.name or disk.id or disk.index or i),
                    tostring(disk.size or disk.size_text or ""),
                    tostring(disk.type or disk.bus or ""),
                    disk.danger and tostring(disk.danger_reason or "danger") or "",
                }
                for column = 1, 4 do
                    if has(ig, "igTableSetColumnIndex") then ig.igTableSetColumnIndex(column - 1) end
                    if draw_selectable(ig, fields[column], control.target == disk) then control:SetTarget(disk) end
                end
            end
            if has(ig, "igEndTable") then ig.igEndTable() end
        else
            for _, disk in ipairs(control.disks or {}) do
                local label = tostring(disk.label or disk.name or disk.id or disk.index)
                if draw_selectable(ig, label, control.target == disk) then control:SetTarget(disk) end
            end
        end
    elseif control.type == "ConfirmDialog" then
        local title = control.text ~= "" and control.text or "Confirm"
        if control.open and has(ig, "igOpenPopup_Str") then ig.igOpenPopup_Str(title, 0) end
        local visible = true
        if has(ig, "igBeginPopupModal") then visible = ig.igBeginPopupModal(title, nil, 0) end
        if visible then
            ig.igText("%s", title)
            for _, risk in ipairs(control.risks or {}) do ig.igText("%s", tostring(risk)) end
            for _, step in ipairs(control.plan_steps or {}) do ig.igText("%s", tostring(step.action or step)) end
            if ig.igButton("Confirm", vec2(ig, 0, 0)) then control.open = false; control:Confirm(); if has(ig, "igCloseCurrentPopup") then ig.igCloseCurrentPopup() end end
            if has(ig, "igSameLine") then ig.igSameLine(0, -1) end
            if ig.igButton("Cancel", vec2(ig, 0, 0)) then control.open = false; control:Cancel(); if has(ig, "igCloseCurrentPopup") then ig.igCloseCurrentPopup() end end
            if has(ig, "igEndPopup") then ig.igEndPopup() end
        end
    else
        ig.igText("%s", control.text ~= "" and control.text or control.type)
    end
end

function Gui:Draw(ig)
    if not self.visible or self.closed then return false end
    if not ig then return true end
    local open = true
    local visible = ig.igBegin(self.title, nil, 0)
    if visible then
        for _, control in ipairs(self.controls) do
            if control.visible then draw_text_control(control, ig) end
        end
    end
    ig.igEnd()
    if not open then self:Close() end
    return true
end

function M.create(opts)
    opts = opts or {}
    return setmetatable({
        title = opts.title or "PEShell",
        controls = {},
        named = {},
        events = {},
        values = {},
        options = {},
        visible = false,
        closed = false,
        focused = nil,
        current_tab = nil,
        current_tab_page = nil,
    }, Gui)
end

M.Gui = Gui
M.Control = Control

return M
