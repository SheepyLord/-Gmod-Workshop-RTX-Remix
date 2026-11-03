-- The RTX Remix guide's real pages and window code over mocked GMod panels. Documented in
-- companion_guide_harness.lua.md beside this file.
local guide_path, pages_path, i18n_path, catalog, inputs, mode, code, caps_name = ...
CLIENT = true
local values = { nativeloader_language = code or "en", gmod_language = "en" }
local commands, hooks = {}, {}
local expected = dofile(inputs)  -- { pot = { [msgid] = true }, images = { [path] = true } }

local status
if caps_name == "r13" then
    status = { schema = 1, activation = { performance_tier = { tier = "low" }, memory = { profile = "minimum" } } }
elseif caps_name == "r6" then
    status = { schema = 1, activation = { performance_tier = { tier = "low" } } }
else
    status = { schema = 1, activation = {} }
end

local function cv(name) return { GetString = function() return values[name] or "" end } end
CreateClientConVar = function(name, default) if values[name] == nil then values[name] = default end return cv(name) end
GetConVar = cv
istable = function(v) return type(v) == "table" end
isstring = function(v) return type(v) == "string" end
isfunction = function(v) return type(v) == "function" end
IsValid = function(v) return v ~= nil and v ~= false end
TOP, FILL, LEFT, RIGHT, BOTTOM = 1, 2, 3, 4, 5
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER = 0, 1
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
ScrW, ScrH = function() return 1920 end, function() return 1080 end
local fonts = {}
surface = { CreateFont = function(name, data)
    assert(data.font and data.size, "a font needs a face and a size")
    fonts[name] = data
end }
draw = {}
local function refuse() error("the guide must not write files or settings while it is shown") end
local images_checked = {}
file = {
    Exists = function(path, realm)
        if realm == "LUA" then return path == "nativeloader/i18n_data.lua" end
        if realm == "GAME" then
            local name = path:match("^materials/(.+)$")
            images_checked[#images_checked + 1] = name
            return name ~= nil and expected.images[name] == true
        end
        return false
    end,
    Read = function(path, realm)
        assert(path == "native-loader/status.json" and realm == "DATA", "unexpected read " .. tostring(path))
        return "status"
    end,
    Write = refuse, Append = refuse, CreateDir = refuse,
}
util = { JSONToTable = function(body) assert(body == "status") return status end }
Material = function(path)
    return { IsError = function() return false end, Width = function() return 800 end, Height = function() return 400 end }
end
timer = { Simple = function() end, Create = function() end }
hook = { Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end }
concommand = { Add = function(name, fn) commands[name] = fn end }
RunConsoleCommand = refuse
cvars = { AddChangeCallback = function() end }
language = { Add = function() end }

-- Panels: every method a no-op unless defined here; labels must wrap and stretch.
local wrap_errors = {}
local function widget(class, parent)
    local panel = { class = class, parent = parent, children = {} }
    setmetatable(panel, { __index = function() return function() end end })
    function panel:Add(kind) return vgui.Create(kind, self) end
    function panel:SetWrap(on) if not on then wrap_errors[#wrap_errors + 1] = class end end
    function panel:SetText(text) assert(type(text) == "string", "a label's text must be a string") self.text = text end
    function panel:SetFont(name) assert(fonts[name] or name:match("^Derma"), "unknown font " .. tostring(name)) end
    if parent then parent.children[#parent.children + 1] = panel end
    return panel
end
vgui = { Create = widget }

local data = dofile(catalog)
local i18n
include = function(path)
    if path == "nativeloader/i18n_data.lua" then return data end
    if path == "nativeloader/guide_pages.lua" then return dofile(pages_path) end
    assert(path == "nativeloader/i18n.lua", "unexpected include " .. path)
    if not i18n then i18n = dofile(i18n_path) end
    return i18n
end

dofile(guide_path)
local G = assert(NATIVELOADER_GUIDE, "the guide's table")
assert(commands.nativeloader_guide and commands.nativeloader_stability_guide, "the guide's commands")
assert(hooks.InitPostEntity and hooks.InitPostEntity.nativeloader_guide, "the first-session opening")

local function out(...) print(table.concat({ ... }, "\t")) end

if mode == "structure" then
    for _, page in ipairs(G.pages) do
        out("PAGE", page.id, page.title, page.icon or "")
        for _, item in ipairs(page.items) do
            local kind = item[1]
            out("ITEM", page.id, kind, item.when or "")
            if kind == "h" and item.id then out("SECTION", page.id, item.id) end
            if kind == "image" then out("IMAGE", page.id, item[2], tostring(#item - 2)) end
            if kind == "link" then out("LINK", page.id, item[3], item[4] or "") end
            if kind == "button" then out("BUTTON", page.id, table.concat({ unpack(item, 3) }, " ")) end
        end
    end
    print("PASS structure")
    return
end

if mode == "scale" then
    -- A GUI scaler draws DermaDefault 31/14 times as tall as the guide's Tahoma 13 probe: the guide's
    -- fonts follow, its pictures by a whole step; nativeloader_guide_scale overrides the measurement.
    local derma = 31
    draw.GetFontHeight = function(name)
        if name == "DermaDefault" then return derma end
        return fonts[name] and fonts[name].size + 1 or 14
    end
    commands.nativeloader_guide(nil, "nativeloader_guide", { "tab" })
    assert(math.abs(G.scale - 31 / 14) < 1e-9, "scale " .. tostring(G.scale))
    assert(G.picture_scale == 2, "pictures " .. tostring(G.picture_scale))
    assert(fonts.NLGuideBody.size == math.floor(15 * 31 / 14 + 0.5), "body font " .. fonts.NLGuideBody.size)
    values.nativeloader_guide_scale = "1"
    commands.nativeloader_guide(nil, "nativeloader_guide", { "tab" })
    assert(G.scale == 1 and G.picture_scale == 1 and fonts.NLGuideBody.size == 15, "the setting overrides the measurement")
    values.nativeloader_guide_scale = "0"
    derma = 14
    commands.nativeloader_guide(nil, "nativeloader_guide", { "tab" })
    assert(G.scale == 1 and fonts.NLGuideBody.size == 15, "a plain 1080-line game draws the guide at its own size")
    -- A taller screen: 2160 lines (the field's 3840x2160) draws it twice as large, 1440 lines a third larger
    -- with the pictures at their own size.
    ScrH = function() return 2160 end
    commands.nativeloader_guide(nil, "nativeloader_guide", { "tab" })
    assert(G.scale == 2 and G.picture_scale == 2 and fonts.NLGuideBody.size == 30, "2160 lines: scale " .. tostring(G.scale))
    ScrH = function() return 1440 end
    commands.nativeloader_guide(nil, "nativeloader_guide", { "tab" })
    assert(math.abs(G.scale - 4 / 3) < 1e-9 and G.picture_scale == 1 and fonts.NLGuideBody.size == 20, "1440 lines: scale " .. tostring(G.scale))
    ScrH = function() return 1080 end
    print("PASS scale")
    return
end

-- render: open every page and every section by its command; check what was drawn.
local function check_texts(where)
    local shown = assert(G.shown, where .. ": nothing shown")
    assert(#shown.texts > 2, where .. ": an empty page")
    for _, text in ipairs(shown.texts) do
        assert(type(text) == "string" and text ~= "", where .. ": an empty text")
        assert(not text:find("%%s"), where .. ": an unexpanded placeholder in " .. text)
        if code == "en" then
            local plain = text:gsub("^> ", "")
            assert(expected.pot[plain] or plain:sub(1, 1) == "{", where .. ": not in the catalog template: " .. plain)
        end
    end
    for _, path in ipairs(shown.images) do assert(expected.images[path], where .. ": a picture that is not shipped: " .. path) end
    return shown
end

local opened = 0
for _, page in ipairs(G.pages) do
    commands.nativeloader_guide(nil, "nativeloader_guide", { page.id })
    local shown = check_texts(page.id)
    assert(shown.id == page.id, "nativeloader_guide " .. page.id .. " opened " .. tostring(shown.id))
    assert(shown.title == i18n.L(page.title), page.id .. ": the title is not translated")
    opened = opened + 1
    for _, item in ipairs(page.items) do
        if item[1] == "h" and item.id then
            commands.nativeloader_guide(nil, "nativeloader_guide", { page.id, item.id })
            assert(G.view.section == item.id and G.shown.id == page.id, page.id .. "." .. item.id .. " did not open")
        end
    end
    out("SHOWN", page.id, tostring(#shown.texts), tostring(#shown.images))
end
commands.nativeloader_stability_guide(nil, "nativeloader_stability_guide", {})
assert(G.shown.id == "memory", "nativeloader_stability_guide opened " .. tostring(G.shown.id))
commands.nativeloader_guide(nil, "nativeloader_guide", {})
assert(G.shown.id == "welcome", "nativeloader_guide without a page opened " .. tostring(G.shown.id))
commands.nativeloader_guide(nil, "nativeloader_guide", { "no_such_page" })
assert(G.shown.id == "welcome", "an unknown page opens the first page")
assert(#wrap_errors == 0, "text that does not wrap: " .. table.concat(wrap_errors, ", "))
print("PASS render " .. code .. " " .. caps_name .. " " .. opened)
