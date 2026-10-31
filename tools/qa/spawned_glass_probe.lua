-- QA probe: spawn the procedural glass add-on's own pane (procedural_shard_4) and shoot it with the 357.
-- Needs sv_cheats 1 (setang only). Prints NL_GLASS lines; NL_SHOT paces screenshots.
local function out(...) print("NL_GLASS " .. table.concat({...}, " ")) end
local function shards() return ents.FindByClass("procedural_shard") end
local me = LocalPlayer()
local target
local steps = {
    function()
        RunConsoleCommand("setang", "10", tostring(me:EyeAngles().y), "0")
        timer.Simple(0.5, function()
            RunConsoleCommand("gm_spawnsent", "procedural_shard_4")
            timer.Simple(2, function()
                local list = shards()
                target = list[#list]
                out("spawned", #list, IsValid(target) and tostring(target:GetPos()) or "none")
                if IsValid(target) then
                    local ang = (target:WorldSpaceCenter() - me:EyePos()):Angle()
                    RunConsoleCommand("setang", tostring(ang.p), tostring(ang.y), "0")
                end
                RunConsoleCommand("use", "weapon_357")
                timer.Simple(1.5, function() print("NL_SHOT before_shot") end)
            end)
        end)
    end,
    function()
        RunConsoleCommand("+attack")
        timer.Simple(0.15, function()
            RunConsoleCommand("-attack")
            timer.Simple(3, function() out("after_shot", "shards", #shards()) print("NL_SHOT after_shot") end)
        end)
    end,
    function() out("done") print("NL_SHOT_DONE") end,
}
local index = 0
local function nextStep() index = index + 1 if steps[index] then steps[index]() end end
concommand.Add("nl_shot_taken", function() timer.Simple(0.5, nextStep) end)
timer.Simple(1, nextStep)
