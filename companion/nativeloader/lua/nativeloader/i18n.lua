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

local data = {}
if file.Exists("nativeloader/i18n_data.lua", "LUA") then
    local ok, loaded = pcall(include, "nativeloader/i18n_data.lua")
    if ok and istable(loaded) then data = loaded end
end

local chosen = CreateClientConVar("nativeloader_language", "", true, false,
    "Language of the RTX Remix tab and guide: empty follows Garry's Mod; en, zh-CN, zh-TW, ja, ko, fr, ru")

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

-- The tab is built once; build it again in the new language.
local function reload()
    timer.Create("nativeloader_language", 0.2, 1, function() RunConsoleCommand("spawnmenu_reload") end)
end
cvars.AddChangeCallback("nativeloader_language", reload, "nativeloader_i18n")

NATIVELOADER_I18N = { L = L, N = N, language = language, languages = LANGUAGES }
return NATIVELOADER_I18N
