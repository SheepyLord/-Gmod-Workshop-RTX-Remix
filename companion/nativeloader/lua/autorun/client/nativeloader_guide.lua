-- The in-game RTX Remix guide (nativeloader_guide): how to find, understand and use every setting of
-- the RTX package and Remix, with labeled pictures. A window with the pages and their sections on the
-- left and the page on the right. It opens once by itself on the first RTX session, then from the
-- console (nativeloader_guide [page] [section]) or the RTX Remix tab's Start here;
-- nativeloader_stability_guide opens the Performance and memory page. The pages are in
-- nativeloader/guide_pages.lua; pictures are in materials/nativeloader/guide/ (a missing one is left
-- out with its legend). The text is translated (nativeloader/i18n.lua). Documented in
-- nativeloader_guide.lua.md beside this file.
local SHOWN = "nativeloader_companion/guide_shown.txt"
local i18n = include("nativeloader/i18n.lua")
local L = i18n.L
local PAGES = include("nativeloader/guide_pages.lua").pages

NATIVELOADER_GUIDE = NATIVELOADER_GUIDE or {}
local GUIDE = NATIVELOADER_GUIDE
GUIDE.pages = PAGES

local COLOR = {
    text = Color(228, 230, 234), dim = Color(160, 166, 174), green = Color(118, 185, 0),
    page = Color(33, 35, 40), nav = Color(25, 27, 31), hover = Color(44, 48, 55), active = Color(52, 72, 26),
    tip = Color(31, 46, 22), warn = Color(62, 46, 17), amber = Color(232, 168, 40), code = Color(16, 17, 20),
    frame = Color(74, 79, 88), badge = Color(12, 12, 12),
}

-- Which loader wrote native-loader/status.json: the guide shows only advice that loader supports.
-- Workshop updates can reach an older winmm.dll, whose config parser rejects newer keys.
local function loader()
    local ok, status = pcall(function()
        local body = file.Read("native-loader/status.json", "DATA")
        return body and util.JSONToTable(body)
    end)
    local activation = ok and type(status) == "table" and status.schema == 1 and status.activation
    local r6 = type(activation) == "table" and type(activation.performance_tier) == "table"
    local r13 = r6 and type(activation.memory) == "table"
    return { r6 = r6, legacy = not r6, r13 = r13, pre13 = not r13 }
end

local function shown(item, caps)
    return item.when == nil or caps[item.when] == true
end

local fonts = false
local function make_fonts()
    if fonts then return end
    fonts = true
    -- Tahoma, as DermaDefault: Windows supplies the glyphs of the other languages.
    local function font(name, size, weight)
        surface.CreateFont(name, { font = "Tahoma", size = size, weight = weight, antialias = true, extended = true })
    end
    font("NLGuideTitle", 27, 800)
    font("NLGuideHeading", 20, 800)
    font("NLGuideBody", 15, 500)
    font("NLGuideBold", 15, 800)
    font("NLGuideNav", 15, 800)
    font("NLGuideNavSection", 14, 500)
    font("NLGuideBadge", 14, 900)
    surface.CreateFont("NLGuideCode", { font = "Lucida Console", size = 14, weight = 500, antialias = true })
end

-- The text the open page shows, in order (for tests and the in-game check).
local function record(text)
    if GUIDE.shown then GUIDE.shown.texts[#GUIDE.shown.texts + 1] = text end
end

local function label(parent, text, font, color, left, top)
    local item = parent:Add("DLabel")
    item:Dock(TOP)
    item:DockMargin(left or 18, top or 3, 18, 3)
    item:SetFont(font or "NLGuideBody")
    item:SetTextColor(color or COLOR.text)
    item:SetText(text)
    item:SetWrap(true)
    item:SetAutoStretchVertical(true)
    record(text)
    return item
end

-- A row: a marker painted on the left (a badge, a step number or a bullet) and wrapped text.
local function row(parent, text, paint_marker, indent)
    local holder = parent:Add("DPanel")
    holder:Dock(TOP)
    holder:DockMargin(18, 3, 18, 3)
    holder:SetPaintBackground(false)
    local body = holder:Add("DLabel")
    body:Dock(TOP)
    body:DockMargin(indent or 32, 2, 0, 0)
    body:SetFont("NLGuideBody")
    body:SetTextColor(COLOR.text)
    body:SetText(text)
    body:SetWrap(true)
    body:SetAutoStretchVertical(true)
    record(text)
    holder.Paint = function(_, w, h) paint_marker(w, h) end
    holder.Think = function(self)
        local tall = math.max(24, body:GetTall() + 4)
        if self:GetTall() ~= tall then self:SetTall(tall) end
    end
    return holder
end

local function badge(x, y, number)
    draw.RoundedBox(11, x, y, 22, 22, COLOR.green)
    draw.SimpleText(tostring(number), "NLGuideBadge", x + 11, y + 11, COLOR.badge, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function entries(item, caps)
    local out = {}
    for index = 2, #item do
        local entry = item[index]
        if type(entry) == "table" then
            if shown(entry, caps) then out[#out + 1] = entry[1] end
        else
            out[#out + 1] = entry
        end
    end
    return out
end

local function add_steps(parent, item, caps)
    for number, text in ipairs(entries(item, caps)) do
        row(parent, L(text), function()
            draw.SimpleText(number .. ".", "NLGuideBold", 4, 4, COLOR.green)
        end)
    end
end

local function add_list(parent, item, caps)
    for _, text in ipairs(entries(item, caps)) do
        row(parent, L(text), function()
            surface.SetDrawColor(COLOR.green)
            surface.DrawRect(8, 10, 6, 6)
        end, 26)
    end
end

-- A box with a colored bar: a tip or a caution.
local function add_box(parent, text, background, bar)
    local holder = parent:Add("DPanel")
    holder:Dock(TOP)
    holder:DockMargin(18, 8, 18, 8)
    local body = holder:Add("DLabel")
    body:Dock(TOP)
    body:DockMargin(16, 8, 12, 0)
    body:SetFont("NLGuideBody")
    body:SetTextColor(COLOR.text)
    body:SetText(text)
    body:SetWrap(true)
    body:SetAutoStretchVertical(true)
    record(text)
    holder.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 0, w, h, background)
        surface.SetDrawColor(bar)
        surface.DrawRect(0, 0, 5, h)
    end
    holder.Think = function(self)
        local tall = body:GetTall() + 16
        if self:GetTall() ~= tall then self:SetTall(tall) end
    end
end

local function add_code(parent, text)
    local item = label(parent, text, "NLGuideCode", COLOR.text, 30, 6)
    item:SetTextInset(10, 0)
    item.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, COLOR.code) end
end

-- A picture at its own size (made from sharp captures; never enlarged, only made smaller to fit), and
-- its legend: entry n explains the badge numbered n.
local function add_image(parent, item)
    local path = item[2]
    if not file.Exists("materials/" .. path, "GAME") then return end
    local material = Material(path, "smooth")
    if material:IsError() then return end
    local width, height = material:Width(), material:Height()
    if width <= 0 or height <= 0 then return end
    local holder = parent:Add("DPanel")
    holder:Dock(TOP)
    holder:DockMargin(18, 10, 18, 6)
    holder:SetTall(height + 2)
    holder.Paint = function(_, w)
        local scale = math.min(1, (w - 2) / width)
        local dw, dh = math.floor(width * scale), math.floor(height * scale)
        surface.SetDrawColor(COLOR.frame)
        surface.DrawOutlinedRect(0, 0, dw + 2, dh + 2)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(material)
        surface.DrawTexturedRect(1, 1, dw, dh)
    end
    holder.PerformLayout = function(self, w)
        local tall = math.floor(height * math.min(1, (w - 2) / width)) + 2
        if self:GetTall() ~= tall then self:SetTall(tall) end
    end
    GUIDE.shown.images[#GUIDE.shown.images + 1] = path
    for number = 3, #item do
        row(parent, L(item[number]), function() badge(0, 1, number - 2) end)
    end
end

local function add_term(parent, word, meaning)
    local title = label(parent, L(word), "NLGuideBold", COLOR.green, 18, 8)
    title:DockMargin(18, 8, 18, 0)
    label(parent, L(meaning), "NLGuideBody", COLOR.text, 32, 1)
end

local function add_button(parent, text, action)
    local button = parent:Add("DButton")
    button:Dock(TOP)
    button:DockMargin(18, 6, 18, 6)
    button:SetTall(30)
    button:SetFont("NLGuideBold")
    button:SetText(text)
    button.DoClick = action
    record(text)
    return button
end

local open_guide

-- The page, built into the content area; heading panels are kept by section id for the navigation.
local function build_page(view, page, caps)
    local content = view.content
    content:Clear()
    GUIDE.shown = { id = page.id, title = L(page.title), texts = {}, images = {} }
    view.sections = {}
    local title = label(content, L(page.title), "NLGuideTitle", COLOR.text, 18, 14)
    title:DockMargin(18, 14, 18, 6)
    for _, item in ipairs(page.items) do
        if shown(item, caps) then
            local kind = item[1]
            if kind == "h" then
                local heading = label(content, L(item[2]), "NLGuideHeading", COLOR.green, 18, 18)
                heading:DockMargin(18, 20, 18, 4)
                if item.id then view.sections[item.id] = heading end
            elseif kind == "p" then
                label(content, L(item[2]))
            elseif kind == "q" then
                label(content, L(item[2]), "NLGuideBold", COLOR.text, 18, 10)
            elseif kind == "steps" then
                add_steps(content, item, caps)
            elseif kind == "list" then
                add_list(content, item, caps)
            elseif kind == "image" then
                add_image(content, item)
            elseif kind == "term" then
                add_term(content, item[2], item[3])
            elseif kind == "tip" then
                add_box(content, L(item[2]), COLOR.tip, COLOR.green)
            elseif kind == "warn" then
                add_box(content, L(item[2]), COLOR.warn, COLOR.amber)
            elseif kind == "code" then
                add_code(content, item[2])
            elseif kind == "button" then
                local commands = { unpack(item, 3) }
                add_button(content, L(item[2]), function()
                    for _, command in ipairs(commands) do RunConsoleCommand(command) end
                end)
            elseif kind == "link" then
                local target, section = item[3], item[4]
                add_button(content, "> " .. L(item[2]), function() open_guide(target, section) end)
            end
        end
    end
    -- The way on: the previous and the next page.
    local index
    for i, other in ipairs(PAGES) do if other == page then index = i end end
    local bar = content:Add("DPanel")
    bar:Dock(TOP)
    bar:DockMargin(18, 24, 18, 18)
    bar:SetTall(32)
    bar:SetPaintBackground(false)
    if PAGES[index - 1] then
        local previous = bar:Add("DButton")
        previous:Dock(LEFT)
        previous:SetWide(300)
        previous:SetText(string.format(L("Previous: %s"), L(PAGES[index - 1].title)))
        previous.DoClick = function() open_guide(PAGES[index - 1].id) end
    end
    if PAGES[index + 1] then
        local following = bar:Add("DButton")
        following:Dock(RIGHT)
        following:SetWide(300)
        following:SetText(string.format(L("Next: %s"), L(PAGES[index + 1].title)))
        following.DoClick = function() open_guide(PAGES[index + 1].id) end
    end
end

local function scroll_to(view, section)
    local target = section and view.sections[section]
    timer.Simple(0.15, function()
        if not IsValid(view.content) then return end
        local bar = view.content:GetVBar()
        if not IsValid(target) then bar:SetScroll(0) return end
        local _, y = view.content:GetCanvas():GetChildPosition(target)
        bar:AnimateTo(math.max(0, y - 10), 0.25, 0, 0.5)
    end)
end

-- An entry of the navigation: its text wraps (translations are often longer than the English).
local function nav_button(parent, text, font, indent, is_active, icon)
    local button = parent:Add("DButton")
    button:Dock(TOP)
    button:DockMargin(0, 0, 0, 1)
    button:SetText("")
    local caption = button:Add("DLabel")
    caption:Dock(TOP)
    caption:DockMargin(indent + (icon and 24 or 0), 5, 8, 0)
    caption:SetFont(font)
    caption:SetText(text)
    caption:SetWrap(true)
    caption:SetAutoStretchVertical(true)
    caption:SetMouseInputEnabled(false)
    local material
    button.Think = function(self)
        local tall = caption:GetTall() + 10
        if self:GetTall() ~= tall then self:SetTall(tall) end
        caption:SetTextColor((icon or is_active()) and COLOR.text or COLOR.dim)
    end
    button.Paint = function(self, w, h)
        if is_active() then
            draw.RoundedBox(0, 0, 0, w, h, COLOR.active)
            surface.SetDrawColor(COLOR.green)
            surface.DrawRect(0, 0, 4, h)
        elseif self:IsHovered() then
            draw.RoundedBox(0, 0, 0, w, h, COLOR.hover)
        end
        if icon then
            material = material or Material(icon)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(material)
            surface.DrawTexturedRect(indent, 7, 16, 16)
        end
    end
    return button
end

-- The left side: every page, and under it the sections of its headings.
local function build_nav(view, caps)
    local nav = view.nav
    nav:Clear()
    local heading = nav:Add("DLabel")
    heading:Dock(TOP)
    heading:DockMargin(12, 10, 8, 8)
    heading:SetFont("NLGuideHeading")
    heading:SetTextColor(COLOR.green)
    heading:SetText(L("Contents"))
    heading:SetWrap(true)
    heading:SetAutoStretchVertical(true)
    for _, page in ipairs(PAGES) do
        local pageButton = nav_button(nav, L(page.title), "NLGuideNav", 10,
            function() return view.page == page and view.section == nil end, page.icon)
        pageButton.DoClick = function() open_guide(page.id) end
        for _, item in ipairs(page.items) do
            if item[1] == "h" and item.id and shown(item, caps) then
                local section = item.id
                local button = nav_button(nav, L(item[2]), "NLGuideNavSection", 44,
                    function() return view.page == page and view.section == section end)
                button.DoClick = function() open_guide(page.id, section) end
            end
        end
    end
end

local function find_page(id)
    for _, page in ipairs(PAGES) do if page.id == id then return page end end
    return PAGES[1]
end

open_guide = function(id, section)
    make_fonts()
    local caps = loader()
    local page = find_page(id)
    local view = GUIDE.view
    if not (view and IsValid(view.frame)) then
        local frame = vgui.Create("DFrame")
        frame:SetTitle(L("RTX Remix guide"))
        frame:SetSize(math.min(1240, ScrW() - 40), math.min(940, ScrH() - 40))
        frame:SetSizable(true)
        frame:SetMinWidth(math.min(760, ScrW() - 40))
        frame:SetMinHeight(math.min(480, ScrH() - 40))
        frame:Center()
        frame:MakePopup()
        local nav = frame:Add("DScrollPanel")
        nav:Dock(LEFT)
        nav:SetWide(270)
        nav:DockMargin(0, 0, 6, 0)
        nav.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, COLOR.nav) end
        local content = frame:Add("DScrollPanel")
        content:Dock(FILL)
        content.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, COLOR.page) end
        view = { frame = frame, nav = nav, content = content }
        GUIDE.view = view
    end
    view.frame:MoveToFront()
    -- The loader is read again at every opening: a reopened guide never shows stale advice.
    view.page, view.section = page, section
    build_nav(view, caps)
    build_page(view, page, caps)
    scroll_to(view, section)
end
GUIDE.open = open_guide

local function complete(command, text)
    local out = {}
    for _, page in ipairs(PAGES) do out[#out + 1] = command .. " " .. page.id end
    return out
end
concommand.Add("nativeloader_guide", function(_, _, args) open_guide(args and args[1], args and args[2]) end, complete,
    "Opens the RTX Remix guide; optionally a page: welcome, tab, remix_menu, characters, memory, troubleshooting")
concommand.Add("nativeloader_stability_guide", function() open_guide("memory") end, nil,
    "Opens the RTX Remix guide's Performance and memory page")

-- Once, on the first RTX session: open the guide a moment after the player has spawned.
hook.Add("InitPostEntity", "nativeloader_guide", function()
    if file.Exists(SHOWN, "DATA") then return end
    file.CreateDir("nativeloader_companion")
    file.Write(SHOWN, os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    timer.Simple(8, function() open_guide() end)
end)
