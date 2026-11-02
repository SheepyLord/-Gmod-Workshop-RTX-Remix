-- Exact surface semantics, independent of a shared atlas or the character's display name (ADR 0088).
local function contains(text, token) return text:find(token, 1, true) ~= nil end
local excluded = {"目白框", "目白边", "目白邊", "白目影", "眼白影", "眼角膜", "角膜", "目影", "眼影", "目HL", "目光",
    "目ハイライト", "眼罩", "眼帯", "眼線", "眼线", "まつげ", "睫毛", "眉毛"}
local englishExcluded = {"shadow", "highlight", "catchlight", "cornea", "blindfold", "eyelash", "eyeliner", "eyebrow", "outline"}
local function excludedName(text)
    for _, token in ipairs(excluded) do if contains(text, token) then return true end end
    local lower = text:lower()
    for _, token in ipairs(englishExcluded) do if contains(lower, token) then return true end end
    return false
end
local function positive(text)
    for _, token in ipairs({"白目", "白眼", "眼白", "目白"}) do
        if contains(text, token) then return true end
    end
    -- Underscores, spaces, case, material prefixes and VRM expression suffixes are common.
    local lower = text:lower():gsub("[_%-]", " "):gsub("eye%s+white", "eyewhite")
    for word in lower:gmatch("[a-z]+") do
        if word:match("^eyewhites?[lr]?$") or word == "sclera" or word == "shirome" then return true end
    end
    local compact = lower:gsub("%s", "")
    -- Corpus Ganyu's exact "eyeball" is a white mesh (UV/geometry reviewed); combined/qualified
    -- eyeball names stay unclassified. 目白底 samples the painted white lower backing, not its rim.
    return compact == "whiteeye" or compact == "eyeball"
end
local function matches(name, english)
    name, english = type(name) == "string" and name or "", type(english) == "string" and english or ""
    if excludedName(name) or excludedName(english) then return false end
    return positive(name) or positive(english)
end
return {matches = matches}
