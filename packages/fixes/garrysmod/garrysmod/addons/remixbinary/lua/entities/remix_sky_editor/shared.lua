-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = NP("Sky Editor")
ENT.Author = "RTX Remixed"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.Category = "RTX Remix"
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
