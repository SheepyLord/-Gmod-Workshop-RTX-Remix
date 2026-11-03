-- The in-game RTX Remix guide (nativeloader_guide): how to find, understand and use every setting of
-- the RTX package and Remix, with labeled pictures. A window with the pages and their sections on the
-- left and the page on the right. It opens once by itself on the first RTX session, then from the
-- console (nativeloader_guide [page] [section]) or the RTX Remix tab's Start here;
-- nativeloader_stability_guide opens the Performance and memory page. The pages are in
-- nativeloader/guide_pages.lua; pictures are in materials/nativeloader/guide/ (a missing one is left
-- out with its legend). The text is translated (nativeloader/i18n.lua). The guide grows with the
-- screen's height past 1080 lines, and with a larger DermaDefault (nativeloader_guide_scale overrides
-- it). Documented in nativeloader_guide.lua.md beside this file.
local SHOWN = "nativeloader_companion/guide_shown.txt"
local i18n = include("nativeloader/i18n.lua")
local L = i18n.L
local PAGES = include("nativeloader/guide_pages.lua").pages
local SCALE_SETTING = CreateClientConVar("nativeloader_guide_scale", "0", true, false,
    "RTX Remix guide size: 0 follows the screen's height and the game's interface text; 1 to 4 sets it")

NATIVELOADER_GUIDE = NATIVELOADER_GUIDE or {}
local GUIDE = NATIVELOADER_GUIDE
GUIDE.pages = PAGES

local COLOR = {
    text = Color(228, 230, 234), dim = Color(160, 166, 174), green = Color(118, 185, 0),
    page = Color(33, 35, 40), nav = Color(25, 27, 31), hover = Color(44, 48, 55), active = Color(52, 72, 26),
    tip = Color(31, 46, 22), warn = Color(62, 46, 17), amber = Color(232, 168, 40), code = Color(16, 17, 20),
    frame = Color(74, 79, 88), badge = Color(12, 12, 12),
}

-- Every size below is for a game that draws its interface text at the usual size; px() scales it.
-- Pictures grow only by whole steps (PICTURE), drawn pixel for pixel, so they stay sharp.
local SCALE, PICTURE = 1, 1
local function px(n) return math.floor(n * SCALE + 0.5) end

-- How large DermaDefault is against the same Tahoma 13 it is in a plain game: an add-on that enlarges
-- the game's interface text everywhere makes it larger (1 when it cannot be measured).
local function derma_ratio()
    if type(draw) ~= "table" or type(draw.GetFontHeight) ~= "function" then return 1 end
    surface.CreateFont("NLGuideProbe", { font = "Tahoma", size = 13, weight = 500, extended = true })
    local ok, derma, probe = pcall(function() return draw.GetFontHeight("DermaDefault"), draw.GetFontHeight("NLGuideProbe") end)
    if not ok or type(derma) ~= "number" or type(probe) ~= "number" or probe <= 0 then return 1 end
    return derma / probe
end

-- The guide's sizes are for a 1080-line screen: a taller one draws them larger, as GUI scalers do for
-- the spawn menu (R14's field check: 2160 lines, a spawn menu twice as large and a guide left at half
-- its size), and so does a larger DermaDefault. Never smaller than 1, at most 4.
local function measure_scale()
    local forced = tonumber(SCALE_SETTING:GetString())
    if forced and forced > 0 then return math.min(4, math.max(1, forced)) end
    local scale = math.max(ScrH() / 1080, derma_ratio())
    return scale < 1.15 and 1 or math.min(4, scale)
end

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

local fonts_scale
local function make_fonts()
    if fonts_scale == SCALE then return end
    fonts_scale = SCALE
    -- Tahoma, as DermaDefault: Windows supplies the glyphs of the other languages.
    local function font(name, size, weight)
        surface.CreateFont(name, { font = "Tahoma", size = px(size), weight = weight, antialias = true, extended = true })
    end
    font("NLGuideTitle", 27, 800)
    font("NLGuideHeading", 20, 800)
    font("NLGuideBody", 15, 500)
    font("NLGuideBold", 15, 800)
    font("NLGuideNav", 15, 800)
    font("NLGuideNavSection", 14, 500)
    font("NLGuideBadge", 14, 900)
    surface.CreateFont("NLGuideCode", { font = "Lucida Console", size = px(14), weight = 500, antialias = true })
end

-- The text the open page shows, in order (for tests and the in-game check).
local function record(text)
    if GUIDE.shown then GUIDE.shown.texts[#GUIDE.shown.texts + 1] = text end
end

local function label(parent, text, font, color, left, top)
    local item = parent:Add("DLabel")
    item:Dock(TOP)
    item:DockMargin(px(left or 18), px(top or 3), px(18), px(3))
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
    holder:DockMargin(px(18), px(3), px(18), px(3))
    holder:SetPaintBackground(false)
    local body = holder:Add("DLabel")
    body:Dock(TOP)
    body:DockMargin(px(indent or 32), px(2), 0, 0)
    body:SetFont("NLGuideBody")
    body:SetTextColor(COLOR.text)
    body:SetText(text)
    body:SetWrap(true)
    body:SetAutoStretchVertical(true)
    record(text)
    holder.Paint = function(_, w, h) paint_marker(w, h) end
    holder.Think = function(self)
        local tall = math.max(px(24), body:GetTall() + px(4))
        if self:GetTall() ~= tall then self:SetTall(tall) end
    end
    return holder
end

local function badge(x, y, number)
    draw.RoundedBox(px(11), x, y, px(22), px(22), COLOR.green)
    draw.SimpleText(tostring(number), "NLGuideBadge", x + px(11), y + px(11), COLOR.badge, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
            draw.SimpleText(number .. ".", "NLGuideBold", px(4), px(4), COLOR.green)
        end)
    end
end

local function add_list(parent, item, caps)
    for _, text in ipairs(entries(item, caps)) do
        row(parent, L(text), function()
            surface.SetDrawColor(COLOR.green)
            surface.DrawRect(px(8), px(10), px(6), px(6))
        end, 26)
    end
end

-- A box with a colored bar: a tip or a caution.
local function add_box(parent, text, background, bar)
    local holder = parent:Add("DPanel")
    holder:Dock(TOP)
    holder:DockMargin(px(18), px(8), px(18), px(8))
    local body = holder:Add("DLabel")
    body:Dock(TOP)
    body:DockMargin(px(16), px(8), px(12), 0)
    body:SetFont("NLGuideBody")
    body:SetTextColor(COLOR.text)
    body:SetText(text)
    body:SetWrap(true)
    body:SetAutoStretchVertical(true)
    record(text)
    holder.Paint = function(_, w, h)
        draw.RoundedBox(px(4), 0, 0, w, h, background)
        surface.SetDrawColor(bar)
        surface.DrawRect(0, 0, px(5), h)
    end
    holder.Think = function(self)
        local tall = body:GetTall() + px(16)
        if self:GetTall() ~= tall then self:SetTall(tall) end
    end
end

local function add_code(parent, text)
    local item = label(parent, text, "NLGuideCode", COLOR.text, 30, 6)
    item:SetTextInset(px(10), 0)
    item.Paint = function(_, w, h) draw.RoundedBox(px(4), 0, 0, w, h, COLOR.code) end
end

-- A picture at its own size times PICTURE (made from sharp captures; drawn pixel for pixel, only made
-- smaller, and then smoothed, to fit), and its legend: entry n explains the badge numbered n.
local function add_image(parent, item)
    local path = item[2]
    if not file.Exists("materials/" .. path, "GAME") then return end
    local material = Material(path, "smooth")
    if material:IsError() then return end
    local width, height = material:Width(), material:Height()
    if width <= 0 or height <= 0 then return end
    local sharp = PICTURE > 1 and Material(path) or material  -- point sampled: whole steps stay crisp
    local holder = parent:Add("DPanel")
    holder:Dock(TOP)
    holder:DockMargin(px(18), px(10), px(18), px(6))
    holder:SetTall(height * PICTURE + 2)
    holder.Paint = function(_, w)
        local scale = math.min(PICTURE, (w - 2) / width)
        local dw, dh = math.floor(width * scale), math.floor(height * scale)
        surface.SetDrawColor(COLOR.frame)
        surface.DrawOutlinedRect(0, 0, dw + 2, dh + 2)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(scale == PICTURE and sharp or material)
        surface.DrawTexturedRect(1, 1, dw, dh)
    end
    holder.PerformLayout = function(self, w)
        local tall = math.floor(height * math.min(PICTURE, (w - 2) / width)) + 2
        if self:GetTall() ~= tall then self:SetTall(tall) end
    end
    GUIDE.shown.images[#GUIDE.shown.images + 1] = path
    for number = 3, #item do
        row(parent, L(item[number]), function() badge(0, px(1), number - 2) end)
    end
end

local function add_term(parent, word, meaning)
    local title = label(parent, L(word), "NLGuideBold", COLOR.green, 18, 8)
    title:DockMargin(px(18), px(8), px(18), 0)
    label(parent, L(meaning), "NLGuideBody", COLOR.text, 32, 1)
end

local function add_button(parent, text, action)
    local button = parent:Add("DButton")
    button:Dock(TOP)
    button:DockMargin(px(18), px(6), px(18), px(6))
    button:SetTall(px(30))
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
    title:DockMargin(px(18), px(14), px(18), px(6))
    for _, item in ipairs(page.items) do
        if shown(item, caps) then
            local kind = item[1]
            if kind == "h" then
                local heading = label(content, L(item[2]), "NLGuideHeading", COLOR.green, 18, 18)
                heading:DockMargin(px(18), px(20), px(18), px(4))
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
    bar:DockMargin(px(18), px(24), px(18), px(18))
    bar:SetTall(px(32))
    bar:SetPaintBackground(false)
    if PAGES[index - 1] then
        local previous = bar:Add("DButton")
        previous:Dock(LEFT)
        previous:SetWide(px(300))
        previous:SetFont("NLGuideBody")
        previous:SetText(string.format(L("Previous: %s"), L(PAGES[index - 1].title)))
        previous.DoClick = function() open_guide(PAGES[index - 1].id) end
    end
    if PAGES[index + 1] then
        local following = bar:Add("DButton")
        following:Dock(RIGHT)
        following:SetWide(px(300))
        following:SetFont("NLGuideBody")
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
        bar:AnimateTo(math.max(0, y - px(10)), 0.25, 0, 0.5)
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
    caption:DockMargin(px(indent + (icon and 24 or 0)), px(5), px(8), 0)
    caption:SetFont(font)
    caption:SetText(text)
    caption:SetWrap(true)
    caption:SetAutoStretchVertical(true)
    caption:SetMouseInputEnabled(false)
    local material
    button.Think = function(self)
        local tall = caption:GetTall() + px(10)
        if self:GetTall() ~= tall then self:SetTall(tall) end
        caption:SetTextColor((icon or is_active()) and COLOR.text or COLOR.dim)
    end
    button.Paint = function(self, w, h)
        if is_active() then
            draw.RoundedBox(0, 0, 0, w, h, COLOR.active)
            surface.SetDrawColor(COLOR.green)
            surface.DrawRect(0, 0, px(4), h)
        elseif self:IsHovered() then
            draw.RoundedBox(0, 0, 0, w, h, COLOR.hover)
        end
        if icon then
            material = material or Material(icon)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(material)
            surface.DrawTexturedRect(px(indent), px(7), px(16), px(16))
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
    heading:DockMargin(px(12), px(10), px(8), px(8))
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
    -- The size is measured again at every opening: a changed GUI scale or setting rebuilds the window.
    SCALE = measure_scale()
    PICTURE = math.max(1, math.floor(SCALE + 0.25))
    GUIDE.scale, GUIDE.picture_scale = SCALE, PICTURE
    make_fonts()
    local caps = loader()
    local page = find_page(id)
    local view = GUIDE.view
    if view and IsValid(view.frame) and view.scale ~= SCALE then
        view.frame:Remove()
        view = nil
    end
    if not (view and IsValid(view.frame)) then
        local frame = vgui.Create("DFrame")
        frame:SetTitle(L("RTX Remix guide"))
        frame:SetSize(math.min(px(1240), ScrW() - 40), math.min(px(940), ScrH() - 40))
        frame:SetSizable(true)
        frame:SetMinWidth(math.min(px(760), ScrW() - 40))
        frame:SetMinHeight(math.min(px(480), ScrH() - 40))
        frame:Center()
        frame:MakePopup()
        local nav = frame:Add("DScrollPanel")
        nav:Dock(LEFT)
        nav:SetWide(px(270))
        nav:DockMargin(0, 0, px(6), 0)
        nav.Paint = function(_, w, h) draw.RoundedBox(px(4), 0, 0, w, h, COLOR.nav) end
        local content = frame:Add("DScrollPanel")
        content:Dock(FILL)
        content.Paint = function(_, w, h) draw.RoundedBox(px(4), 0, 0, w, h, COLOR.page) end
        view = { frame = frame, nav = nav, content = content, scale = SCALE }
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
