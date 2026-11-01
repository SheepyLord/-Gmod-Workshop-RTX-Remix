-- MIT. Only individual pieces enter these material groups; stable merged piles are never scanned.
local geometry = include("nlglass/debris_mesh.lua")
local R = { groups = {} }
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
