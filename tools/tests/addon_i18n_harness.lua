CLIENT = true
local function noop() end
local values = { gmod_language = "en" }
local function cv(name) return { GetString = function() return values[name] or "en" end } end
CreateClientConVar = function(name, default) values[name] = default return cv(name) end
GetConVar = function(name) return cv(name) end
isstring = function(v) return type(v) == "string" end
istable = function(v) return type(v) == "table" end
language = { Add = noop }
cvars = { AddChangeCallback = noop }
hook = { Add = noop }
timer = { Simple = noop }
local function quote(s)
 return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
  if c == '\\' then return '\\\\' end
  if c == '"' then return '\\"' end
  return string.format('\\u%04x',string.byte(c))
 end) .. '"'
end
local function dump(part,tables)
 for lang,t in pairs(tables) do for key,value in pairs(t) do
  assert(type(value)=='string',part..':'..lang..':'..key)
  print('['..quote(part)..','..quote(lang)..','..quote(key)..','..quote(value)..']')
 end end
end
dofile('packages/advanced-bodygroup-tool/!advanced_bodygroup_tool/lua/advanced_bodygroup_tool/cl_i18n.lua')
dump('bodygroup',AdvancedBodygroupTool.I18N.locales)
dofile('packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_10_i18n.lua')
dump('destruction',BBS.I18N.locales)
dofile('packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_05_i18n.lua')
dump('material',AdvMat.I18N.locales)
dofile('packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_19_help_i18n.lua')
dofile('packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_20_help.lua')
AdvMat.HELP_I18N.en = AdvMat.HELP
dump('material_help',AdvMat.HELP_I18N)
local f=assert(io.open('packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sh_core.lua','rb'))
local text=f:read('*a');f:close()
local first=assert(text:find('MMDVMDNPC.I18N =',1,true))
local last=assert(text:find('MMDVMDNPC.LanguageAliases =',first,true))
MMDVMDNPC={}
assert(loadstring(text:sub(first,last-1)))()
dump('motion',MMDVMDNPC.I18N)

-- Exercise the actual language detection used by the three override selectors.
for _, code in ipairs({"zh-TW", "tchinese", "zh-Hant"}) do
 values.gmod_language=code
 assert(AdvancedBodygroupTool.I18N.DetectLanguage()=="zh-tw", "bodygroup Traditional Chinese")
 assert(BBS.I18N.DetectLanguage()=="zh-tw", "destruction Traditional Chinese")
 assert(AdvMat.I18N.DetectLanguage()=="zh-tw", "material Traditional Chinese")
end
values.gmod_language="ko"
assert(BBS.I18N.DetectLanguage()=="ko", "destruction Korean")
local finish=assert(text:find('function MMDVMDNPC.RegisterI18N',last,true))
assert(loadstring(text:sub(last,finish-1)))()
assert(MMDVMDNPC.NormalizeLanguage("zh-TW")=="zh-tw", "motion Traditional Chinese")

-- Generic English lookup must not silently fail because synonymous labels differ in one locale.
for code, catalog in pairs(AdvMat.I18N.locales) do
 if code ~= "en" then
  AdvMat.I18N.language=code
  for _, text in ipairs({"Colour", "Texture path", "Strength"}) do
   assert(AdvMat.LText(text)~=text, code..": untranslated material label "..text)
  end
 end
end
-- Context-bound labels continue to work across an ambiguous reverse translation such as Edit.
IsValid=function(value) return type(value)=="table" end
local panel={AdvMatI18NTextKey="common.edit", text="Edit"}
panel.GetClassName=function() return "DButton" end
panel.GetText=function(self) return self.text end
panel.SetText=function(self,value) self.text=value end
for _, code in ipairs({"zh", "fr", "ru", "zh-tw", "en"}) do
 AdvMat.I18N.language=code
 AdvMat.I18N.LocalizePanel(panel)
 assert(panel.text==AdvMat.I18N.locales[code]["common.edit"], "context label language switch")
end
