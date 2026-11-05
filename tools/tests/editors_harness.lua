-- LuaJIT harness for test_editors.py (R19-E): the shipped editors' Lua, loaded with small
-- Garry's Mod stand-ins. One scenario per run; prints PASS <scenario> or fails an assertion.
-- Usage: luajit editors_harness.lua <scenario> <material editor> <bodygroup tool> <destruction>
-- where the last three are the add-on folders (!advanced_material_editor, ...).
local scenario, AME, ABTDIR, BBSDIR = arg[1], arg[2], arg[3], arg[4]

local function equal(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected), 2)
	end
end

local function check(condition, message)
	if not condition then error(message or "check failed", 2) end
	return condition
end

local function readFile(path)
	local handle = assert(io.open(path, "rb"))
	local text = handle:read("*a")
	handle:close()
	return text
end

local function load(path)
	local chunk = assert(loadfile(path))
	return chunk()
end

-- Garry's Mod stand-ins ------------------------------------------------------------------------

SERVER, CLIENT = true, false
NOTIFY_GENERIC, NOTIFY_ERROR, NOTIFY_HINT = 0, 1, 3
NULL = { valid = false }
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function isvector(v) return type(v) == "table" and v.isVector == true end
function isentity(v) return type(v) == "table" and v.isEntity == true end
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function tobool(v) return v ~= nil and v ~= false and v ~= 0 and v ~= "0" and v ~= "false" and v ~= "" end
function AddCSLuaFile() end
function include() end
function Angle() return {} end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0, isVector = true } end
function CreateMaterial() return {} end
function ErrorNoHalt() end
function MsgC() end
function Color() return {} end

local clock = 0
function CurTime() return clock end
function RealTime() return clock end
function SysTime() return clock end
local function advance(seconds) clock = clock + seconds end

math.Clamp = function(value, low, high) return math.min(math.max(value, low), high) end
math.NormalizeAngle = function(a) return (a + 180) % 360 - 180 end
function table.Copy(source, seen)
	if type(source) ~= "table" then error("bad argument #1 to 'pairs' (table expected, got " .. type(source) .. ")", 2) end
	seen = seen or {}
	if seen[source] then return seen[source] end
	local copy = {}
	seen[source] = copy
	for key, value in pairs(source) do
		copy[key] = type(value) == "table" and table.Copy(value, seen) or value
	end
	return copy
end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.IsEmpty(t) return next(t) == nil end
function table.Add(destination, source)
	for _, value in ipairs(source) do destination[#destination + 1] = value end
	return destination
end
function SortedPairs(t)
	local keys = {}
	for key in pairs(t) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local index = 0
	return function()
		index = index + 1
		local key = keys[index]
		if key ~= nil then return key, t[key] end
	end
end

local hooks = {}
hook = {
	Add = function(event, name, fn) hooks[event] = hooks[event] or {}; hooks[event][name] = fn end,
	Remove = function(event, name) if hooks[event] then hooks[event][name] = nil end end,
	Run = function(event, ...)
		for _, fn in pairs(hooks[event] or {}) do
			local result = fn(...)
			if result ~= nil then return result end
		end
	end,
}

local timers = {}
timer = {
	Create = function(name, delay, repetitions, fn)
		timers[name] = { delay = delay, repetitions = repetitions, fn = fn, due = clock + delay }
	end,
	Remove = function(name) timers[name] = nil end,
	Exists = function(name) return timers[name] ~= nil end,
	Simple = function(delay, fn) timers[{}] = { delay = delay, repetitions = 1, fn = fn, due = clock + delay } end,
}
-- Fires every timer that is due now, a repeating one once.
local function runTimers()
	local due = {}
	for name, entry in pairs(timers) do
		if entry.due <= clock then due[#due + 1] = { name = name, entry = entry } end
	end
	for _, item in ipairs(due) do
		if timers[item.name] == item.entry then
			if item.entry.repetitions == 1 then timers[item.name] = nil
			else item.entry.due = clock + item.entry.delay end
			item.entry.fn()
		end
	end
end

local convars = {}
local function newConVar(name, value)
	local convar = { name = name, value = tostring(value) }
	function convar:GetBool() return tobool(self.value) end
	function convar:GetInt() return math.floor(tonumber(self.value) or 0) end
	function convar:GetFloat() return tonumber(self.value) or 0 end
	function convar:GetString() return self.value end
	function convar:SetBool(on) self.value = on and "1" or "0" end
	convars[name] = convar
	return convar
end
function CreateConVar(name, default) return convars[name] or newConVar(name, default) end
CreateClientConVar = CreateConVar
function GetConVar(name) return convars[name] end

local sent, receivers, incoming, building = {}, {}, {}, nil
net = {}
for _, kind in ipairs({ "UInt", "Int", "String", "Bool", "Data", "Entity", "Float", "Vector", "Normal", "Double" }) do
	net["Write" .. kind] = function(value) building.data[#building.data + 1] = value end
	net["Read" .. kind] = function() return table.remove(incoming, 1) end
end
function net.Start(name) building = { name = name, data = {} } end
function net.Send(target) building.to = target; sent[#sent + 1] = building; building = nil end
function net.Broadcast() building.to = "all"; sent[#sent + 1] = building; building = nil end
function net.SendToServer() building.to = "server"; sent[#sent + 1] = building; building = nil end
function net.Receive(name, fn) receivers[name] = fn end
function net.BytesLeft() return 65536 end
local function receive(name, sender, ...)
	incoming = { ... }
	check(receivers[name], "no receiver for " .. tostring(name))(0, sender)
end
-- The players a sent message reached.
local function recipients(message, everybody)
	if message.to == "all" then return everybody end
	if type(message.to) == "table" and message.to.isPlayer then return { message.to } end
	return message.to
end

local counts = { json = 0, compress = 0 }
local payloadPad = 0
util = {
	AddNetworkString = function() end,
	TableToJSON = function() counts.json = counts.json + 1; return "{json " .. counts.json .. "}" end,
	Compress = function(text) counts.compress = counts.compress + 1; return text .. string.rep("z", payloadPad) end,
	Decompress = function(text) return text end,
	JSONToTable = function() return nil end,
	CRC = function(text) return tostring(#tostring(text)) end,
	SHA256 = function(text) return "sha" .. tostring(text) end,
}
file = {
	Exists = function() return false end, Read = function() return nil end, Write = function() end,
	IsDir = function() return true end, CreateDir = function() end, Delete = function() end,
	Rename = function() return true end, Find = function() return {}, {} end,
}
concommand = { Add = function() end }
game = { SinglePlayer = function() return false end }
duplicator = {
	RegisterEntityModifier = function() end, ClearEntityModifier = function() end,
	StoreEntityModifier = function() end,
}
ents = { GetAll = function() return {} end }

local everybody = {}
player = { GetAll = function() return everybody end }

local function newEntity(model, index)
	local entity = {
		valid = true, isEntity = true, model = model, index = index or 0, class = "prop_physics",
		nw = {}, bodygroups = {}, skin = 0,
		groups = { { id = 0, num = 2, name = "body", submodels = { [0] = "body", [1] = "" } },
			{ id = 1, num = 2, name = "hat", submodels = { [0] = "hat", [1] = "" } } },
	}
	function entity:IsValid() return self.valid end
	function entity:IsWorld() return false end
	function entity:IsPlayer() return self.isPlayer == true end
	function entity:GetClass() return self.class end
	function entity:GetModel() return self.model end
	function entity:EntIndex() return self.index end
	function entity:GetBodyGroups() return self.groups end
	function entity:GetBodygroup(id) return self.bodygroups[id] or 0 end
	function entity:SetBodygroup(id, value) self.bodygroups[id] = value end
	function entity:GetBodygroupCount(id)
		for _, group in ipairs(self.groups) do if group.id == id then return group.num end end
		return 0
	end
	function entity:SkinCount() return 8 end
	function entity:GetSkin() return self.skin end
	function entity:SetSkin(skin) self.skin = skin end
	function entity:GetNW2String(key, default) local v = self.nw[key] if v == nil then return default end return v end
	function entity:SetNW2String(key, value) self.nw[key] = value end
	function entity:GetNW2Int(key, default) local v = self.nw[key] if v == nil then return default end return v end
	function entity:SetNW2Int(key, value) self.nw[key] = value end
	function entity:WorldSpaceCenter() return Vector() end
	function entity:GetMaterials() return {} end
	return entity
end

local function newPlayer(name, admin, index)
	local ply = newEntity("models/player/" .. name .. ".mdl", index)
	ply.name, ply.admin, ply.isPlayer, ply.class = name, admin == true, true, "player"
	function ply:IsAdmin() return self.admin end
	function ply:IsSuperAdmin() return self.admin end
	function ply:SteamID() return "STEAM_0:0:" .. self.name end
	everybody[#everybody + 1] = ply
	return ply
end

-- Scenarios ------------------------------------------------------------------------------------

local scenarios = {}

-- ADV-01: a snapshot is encoded once per state of the store; requests coalesce, so the queue
-- holds two jobs at most; every player gets exactly one snapshot per announcement.
function scenarios.adv_snapshot()
	payloadPad = 70000  -- three 32000-byte chunks per snapshot
	AdvMat = {
		DataFolder = "advmat", DataFile = "advmat/overrides.json",
		SCOPE = { MODEL = 1, MATERIAL = 2, WORLD = 3, ENTITY = 4 },
		Log = function() end,
		TableCount = function(t) return table.Count(t or {}) end,
		IsAllowed = function() return true end,
	}
	newConVar("advmat_autosave", 1)
	local entities = {}
	function Entity(index) return entities[index] or NULL end
	load(AME .. "/lua/advmat/sh_20_net.lua")
	load(AME .. "/lua/advmat/sv_30_store.lua")
	local Store = AdvMat.Store
	local p1, p2 = newPlayer("p1", false, 1), newPlayer("p2", false, 2)
	local function request(ply) receive("AdvMat.Request", ply) end
	local function pump() check(timers["AdvMat.SyncPump"], "the sync pump is not running").fn() end

	request(p1)
	request(p2)
	equal(counts.compress, 1, "two requests for one state encode once")
	pump()                                      -- the first chunk goes out to both
	advance(6)
	request(p1)                                 -- already receiving this very snapshot
	equal(counts.compress, 1, "a request for the snapshot being sent encodes nothing")

	Store.Revision = Store.Revision + 1         -- what a broadcast does
	advance(6)
	request(p1)
	request(p2)
	equal(counts.compress, 2, "a new revision is encoded once")
	for _ = 1, 30 do                            -- both keep asking while they wait
		advance(6)
		request(p1)
		request(p2)
	end
	equal(counts.compress, 2, "waiting players asking again encode nothing")

	-- Rules that leave with their entity change the snapshot without a revision.
	local prop = newEntity("models/prop.mdl", 7)
	entities[7] = prop
	Store.EntityRules[7] = { [0] = { scope = 4, key = 7, index = 0, params = {} } }
	hooks.EntityRemoved["AdvMat.EntityRemoved"](prop)
	advance(6)
	request(p1)
	equal(counts.compress, 3, "a removed entity's rules invalidate the snapshot")

	local chunks = 0
	while timers["AdvMat.SyncPump"] do
		pump()
		chunks = chunks + 1
		check(chunks < 100, "the queue does not drain")
	end
	-- One snapshot in flight (two chunks left) and one waiting (three chunks): nothing more.
	equal(chunks, 5, "the pump sent the snapshot in flight and one waiting snapshot")

	-- The client's bookkeeping: one snapshot per announcement, never a snapshot unannounced.
	for _, ply in ipairs({ p1, p2 }) do
		local announced, completed = 0, 0
		for _, message in ipairs(sent) do
			for _, target in ipairs(recipients(message, everybody) or {}) do
				if target == ply then
					if message.name == "AdvMat.SyncBegin" then announced = announced + 1 end
					if message.name == "AdvMat.Sync" and message.data[1] == message.data[2] then
						completed = completed + 1
						check(completed <= announced, ply.name .. " got a snapshot nobody announced")
					end
				end
			end
		end
		equal(announced, 2, ply.name .. " announcements")
		equal(completed, 2, ply.name .. " snapshots")
	end
end

-- ADV-02: no HELLO resets the 2 s limit; a capable HELLO inside the window is answered once at
-- its end; profile messages are encoded once per revision.
function scenarios.adv_hello()
	AdvMat = {
		DataFolder = "advmat", MAX_SUBMATERIALS = 32,
		Log = function() end,
		TableCount = function(t) return table.Count(t or {}) end,
		IsAllowed = function() return true end,
		NormalizeMaterial = function(value) return string.lower(tostring(value or "")) end,
		Net = { WriteTable = function() end },
		RTXSchema = {
			SanitizeProfile = function(raw) return raw end,
			Compile = function(profile) return profile end,
		},
	}
	load(AME .. "/lua/advmat/sv_31_rtx_store.lua")
	local Store = AdvMat.RTXStore
	for index = 1, 3 do
		local hash = string.format("0x%016X", index)
		Store.Profiles["rtx:hash:" .. hash:sub(3)] = { target = { material = "m" .. index, hashes = { hash } } }
	end
	Store.Revision = 5
	local snapshots = 0
	local send = Store.SendSnapshot
	Store.SendSnapshot = function(ply) snapshots = snapshots + 1; return send(ply) end
	local p, q = newPlayer("p", false, 1), newPlayer("q", false, 2)
	local function hello(ply, protocol) receive("AdvMat.RTX.Hello", ply, protocol) end

	hello(p, 3)
	equal(snapshots, 1, "the first HELLO is answered")
	equal(counts.compress, 3, "each profile is encoded once")
	for _ = 1, 10 do                             -- toggling never resets the limit
		advance(0.09)
		hello(p, 0)
		advance(0.09)
		hello(p, 3)
	end
	equal(snapshots, 1, "alternating protocols inside the window send no snapshot")
	advance(0.25)                                -- past the window
	runTimers()
	equal(snapshots, 2, "the HELLO inside the window is answered once, at its end")
	runTimers()
	equal(snapshots, 2, "and only once")
	equal(counts.compress, 3, "the same revision is not encoded again")

	hello(q, 3)
	equal(snapshots, 3, "another player has a window of their own")
	equal(counts.compress, 3, "another player's snapshot reuses the encoded profiles")

	advance(0.1)
	hello(p, 2)                                  -- a mismatched protocol withdraws ...
	advance(0.1)
	hello(p, 3)                                  -- ... but does not reset the limit either
	equal(snapshots, 3, "a mismatched HELLO does not reset the limit")
	advance(2)
	runTimers()
	equal(snapshots, 4, "the deferred HELLO is answered")

	advance(0.1)
	hello(p, 3)
	advance(0.1)
	hello(p, 0)                                  -- withdrawn before the window ends
	advance(2)
	runTimers()
	equal(snapshots, 4, "a withdrawn client gets no deferred snapshot")

	Store.Revision = 6
	advance(3)
	hello(p, 3)
	equal(snapshots, 5, "a HELLO after the window is answered at once")
	equal(counts.compress, 6, "a new revision is encoded once")
end

-- ABT-01: a crafted dupe never raises an error and costs no more than a genuine one.
function scenarios.abt_dupe()
	local modifiers = {}
	duplicator = {
		RegisterEntityModifier = function(name, fn) modifiers[name] = fn end,
		ClearEntityModifier = function(entity, name) entity.EntityMods = entity.EntityMods or {}; entity.EntityMods[name] = nil end,
		StoreEntityModifier = function(entity, name, data) entity.EntityMods = entity.EntityMods or {}; entity.EntityMods[name] = data end,
	}
	ents = { GetAll = function() return {} end }
	load(ABTDIR .. "/lua/autorun/advanced_bodygroup_tool.lua")
	local ABT = AdvancedBodygroupTool
	local paste = check(modifiers[ABT.ModifierName], "the duplicator modifier is registered")

	local crafted = {
		{ hiddenBodygroups = "1,2" },
		{ hiddenRegions = 5, regionOptions = true, vertexKeepBounds = "x" },
		{ hiddenRegions = { [0] = "x", [1] = 7 }, regionOptions = 3 },
		{ hiddenBodygroups = { [0] = {}, ["x"] = true, [1.5] = true }, model = {} },
		{ vertexKeepBounds = { [0] = { cuts = "x" }, [1] = { cuts = { [1] = "x" } }, [2] = 4 } },
		{ hiddenRegions = { [0] = { [1.5] = true, [0] = true, [4096] = true, ["2"] = true } } },
	}
	for index, data in ipairs(crafted) do
		local entity = newEntity("models/crafted.mdl")
		local ok, failure = pcall(paste, nil, entity, data)
		check(ok, "crafted dupe " .. index .. " raised: " .. tostring(failure))
	end

	-- Only the parts that check out are kept.
	local entity = newEntity("models/crafted.mdl")
	paste(nil, entity, crafted[6])
	equal(entity:GetNW2String(ABT.HiddenRegionsNWKey, ""), "0:2", "the one valid region")
	entity = newEntity("models/crafted.mdl")
	paste(nil, entity, { hiddenBodygroups = { [1] = true, [7] = true }, hiddenRegions = { [1] = { [3] = true } },
		regionOptions = { [1] = 0 } })
	equal(entity:GetNW2String(ABT.HiddenNWKey, ""), "1", "hidden bodygroups")
	equal(entity:GetNW2String(ABT.HiddenRegionsNWKey, ""), "1:3", "hidden regions")

	-- A stored modifier that never went through a paste is read the same careful way.
	entity = newEntity("models/crafted.mdl")
	entity.EntityMods = { [ABT.ModifierName] = { hiddenBodygroups = "1", hiddenRegions = { [0] = "x" } } }
	local ok, failure = pcall(ABT.SetBodygroupForceHidden, entity, 0, true)
	check(ok, "a crafted stored modifier raised: " .. tostring(failure))
	equal(entity:GetNW2String(ABT.HiddenNWKey, ""), "0", "the action itself still works")

	-- Huge crafted tables stop at the entry budget.
	local regions = {}
	for group = 1, 200000 do regions[tostring(group % 2) .. string.rep("0", group % 7) .. "x" .. group] = { [1] = true } end
	for group = 0, 1 do regions[group] = {} for region = 1, 100000 do regions[group][region] = true end end
	entity = newEntity("models/crafted.mdl")
	local started = os.clock()
	paste(nil, entity, { hiddenRegions = regions })
	check(os.clock() - started < 2, "a huge crafted dupe took " .. (os.clock() - started) .. " s")
	local count = 0
	for _ in string.gmatch(ABT.GetHiddenRegionEncoding(entity), "%d+:%d+") do count = count + 1 end
	check(count <= 256, "at most 256 hidden regions, not " .. count)
end

local function loadServerTool()
	local modifiers = {}
	duplicator = {
		RegisterEntityModifier = function(name, fn) modifiers[name] = fn end,
		ClearEntityModifier = function() end, StoreEntityModifier = function() end,
	}
	ents = { GetAll = function() return {} end }
	load(ABTDIR .. "/lua/autorun/advanced_bodygroup_tool.lua")
	TOOL = {}
	load(ABTDIR .. "/lua/weapons/gmod_tool/stools/advanced_bodygroup.lua")
	return AdvancedBodygroupTool, TOOL
end

-- A player holding the bodygroup tool with `selected` chosen.
local function holdTool(ply, selected)
	local weapon = { valid = true, nw = {} }
	function weapon:GetClass() return "gmod_tool" end
	function weapon:GetMode() return "advanced_bodygroup" end
	function weapon:GetNW2Entity(_, default) return self.nw.selected or default end
	function weapon:SetNW2Entity(_, value) self.nw.selected = value end
	weapon.nw.selected = selected
	function ply:GetActiveWeapon() return weapon end
	function ply:GetTool() return { GetSelectedEntity = function() return weapon.nw.selected or NULL end } end
	function ply:GetEyeTrace() return {} end
	return weapon
end

-- ABT-03: a budget on each player's actions; ABT-04: another player only for an admin.
function scenarios.abt_actions()
	local ABT, Tool = loadServerTool()
	local p, q, admin = newPlayer("p", false, 1), newPlayer("q", false, 2), newPlayer("admin", true, 3)
	local prop = newEntity("models/prop.mdl", 10)
	local function revision(entity) return entity:GetNW2Int(ABT.RevisionNWKey, 0) end
	local function setSkin(ply, entity, skin)
		holdTool(ply, entity)
		receive("advanced_bodygroup_tool_apply", ply, entity, ABT.Action.SetSkin, skin)
	end

	-- Rate: the burst passes, the rest of a flood is dropped, the budget refills.
	for skin = 1, 100 do setSkin(p, prop, skin % 8) end
	local afterFlood = revision(prop)
	check(afterFlood >= 20 and afterFlood <= 30, "a flood is cut to the burst, not " .. afterFlood)
	advance(1)
	for skin = 1, 100 do setSkin(p, prop, skin % 8) end
	local refill = revision(prop) - afterFlood
	check(refill >= 6 and refill <= 10, "a second of refill allows about 8 actions, not " .. refill)
	advance(10)
	local replies = 0
	local before = #sent
	holdTool(p, prop)
	for _ = 1, 60 do
		receive("advanced_bodygroup_tool_set_vertex_cuts", p, prop, 0, 1, 0, "wrong identity", 0)
	end
	for index = before + 1, #sent do
		if sent[index].name == "advanced_bodygroup_tool_vertex_cuts_result" then replies = replies + 1 end
	end
	equal(replies, 60, "every vertex-cut request is answered, refused ones too")

	-- Players: yourself, or another player as an admin; never another player otherwise.
	advance(10)
	setSkin(p, q, 3)
	equal(q:GetSkin(), 0, "a player cannot change another player's model")
	setSkin(p, p, 3)
	equal(p:GetSkin(), 3, "a player can change their own model")
	setSkin(admin, q, 5)
	equal(q:GetSkin(), 5, "an admin can change another player's model")
	setSkin(p, prop, 6)
	equal(prop:GetSkin(), 6, "props stay with CanTool")
	hooks.CanTool = { deny = function() return false end }
	setSkin(p, prop, 7)
	equal(prop:GetSkin(), 6, "CanTool still decides for props")
	hooks.CanTool = nil

	-- The tool does not select another player for a non-admin, and drops one it holds.
	local function tool(owner)
		local weapon = holdTool(owner, NULL)
		return setmetatable({ GetWeapon = function() return weapon end, GetOwner = function() return owner end },
			{ __index = Tool }), weapon
	end
	local object, weapon = tool(p)
	equal(object:LeftClick({ Entity = q }), false, "a player cannot select another player")
	check(weapon.nw.selected == NULL, "nothing was selected")
	equal(object:LeftClick({ Entity = prop }), true, "a prop can be selected")
	check(weapon.nw.selected == prop, "the prop was selected")
	object, weapon = tool(admin)
	equal(object:LeftClick({ Entity = q }), true, "an admin can select another player")
	admin.admin = false
	object:Think()
	check(weapon.nw.selected == NULL, "a selection the owner may no longer edit is dropped")
end

-- ABT-02: the client's region analyses are a bounded least-recently-used cache.
function scenarios.abt_cache()
	SERVER, CLIENT = false, true
	AdvancedBodygroupTool = {}
	load(ABTDIR .. "/lua/advanced_bodygroup_tool/cl_uv_hide.lua")
	local ABT = AdvancedBodygroupTool
	local model = "models/cache.mdl"
	ABT.ModelLayoutCache[model] = { version = 49, count = 1,
		groups = { [0] = { count = 2, options = { [0] = 1, [1] = 1 } } } }
	local builds, triangles = 0, 4
	util.GetModelMeshes = function()
		builds = builds + 1
		local vertices = {}
		for index = 1, triangles do
			local x = index * 10
			vertices[#vertices + 1] = { pos = Vector(x, 0, 0), u = 0, v = 0 }
			vertices[#vertices + 1] = { pos = Vector(x + 1, 0, 0), u = 1, v = 0 }
			vertices[#vertices + 1] = { pos = Vector(x, 1, 0), u = 0, v = 1 }
		end
		return { { material = "models/cache/skin", triangles = vertices } }
	end
	local entity = newEntity(model)
	entity.groups = { { id = 0, num = 2, name = "body", submodels = { [0] = "body", [1] = "" } } }
	local function analyse(skin)
		entity.skin = skin
		local regions = ABT.GetBodygroupRegions(entity, 0)
		check(regions and #regions == triangles, "skin " .. skin .. " has its regions")
	end
	local function cached(skin) return ABT.RegionAnalysisCache[model .. "|0|" .. skin] ~= nil end

	ABT.MaxRegionAnalyses = 3
	for skin = 0, 9 do
		analyse(skin)
		check(table.Count(ABT.RegionAnalysisCache) <= 3, "the cache holds 3 analyses at most")
	end
	check(cached(7) and cached(8) and cached(9) and not cached(6), "the newest three are kept")
	local before = builds
	analyse(7)                                   -- used again: a hit, and now the newest
	equal(builds, before, "a cached variant is not analysed again")
	analyse(10)
	check(cached(7) and not cached(8), "the least recently used analysis goes first")

	ABT.MaxRegionAnalysisTriangles = 10          -- room for two analyses of four triangles
	analyse(11)
	equal(table.Count(ABT.RegionAnalysisCache), 2, "the triangle budget holds")
	triangles = 20                               -- one analysis over the whole budget
	analyse(12)
	equal(table.Count(ABT.RegionAnalysisCache), 1, "only the analysis in use is kept")
	check(cached(12), "the analysis in use is never evicted")
end

-- BBS-02: refused settings packets are logged once per player every few seconds.
function scenarios.bbs_denied()
	local lines = {}
	BBS = {
		NET_HIT = "BBS.Hit", NET_SET_ENABLED = "BBS.SetEnabled", NET_SET_DEATH_ONLY = "BBS.SetDeathOnly",
		NET_SET_LIVING_PLAYERS = "BBS.SetLivingPlayers", NET_SET_LIVING_NPCS = "BBS.SetLivingNPCs",
		NET_TRANSFER_DEATH_DAMAGE = "BBS.TransferDeathDamage",
		Log = function(format, ...) lines[#lines + 1] = string.format(format, ...) end,
	}
	newConVar("bbs_enabled", 1)
	newConVar("bbs_damage_living_npcs", 1)
	load(BBSDIR .. "/sv_20_hits.lua")
	local p, admin = newPlayer("p", false, 1), newPlayer("admin", true, 2)

	for _ = 1, 100 do receive(BBS.NET_SET_ENABLED, p, false) end
	equal(#lines, 1, "a flood of refused packets logs one line")
	check(lines[1]:find("without admin access", 1, true), lines[1])
	advance(5)
	for _ = 1, 10 do receive(BBS.NET_SET_LIVING_NPCS, p, false) end
	equal(#lines, 1, "the next lines wait for the interval")
	advance(5.5)
	receive(BBS.NET_SET_ENABLED, p, false)
	equal(#lines, 2, "after the interval one more line")
	check(lines[2]:find("(109 other refused requests since the last line)", 1, true), lines[2])
	equal(GetConVar("bbs_enabled"):GetBool(), true, "nothing changed")

	receive(BBS.NET_SET_ENABLED, admin, false)
	equal(GetConVar("bbs_enabled"):GetBool(), false, "an admin still changes the setting")
	check(lines[#lines]:find("set bbs_enabled to false", 1, true), lines[#lines])
end

-- BBS-01 (and the material editor's same helper): a setting of 0 reads as off; the fallback
-- is only for a setting that does not exist.
function scenarios.getbool()
	local function extract(path, header)
		local text = readFile(path)
		local first = text:find(header, 1, true)
		check(first, header .. " not found in " .. path)
		local last = check(text:find("\nend[\r\n]", first), "the end of " .. header)
		local name = header:match("function ([%w_]+)")
		return assert(loadstring(text:sub(first, last + 4) .. "\nreturn " .. name, "=" .. path))()
	end
	local helpers = {
		extract(BBSDIR .. "/cl_22_shape.lua", "local function GetBool("),
		extract(BBSDIR .. "/cl_25_profiler.lua", "local function GetBool("),
		extract(BBSDIR .. "/cl_32_mesh_persistence.lua", "local function GetBool("),
		extract(BBSDIR .. "/cl_40_damage.lua", "local function GetBool("),
		extract(AME .. "/lua/advmat/cl_71_rtx_source.lua", "local function ConVarBool("),
	}
	newConVar("setting_off", 0)
	newConVar("setting_on", 1)
	for index, helper in ipairs(helpers) do
		equal(helper("setting_off", true), false, "helper " .. index .. ": a setting of 0 with fallback true")
		equal(helper("setting_on", false), true, "helper " .. index .. ": a setting of 1 with fallback false")
		equal(helper("setting_missing", true), true, "helper " .. index .. ": a missing setting takes the fallback")
		equal(helper("setting_missing", false), false, "helper " .. index .. ": a missing setting, fallback false")
	end
end

local run = scenarios[scenario]
check(run, "unknown scenario " .. tostring(scenario))
run()
print("PASS " .. scenario)
