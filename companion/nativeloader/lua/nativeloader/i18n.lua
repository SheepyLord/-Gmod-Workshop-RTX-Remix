-- Translations of the companion's text: the RTX Remix tab, the guide and the update notice. People
-- review and edit them in companion/i18n/<language>.po of the loader's repository;
-- tools/companion_i18n.py builds those into nativeloader/i18n_data.lua when the RTX package is made.
-- The language follows Garry's Mod's (gmod_language) unless nativeloader_language names another.
-- include("nativeloader/i18n.lua") returns the module: L(text) translates now, N(text) only marks
-- text that is translated where it is shown. Documented in i18n.lua.md beside this file.
if NATIVELOADER_I18N then return NATIVELOADER_I18N end

-- The languages, each named in itself.
local LANGUAGES = {
    { "en", "English" }, { "zh-CN", "简体中文" }, { "zh-TW", "繁體中文" }, { "ja", "日本語" },
    { "ko", "한국어" }, { "fr", "Français" }, { "ru", "Русский" },
}
local LANGUAGE_ALIASES = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }

local data = {}
if file.Exists("nativeloader/i18n_data.lua", "LUA") then
    local ok, loaded = pcall(include, "nativeloader/i18n_data.lua")
    if ok and istable(loaded) then data = loaded end
end

local chosen = CreateClientConVar("nativeloader_language", "", true, false,
    "Language of the RTX Remix tab and guide: empty follows Garry's Mod; en, zh-CN, zh-TW, ja, ko, fr, ru")
local phrase_api = language

local function language()
    local code = chosen:GetString()
    if code == "" then
        local gmod = GetConVar("gmod_language")
        code = gmod and gmod:GetString() or "en"
    end
    return code
end

local function L(text)
    local phrases = data[language()]
    local translated = phrases and phrases[text]
    if translated and translated ~= "" then return translated end
    return text
end

local function N(text)
    return text
end

-- The bundled add-ons keep a separate catalog: "Clear" is an action there, weather here.
local function A(text, code)
    code = code or language()
    code = LANGUAGE_ALIASES[code] or code
    local phrases = data.addons and data.addons[code]
    return phrases and phrases[text] or text
end

local registered = {}
local function RegisterPhrase(key, text)
    registered[key] = text
    phrase_api.Add(key, A(text))
end

local function P(text)
    local key = "nativeloader.bundle." .. util.CRC(text)
    RegisterPhrase(key, text)
    return "#" .. key
end

local function PreparePanel(panel)
    if panel.NativeLoaderFullLabels then return end
    panel.NativeLoaderFullLabels = true
    for _, name in ipairs({"NumSlider", "ComboBox"}) do
        local original = panel[name]
        if original then
            panel[name] = function(self, label, ...)
                surface.SetFont("DermaDefault")
                if isstring(label) and surface.GetTextSize(label) > 100 then
                    self:Help(label)
                    return original(self, "", ...)
                end
                return original(self, label, ...)
            end
        end
    end
    local checkbox = panel.CheckBox
    if checkbox then
        panel.CheckBox = function(self, label, ...)
            local control = checkbox(self, label, ...)
            if control.Label and control.Button then
                control.Label:SetWrap(true)
                control.Label:SetAutoStretchVertical(true)
                control.PerformLayout = function(box, width)
                    local indent = box:GetIndent() or 0
                    local left = indent + box.Button:GetWide() + 8
                    box.Button:SetPos(indent, 1)
                    box.Label:SetPos(left, 0)
                    box.Label:SetWide(math.max(1, width - left - 4))
                    box.Label:SizeToContentsY()
                    box:SetTall(math.max(17, box.Label:GetTall() + 2))
                end
            end
            return control
        end
    end
end

-- The tab is built once; build it again in the new language.
local function reload()
    timer.Create("nativeloader_language", 0.2, 1, function()
        for key, text in pairs(registered) do phrase_api.Add(key, A(text)) end
        RunConsoleCommand("spawnmenu_reload")
    end)
end
cvars.AddChangeCallback("nativeloader_language", reload, "nativeloader_i18n")
cvars.AddChangeCallback("gmod_language", function()
    if chosen:GetString() == "" then reload() end
end, "nativeloader_i18n")

NATIVELOADER_I18N = { L = L, N = N, A = A, P = P, RegisterPhrase = RegisterPhrase,
    PreparePanel = PreparePanel, language = language, languages = LANGUAGES }
return NATIVELOADER_I18N
