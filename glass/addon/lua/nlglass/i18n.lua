-- MIT. The same gettext build/escaping as the companion, in a separate MIT catalog namespace.
local data=include("nlglass/i18n_data.lua")
local I={}
local aliases={zh="zh-CN",["zh-cn"]="zh-CN",["zh-tw"]="zh-TW"}
function I.Language()
    local override=GetConVar("nativeloader_language")
    local c=override and override:GetString() or ""
    if c=="" then local gmod=GetConVar("gmod_language") c=gmod and gmod:GetString() or "en" end
    return aliases[string.lower(c)] or c
end
function I.L(text)
    local table=data[I.Language()]
    return table and table[text] or text
end
function I.Phrase(key,text) language.Add(key,I.L(text)) end
return I
