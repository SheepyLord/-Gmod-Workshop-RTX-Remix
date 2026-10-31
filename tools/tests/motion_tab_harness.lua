-- The Motion importer tab and the Character Motion Importer's builders under mocked Derma.
-- luajit motion_tab_harness.lua <scenario> <companion tab file> <add-on lua/mmd_vmd_npc folder>
-- Scenarios: late, unavailable, windows, shared, fallback, broken, scale, guiscaler, translations.
-- Prints PASS <scenario>.
local scenario, tabFile, addonDir = arg[1], arg[2], arg[3]
assert(scenario and tabFile and addonDir, "usage: motion_tab_harness.lua <scenario> <tab> <addon dir>")

local function noop() end
local function fail(message) error(message, 2) end
local function equal(actual, expected, what)
    if actual ~= expected then fail((what or "value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)) end
end

-- Anything the code reads that this file does not mock: a callable, indexable nothing.
local STUB = newproxy(true)
do
    local mt = getmetatable(STUB)
    mt.__index = function() return STUB end
    mt.__call = function() return STUB end
    mt.__tostring = function() return "<stub>" end
    mt.__concat = function(a, b) return tostring(a) .. tostring(b) end
    for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do
        mt[op] = function() return 0 end
    end
    mt.__lt = function() return false end
    mt.__le = function() return false end
    mt.__len = function() return 0 end
end
local ABSENT = { MMDVMDNPC = true, mmdhl = true, g_SpawnMenu = true, NATIVELOADER_I18N = true }
setmetatable(_G, { __index = function(_, name)
    if ABSENT[name] or type(name) ~= "string" then return nil end
    -- GMod's numeric enums (IN_ATTACK, NOTIFY_HINT, TEXT_ALIGN_CENTER, ...).
    if name:match("^[A-Z][A-Z0-9_]*$") then return 0 end
    return STUB
end })

CLIENT, SERVER = true, false
NODOCK, FILL, LEFT, RIGHT, TOP, BOTTOM = 0, 1, 2, 3, 4, 5
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function istable(v) return type(v) == "table" end
function isnumber(v) return type(v) == "number" end
function isbool(v) return type(v) == "boolean" end
function tobool(v) return v ~= nil and v ~= false and v ~= 0 and v ~= "0" and v ~= "false" end
function IsValid(v) return type(v) == "table" and rawget(v, "valid") ~= false end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
color_white = Color(255, 255, 255)
function ScrW() return 1920 end
function ScrH() return 1080 end
function SysTime() return os.clock() end
function RealTime() return os.clock() end
function CurTime() return os.clock() end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

local convars = { gmod_language = "en" }
local function convar(name)
    return {
        GetString = function() return tostring(convars[name] or "") end,
        GetFloat = function() return tonumber(convars[name]) or 0 end,
        GetInt = function() return math.floor(tonumber(convars[name]) or 0) end,
        GetBool = function() return tobool(convars[name]) end,
    }
end
function CreateClientConVar(name, default)
    if convars[name] == nil then convars[name] = default end
    return convar(name)
end
CreateConVar = CreateClientConVar
function GetConVar(name) return convar(name) end
function convar_set(name, value) convars[name] = value end
local ran, commands = {}, {}
function RunConsoleCommand(name, ...) ran[#ran + 1] = { name, ... } end
concommand = { Add = function(name, fn) commands[name] = fn end }
local callbacks = {}
cvars = { AddChangeCallback = function(name, fn, id) callbacks[name .. "/" .. tostring(id)] = fn end }
local store = {}
cookie = {
    GetString = function(name, default) return store[name] or default end,
    GetNumber = function(name, default) return tonumber(store[name]) or default end,
    Set = function(name, value) store[name] = tostring(value) end,
}
file = { Read = function() return nil end, Exists = function() return false end, Write = noop, Append = noop,
    CreateDir = noop, Delete = noop, Size = function() return -1 end, Find = function() return {}, {} end }
util = { JSONToTable = function() return nil end, TableToJSON = function() return "{}" end,
    SHA1 = function() return "" end, CRC = function(s) return tostring(#tostring(s)) end }
local sent = {}
net = setmetatable({ Start = function(name) sent[#sent + 1] = name end, SendToServer = noop, Receive = noop },
    { __index = function() return noop end })
surface = { CreateFont = noop, SetFont = noop, SetDrawColor = noop, DrawRect = noop, PlaySound = noop,
    GetTextSize = function(text) return #tostring(text or "") * 7, 14 end }
draw = { RoundedBox = noop, SimpleText = noop }
notification = { AddLegacy = noop }
local timers = {}
timer = { Simple = function(_, fn) timers[#timers + 1] = fn end, Create = noop, Remove = noop }
local function flush_timers()
    while #timers > 0 do table.remove(timers, 1)() end
end
local phrases = {}
language = { Add = function(key, value) phrases[key] = value end }

-- GMod's hook library: a non-string identifier is passed first, and dropped once invalid.
local hooks = {}
hook = {
    Add = function(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end,
    Remove = function(name, id) if hooks[name] then hooks[name][id] = nil end end,
    Run = function(name, ...)
        local snapshot = {}
        for id, fn in pairs(hooks[name] or {}) do snapshot[id] = fn end
        for id, fn in pairs(snapshot) do
            if isstring(id) then fn(...)
            elseif IsValid(id) then fn(id, ...)
            else hooks[name][id] = nil end
        end
    end,
}

-- Derma: panels remember what was set on them; unknown methods do nothing.
local Panel = {}
local created = {}
local function method_or_noop(self, key)
    local value = Panel[key]
    if value ~= nil then return value end
    if type(key) == "string" and key:match("^[A-Z]") then return noop end
    return nil
end
local Meta = { __index = method_or_noop }
local serial = 0
local function new_panel(class, parent)
    serial = serial + 1
    local p = setmetatable({ class = class, children = {}, serial = serial, zpos = 0, dock = NODOCK,
        visible = true, enabled = true, tall = 24, wide = 64, text = "" }, Meta)
    created[#created + 1] = p
    if class == "DCheckBoxLabel" or class == "DNumSlider" then
        p.Label = new_panel("DLabel", p)
        if class == "DNumSlider" then p.Slider = new_panel("DSlider", p) end
    end
    if class == "DListView" then p.Columns, p.lines = {}, {} end
    if class == "DComboBox" then p.choices = {} end
    if parent then p:SetParent(parent) end
    return p
end
vgui = { Create = function(class, parent) return new_panel(class, parent) end }

function Panel:SetParent(parent)
    local old = rawget(self, "parent")
    if old then
        for i, child in ipairs(old.children) do if child == self then table.remove(old.children, i) break end end
    end
    self.parent = parent
    if parent then parent.children[#parent.children + 1] = self end
end
function Panel:GetParent() return rawget(self, "parent") end
function Panel:GetChildren() local copy = {} for i, c in ipairs(self.children) do copy[i] = c end return copy end
function Panel:Add(what)
    if isstring(what) then return new_panel(what, self) end
    what:SetParent(self)
    return what
end
function Panel:Remove()
    if rawget(self, "valid") == false then return end
    self.valid = false
    for _, child in ipairs(self:GetChildren()) do child:Remove() end
    local onRemove = rawget(self, "OnRemove")
    if onRemove then onRemove(self) end
    self:SetParent(nil)
end
function Panel:Close() self:Remove() end
function Panel:GetCanvas() return self end
function Panel:Dock(side) self.dock = side end
function Panel:SetZPos(z) self.zpos = z end
function Panel:DockMargin(l, t, r, b) self.margin = { l, t, r, b } end
function Panel:GetDockMargin() local m = rawget(self, "margin") or { 0, 0, 0, 0 } return m[1], m[2], m[3], m[4] end
function Panel:DockPadding(l, t, r, b) self.padding = { l, t, r, b } end
function Panel:GetDockPadding() local m = rawget(self, "padding") or { 0, 0, 0, 0 } return m[1], m[2], m[3], m[4] end
function Panel:SetTall(h) self.tall = h end
function Panel:GetTall() return self.tall end
function Panel:SetWide(w) self.wide = w end
function Panel:GetWide() return self.wide end
function Panel:SetSize(w, h) self.wide, self.tall = w, h end
function Panel:SetVisible(v) self.visible = v and true or false end
function Panel:IsVisible() return self.visible end
function Panel:SetEnabled(v) self.enabled = v and true or false end
function Panel:IsEnabled() return self.enabled end
function Panel:IsHovered() return false end
function Panel:SetText(text)
    self.text = tostring(text)
    if self.class == "DTextEntry" then self.value = self.text end
    if self.class == "DCheckBoxLabel" or self.class == "DNumSlider" then self.Label.text = self.text end
end
function Panel:GetText() return self.text end
function Panel:SetFont(font) self.font = font end
function Panel:GetFont() return rawget(self, "font") end
function Panel:SetTextColor(color) self.color = color end
function Panel:SetTooltip(text) self.tooltip = text end
function Panel:SetImage(path) self.image = path end
function Panel:SetPlaceholderText(text) self.placeholder = text end
function Panel:SetValue(value)
    if self.class == "DCheckBoxLabel" then
        self.checked = tobool(value)
        if rawget(self, "OnChange") then self:OnChange(self.checked) end
        return
    end
    if self.class == "DComboBox" then self.text = tostring(value) return end
    self.value = value
    if self.class == "DNumSlider" and rawget(self, "OnValueChanged") then self:OnValueChanged(value) end
end
function Panel:GetValue() if self.class == "DTextEntry" then return rawget(self, "value") or "" end return rawget(self, "value") end
function Panel:SetChecked(v) self.checked = v and true or false end
function Panel:GetChecked() return rawget(self, "checked") == true end
function Panel:SetFraction(v) self.fraction = v end
function Panel:SetConVar(name) self.convar = name end
function Panel:AddChoice(text, data) self.choices[#self.choices + 1] = { text, data } end
function Panel:IsMenuOpen() return false end
function Panel:AddColumn(title)
    local column = new_panel("DListView_Column", self)
    column.text = title
    self.Columns[#self.Columns + 1] = column
    return column
end
function Panel:AddLine(...)
    local line = new_panel("DListView_Line", self)
    line.Columns = {}
    for i = 1, select("#", ...) do
        local cell = new_panel("DListViewLabel", line)
        cell.text = tostring((select(i, ...)))
        line.Columns[i] = cell
    end
    self.lines[#self.lines + 1] = line
    return line
end
function Panel:Clear()
    if self.class == "DListView" then
        for _, line in ipairs(self.lines) do line:Remove() end
        self.lines = {}
    elseif self.class == "DComboBox" then
        self.choices = {}
    else
        for _, child in ipairs(self:GetChildren()) do child:Remove() end
    end
end
function Panel:GetLines() return self.lines end
function Panel:GetSelected() return {} end
function Panel:GetSelectedLine() return nil end
function Panel:SelectItem(line)
    self.selectedLine = line
    if rawget(self, "OnRowSelected") then self:OnRowSelected(1, line) end
end

-- Helpers over the mocked tree.
local function walk(panel, visit)
    visit(panel)
    for _, child in ipairs(panel.children) do walk(child, visit) end
end
local function find_all(panel, test)
    local found = {}
    walk(panel, function(p) if rawget(p, "valid") ~= false and test(p) then found[#found + 1] = p end end)
    return found
end
local function by_text(panel, text, class)
    for _, p in ipairs(find_all(panel, function(p) return p.text == text and (not class or p.class == class) end)) do
        return p
    end
    fail("no " .. (class or "panel") .. " with text " .. tostring(text))
end
local function has_text(panel, text)
    return #find_all(panel, function(p) return p.text == text end) > 0
end
local function created_of(class)
    local found = {}
    for _, p in ipairs(created) do
        if p.class == class and rawget(p, "valid") ~= false then found[#found + 1] = p end
    end
    return found
end
local function shown(panel)
    local p = panel
    while p do
        if p.visible == false or rawget(p, "valid") == false then return false end
        p = rawget(p, "parent")
    end
    return true
end
local function inside(panel, ancestor)
    local p = rawget(panel, "parent")
    while p do if p == ancestor then return true end p = rawget(p, "parent") end
    return false
end
-- Docked children in the order Derma lays them out (ZPos, then creation).
local function flow(panel, side)
    local list = {}
    for _, child in ipairs(panel.children) do
        if child.visible and (side == nil or child.dock == side) then list[#list + 1] = child end
    end
    table.sort(list, function(a, b) if a.zpos ~= b.zpos then return a.zpos < b.zpos end return a.serial < b.serial end)
    return list
end
-- The texts of a stacked column, top to bottom, through each child's labels.
local function column_texts(panel)
    local texts = {}
    for _, child in ipairs(flow(panel, TOP)) do
        walk(child, function(p)
            if (p.class == "DLabel" or p.class == "DButton") and p.text ~= "" then texts[#texts + 1] = p.text end
        end)
    end
    return texts
end
local function before(texts, first, second)
    local a, b
    for i, t in ipairs(texts) do
        if t == first and not a then a = i end
        if t == second and not b then b = i end
    end
    assert(a and b, "missing " .. tostring(a and second or first))
    assert(a < b, first .. " should come before " .. second)
end

-- The add-on: its catalogs and lookups from sh_core.lua, then the client files the tab uses.
local function load_addon(withBuilders)
    MMDVMDNPC = { DataRoot = "mmd_vmd_npc", MotionRoot = "mmd_vmd_npc/motions", CacheExtension = ".json",
        CategoryUserImport = "__user_import", CategoryAddonOther = "__addon_other", MotionDetailsOrdered = {} }
    local f = assert(io.open(addonDir .. "/sh_core.lua", "rb"))
    local text = f:read("*a")
    f:close()
    local first = assert(text:find("MMDVMDNPC.I18N = MMDVMDNPC.I18N or {}", 1, true))
    local last = assert(text:find("\nif CLIENT then", text:find("function MMDVMDNPC.CategoryDisplayName", first, true), true))
    assert(loadstring(text:sub(first, last), "@sh_core.lua"))()
    include = function() return nil end
    dofile(addonDir .. "/cl_menu.lua")
    dofile(addonDir .. "/cl_import_data.lua")
    dofile(addonDir .. "/cl_import_bake.lua")
    dofile(addonDir .. "/cl_importer.lua")
    assert(isfunction(MMDVMDNPC.BuildMotionManager) and isfunction(MMDVMDNPC.BuildMotionImporter), "builders")
    assert(isfunction(MMDVMDNPC.OpenMotionManager) and isfunction(MMDVMDNPC.OpenMotionImporter), "windows")
    if not withBuilders then
        MMDVMDNPC.BuildMotionManager, MMDVMDNPC.BuildMotionImporter = nil, nil
    end
end

local translated = false
local function load_tab()
    local tabs = {}
    spawnmenu = {
        AddCreationTab = function(name, build, icon, order, tooltip) tabs[name] = { Function = build, Icon = icon, Order = order, Tooltip = tooltip } end,
        GetCreationTabs = function() return tabs end,
    }
    include = function(path)
        if path == "nativeloader/i18n.lua" then
            return { L = function(text) return translated and ("translated:" .. text) or text end }
        end
    end
    dofile(tabFile)
    local tab = assert(tabs["#nativeloader.motion_importer"], "tab registered")
    return tab
end

local function file_access(available)
    local picks = {}
    mmdhl = { FileAccess = {
        IsAvailable = function() if available() then return true end return false, "turned off", "disabled" end,
        Pick = function(request, done) picks[#picks + 1] = { request = request, done = done } end,
        Read = noop, Release = noop, OpenManager = noop,
    } }
    return picks
end

local function spawnmenu_window()
    local closed = 0
    g_SpawnMenu = setmetatable({ Close = function() closed = closed + 1 end }, Meta)
    return function() return closed end
end

if scenario == "late" then
    -- The tab is built before the add-on loads; it waits, then fills itself.
    local tab = load_tab()
    local panel = tab.Function()
    panel:Think()
    assert(not IsValid(rawget(panel, "Workspace")), "nothing to build yet")
    assert(has_text(panel, "Import VMD files and manage your motion library and playback."), "summary while waiting")
    local picks = file_access(function() return true end)
    load_addon(true)
    panel:Think()
    local workspace = rawget(panel, "Workspace")
    assert(IsValid(workspace), "workspace after the add-on loaded")
    assert(not IsValid(rawget(panel, "Summary")), "summary replaced")
    local closedCount = spawnmenu_window()

    -- Top bar: the two sections on the left, Open in window on the right.
    local header = workspace.Header
    local sections = flow(header, LEFT)
    equal(#sections, 2, "section buttons")
    equal(sections[1].text, "Import MMD Motion", "first section")
    equal(sections[2].text, "Motion Manager", "second section")
    equal(sections[1].Selected, true, "importer shown first")
    local openWindow = flow(header, RIGHT)[1]
    equal(openWindow.text, "Open in window", "window action")
    assert(openWindow.enabled, "window action enabled")

    -- The importer fills the tab: inputs on the left, the bake side on the right.
    local importer = workspace.Pages.import
    assert(IsValid(importer) and shown(importer), "importer shown")
    local body = flow(importer, FILL)[1]
    local inputs = flow(body, LEFT)[1]
    local side = flow(body, FILL)[1]
    equal(inputs.class, "DScrollPanel", "inputs scroll")
    local left, right = column_texts(inputs), column_texts(side)
    -- The desktop importer's order: body, music, camera, offset, metadata, face/flex.
    for _, pair in ipairs({
        { "Body Motion VMD", "Music File" }, { "Music File", "Camera VMD" },
        { "Camera VMD", "Audio offset (seconds)" }, { "Audio offset (seconds)", "Motion Metadata" },
        { "Motion Metadata", "Face/Flex VMDs (if they are stored in separate VMDs from the body motion)" },
    }) do before(left, pair[1], pair[2]) end
    for _, field in ipairs({ "Category", "Display Name", "English Name", "Artist", "Language", "Link", "Motion Artist" }) do
        assert(has_text(inputs, field), "metadata field " .. field)
    end
    assert(has_text(inputs, "Add Face/Flex Motions") and has_text(inputs, "Remove Selected Flex"), "flex actions")
    -- Then the bake, its options, the progress and the log.
    before(right, "Bake Motion and Import", "Bake Options")
    before(right, "Bake Options", "Disable foot IK (motion baked without IK)")
    before(right, "Unify ground height (cancel stage placement)", "Import Log and Output")
    assert(#find_all(side, function(p) return p.class == "DProgress" end) == 1, "progress bar")
    local log = flow(side, FILL)[1]
    assert(log.class == "DTextEntry" and log.dock == FILL, "the log fills the rest")
    assert(by_text(side, "Copy Log", "DButton"), "copy log")
    assert(by_text(importer, "Bake Motion and Import", "DButton").enabled, "bake enabled with file access")

    -- Choosing a body motion goes through Model Hotloader's picker and shows the file.
    by_text(inputs, "Browse", "DButton"):DoClick()
    equal(#picks, 1, "picker opened")
    picks[1].done(true, { { name = "dance.vmd", displayPath = "C:/motions/dance.vmd" } })
    local entries = find_all(inputs, function(p) return p.class == "DTextEntry" and p.value == "C:/motions/dance.vmd" end)
    equal(#entries, 1, "body file shown")
    equal(MMDVMDNPC.Importer.State.meta.display_name, "dance", "name filled from the file")

    -- The library: search, categories, list and its actions left; details, music, playback right.
    sections[2]:DoClick()
    flush_timers()
    local manager = workspace.Pages.manager
    assert(IsValid(manager) and shown(manager) and not shown(importer), "manager shown, importer hidden")
    equal(sections[2].Selected, true, "manager selected")
    local listSide = flow(manager, LEFT)[1]
    local detailSide = flow(manager, FILL)[1]
    local list = find_all(listSide, function(p) return p.class == "DListView" end)[1]
    assert(list and list.dock == FILL, "motion list")
    local titles = {}
    for i, column in ipairs(list.Columns) do titles[i] = column.text end
    equal(table.concat(titles, "|"), "Motion ID|Category|Duration|Music|Camera|Built|Wheel", "list columns")
    assert(#find_all(listSide, function(p) return p.class == "DTextEntry" and p.placeholder == "Search name, artist, id, source, or music" end) == 1, "search")
    assert(#find_all(listSide, function(p) return p.class == "DComboBox" end) == 1, "categories")
    for _, action in ipairs({ "Rename", "☆ Add To Wheel", "Debug", "Delete Motion + Music", "Refresh" }) do
        assert(inside(by_text(manager, action, "DButton"), listSide), action .. " under the list")
    end
    for _, action in ipairs({ "Build Selected", "Play Built", "Stop", "Clear This Model", "Clear All Models For Motion",
        "Save Offset", "Preview Music Only", "Preview Motion", "Stop Music" }) do
        assert(inside(by_text(manager, action, "DButton"), detailSide), action .. " beside the list")
    end
    local settings = find_all(detailSide, function(p) return p.class == "DScrollPanel" end)[1]
    before(column_texts(settings), "Audio Sync", "Playback")
    for _, text in ipairs({ "Play music", "Omnidirectional music (no panning)", "Volume", "Music full-volume range" }) do
        assert(has_text(settings, text), "setting " .. text)
    end
    assert(#sent >= 2, "the library asked for the motions")

    -- A selected motion's details, then Open in window gives the floating Motion Manager.
    local dance = { id = "dance", displayName = "Dance", duration = 12, frameCount = 360,
        category = "__user_import", musicSound = "", hasCamera = true, built = false, link = "example.com" }
    MMDVMDNPC.MotionDetailsOrdered, MMDVMDNPC.MotionDetails.dance = { dance }, dance
    hook.Run("MMDVMDNPCMotionDetailsUpdated")
    flush_timers()
    equal(#list.lines, 1, "one motion listed")
    list:SelectItem(list.lines[1])
    assert(find_all(detailSide, function(p) return p.class == "DLabel" and p.text:find("Dance", 1, true) == 1 end)[1], "details shown")
    openWindow:DoClick()
    equal(closedCount(), 1, "spawn menu closed")
    local frames = created_of("DFrame")
    equal(#frames, 1, "Motion Manager window")
    assert(#find_all(frames[1], function(p) return p.class == "DListView" end) == 1, "window has the library")
    -- The importer section opens the importer window.
    sections[1]:DoClick()
    openWindow:DoClick()
    equal(closedCount(), 2, "spawn menu closed again")
    equal(#created_of("DFrame"), 2, "importer window")
    equal(store.nativeloader_motion_section, "import", "section remembered")
elseif scenario == "unavailable" then
    -- No file access: a notice with Resolve, the importer's controls disabled, until it comes.
    local on = false
    load_addon(true)
    local tab = load_tab()
    local panel = tab.Function()
    panel:Think()
    local importer = rawget(panel, "Workspace").Pages.import
    local notice = flow(importer, TOP)[1]
    assert(notice.visible, "notice shown")
    equal(notice.Text.text, "Model Hotloader is not installed: hot motion import is not available.", "notice")
    equal(notice.Resolve.text, "Resolve", "resolve")
    assert(not by_text(importer, "Bake Motion and Import", "DButton").enabled, "bake disabled")
    for _, browse in ipairs(find_all(importer, function(p) return p.text == "Browse" end)) do
        assert(not browse.enabled, "browse disabled")
    end
    file_access(function() return on end)
    hook.Run("MMDVMDNPCImportAvailabilityChanged")
    assert(notice.visible, "still unavailable")
    equal(notice.Text.text, "Hot motion import is not available right now.", "short notice")
    assert(notice.Settings.visible, "file access settings offered when it is turned off")
    on = true
    hook.Run("MMDVMDNPCImportAvailabilityChanged")
    assert(not notice.visible, "notice gone")
    assert(by_text(importer, "Bake Motion and Import", "DButton").enabled, "bake enabled")
    assert(IsValid(importer), "the tab keeps its importer")
elseif scenario == "windows" then
    -- The floating windows and their console commands build the same parts in Derma's look.
    file_access(function() return true end)
    load_addon(true)
    assert(isfunction(commands.mmdvmd_import) and isfunction(commands.mmdvmd_menu), "console commands")
    commands.mmdvmd_menu()
    local frame = created_of("DFrame")[1]
    assert(frame, "manager window")
    local root = flow(frame, FILL)[1]
    local order = {}
    for _, child in ipairs(flow(root)) do order[#order + 1] = child.class .. ":" .. child.dock end
    -- As before: the bar, the list, then the strips below it from the bottom up.
    equal(table.concat(order, " "), "DPanel:4 DLabel:5 DPanel:5 DPanel:5 DPanel:5 DPanel:5 DListView:1", "manager window layout")
    local controls = flow(root, BOTTOM)[5]
    local buttons = {}
    for _, b in ipairs(flow(controls)) do buttons[#buttons + 1] = b.text end
    equal(table.concat(buttons, "|"), "Debug|Build Selected|Play Built|☆ Add To Wheel|Rename|Stop|Clear This Model|Clear All Models For Motion|Delete Motion + Music", "manager window actions")
    assert(rawget(by_text(root, "Build Selected", "DButton"), "Paint") == nil, "no light theme in the window")
    local list = flow(root, FILL)[1]
    equal(#list.Columns, 9, "the window keeps every column")
    frame:Close()
    assert(next(hooks.MMDVMDNPCMotionListUpdated or {}) == nil, "window hooks released")

    commands.mmdvmd_import()
    local importer = created_of("DFrame")[1]
    equal(MMDVMDNPC.Importer.Frame, importer, "importer window")
    local iroot = flow(importer, FILL)[1]
    local bottom = flow(iroot, BOTTOM)[1]
    local scroll = flow(iroot, FILL)[1]
    equal(scroll.class, "DScrollPanel", "one scroll of inputs")
    local texts = column_texts(scroll)
    before(texts, "Body Motion VMD", "Face/Flex VMDs (if they are stored in separate VMDs from the body motion)")
    before(texts, "Bake Options", "Import Log and Output")
    assert(inside(by_text(iroot, "Bake Motion and Import", "DButton"), bottom), "bake in the bottom bar")
    assert(rawget(by_text(iroot, "Bake Motion and Import", "DButton"), "Paint"), "the window's own bake button")
    assert(#find_all(iroot, function(p) return p.class == "DProgress" end) == 1, "progress")
    -- Opening it again brings the same window forward.
    equal(MMDVMDNPC.OpenMotionImporter(), importer, "one importer window")
    -- File access going away closes it and explains.
    mmdhl = nil
    hook.Run("MMDVMDNPCImportAvailabilityChanged")
    assert(not IsValid(importer), "window closed")
    assert(IsValid(MMDVMDNPC.Importer.ResolveFrame), "resolve window")
elseif scenario == "shared" then
    -- The tab and the window show the same chosen files and settings.
    local picks = file_access(function() return true end)
    load_addon(true)
    local tab = load_tab()
    local panel = tab.Function()
    panel:Think()
    local importer = rawget(panel, "Workspace").Pages.import
    local window = MMDVMDNPC.OpenMotionImporter()
    local wroot = flow(window, FILL)[1]
    by_text(wroot, "Browse", "DButton"):DoClick()
    picks[#picks].done(true, { { name = "camera_test.vmd", displayPath = "D:/camera_test.vmd" } })
    importer:Think()
    equal(#find_all(importer, function(p) return p.class == "DTextEntry" and p.value == "D:/camera_test.vmd" end), 1, "tab shows the window's file")
    local check = by_text(wroot, "Unify ground height (cancel stage placement)", "DCheckBoxLabel")
    check:SetValue(1)
    importer:Think()
    assert(by_text(importer, "Unify ground height (cancel stage placement)", "DCheckBoxLabel"):GetChecked(), "option shared")
    equal(store.mmdvmd_import_unify_ground, "1", "option remembered")
elseif scenario == "fallback" then
    -- An add-on copy without the builders still gets its windows from the tab.
    load_addon(false)
    local tab = load_tab()
    local panel = tab.Function()
    panel:Think()
    assert(not IsValid(rawget(panel, "Workspace")), "no workspace without builders")
    local launchers = rawget(panel, "Launchers")
    assert(IsValid(launchers), "launchers")
    local buttons = flow(launchers, LEFT)
    equal(#buttons, 2, "both windows")
    local opened
    MMDVMDNPC.OpenMotionManager = function() opened = "manager" end
    spawnmenu_window()
    by_text(launchers, "Motion Manager", "DButton"):DoClick()
    equal(opened, "manager", "window opened")
elseif scenario == "broken" then
    -- A builder that fails: one report, the window buttons instead, no retry every frame (review R4).
    load_addon(true)
    local reports = {}
    ErrorNoHalt = function(message) reports[#reports + 1] = message end
    MMDVMDNPC.BuildMotionImporter = function() error("builder failed") end
    local tab = load_tab()
    local panel = tab.Function()
    panel:Think()
    panel:Think()
    assert(not IsValid(rawget(panel, "Workspace")), "no workspace from a failing builder")
    equal(#reports, 1, "one report")
    assert(reports[1]:find("builder failed", 1, true), "the builder's error is reported")
    assert(IsValid(rawget(panel, "Launchers")), "window buttons instead")
    equal(#panel:GetChildren(), 1, "no half-built page left")
elseif scenario == "scale" then
    -- The importer's size follows the screen as External Models does (1 at 1080p, 2 at 2160p), times
    -- the player's mmd_vmd_npc_menu_scale (review R4: at 4K its text was half the spawn menu's).
    load_addon(true)
    equal(MMDVMDNPC.MenuScale(), 1, "1080p")
    ScrH = function() return 2160 end
    equal(MMDVMDNPC.MenuScale(), 2, "2160p")
    ScrH = function() return 1440 end
    equal(MMDVMDNPC.MenuScale(), 1440 / 1080, "1440p")
    ScrH = function() return 720 end
    equal(MMDVMDNPC.MenuScale(), 1, "below 1080p the screen adds nothing")
    ScrH = function() return 2160 end
    convar_set("mmd_vmd_npc_menu_scale", "0.75")
    equal(MMDVMDNPC.MenuScale(), 1.5, "the player's multiplier on top")
    ScrH = function() return 1080 end
elseif scenario == "guiscaler" then
    -- With GUI Scaler installed, the tab and its sections opt out of its second scaling (gScF), as
    -- Model Hotloader's panels do; without it nothing is marked (review R4).
    load_addon(true)
    local real = GetConVar
    GetConVar = function(name)
        if name == "guiscaler_scale_multiplier" then return nil end
        return real(name)
    end
    local tab = load_tab()
    local plain = tab.Function()
    plain:Think()
    local workspace = rawget(plain, "Workspace")
    assert(IsValid(workspace), "workspace")
    assert(not rawget(workspace, "gScF") and not rawget(workspace.OpenWindow, "gScF"), "nothing marked without GUI Scaler")
    GetConVar = real -- the mock answers every name, so GUI Scaler counts as installed
    local scaled = tab.Function()
    scaled:Think()
    workspace = rawget(scaled, "Workspace")
    assert(rawget(workspace, "gScF") and rawget(workspace.OpenWindow, "gScF"), "the tab's own buttons opt out")
    assert(rawget(workspace.Pages.import, "gScF"), "the importer section opts out")
    workspace.Show("manager")
    assert(rawget(workspace.Pages.manager, "gScF"), "a section built later opts out")
elseif scenario == "translations" then
    load_tab()
    translated = true
    callbacks["nativeloader_language/nativeloader_motion_tab"]()
    equal(phrases["nativeloader.motion_importer"], "translated:Motion importer", "tab title")
    local tab = spawnmenu.GetCreationTabs()["#nativeloader.motion_importer"]
    assert(tab.Tooltip:find("translated:", 1, true), "tooltip")
    callbacks["gmod_language/nativeloader_motion_tab"]()
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
