-- MIT. Only individual pieces enter these material groups; stable merged piles are never scanned.
local geometry = include("nlglass/debris_mesh.lua")
local R = { groups = {}, retired = {}, retireFirst = 1, retireLast = 0, released = 0 }
function R.Retire(mesh)
    R.retireLast=R.retireLast+1;R.retired[R.retireLast]=mesh
end
function R.Tick()
    R.released=0
    -- Initial construction, up to six split children, evictions and shared preview replacements
    -- retire here. Keep releases bounded even when a receiving-frame preview changes in a burst.
    for _=1,16 do
        local mesh=R.retired[R.retireFirst];if not mesh then break end
        mesh:Destroy();R.retired[R.retireFirst]=nil;R.retireFirst=R.retireFirst+1;R.released=R.released+1
    end
    if R.retireFirst>R.retireLast then R.retireFirst,R.retireLast=1,0
    elseif R.retireFirst>8192 then
        local compact={};for i=R.retireFirst,R.retireLast do compact[#compact+1]=R.retired[i]end
        R.retired,R.retireFirst,R.retireLast=compact,1,#compact
    end
end
function R.ClearRetired()
    for i=R.retireFirst,R.retireLast do R.retired[i]:Destroy() end
    R.retired,R.retireFirst,R.retireLast,R.released={},1,0,0
end
function R.Add(p)
    if p.drawGroup then return end
    local group = R.groups[p.materialName]
    if not group then
        group = { material = p.material, members = {}, count = 0, key = p.materialName }
        R.groups[p.materialName] = group
    end
    p.drawGroup, group.members[p.id], group.count = group, p, group.count + 1
end
function R.Remove(p)
    local group = p.drawGroup
    if not group then return end
    group.members[p.id], group.count, p.drawGroup = nil, group.count - 1, nil
    if group.count == 0 then R.groups[group.key] = nil end
end
function R.Draw(view)
    local calls, culled = 0, 0
    for _, group in pairs(R.groups) do
        local bound = false
        for _, p in pairs(group.members) do
            local scale = p.shrink or 1
            if view.Visible(p.position, p.geometry.radius * scale, true) then
                if not bound then render.SetMaterial(group.material);bound = true end
                geometry.Draw(p, scale);calls = calls + 1
            else culled = culled + 1 end
        end
    end
    return calls, culled
end
return R
