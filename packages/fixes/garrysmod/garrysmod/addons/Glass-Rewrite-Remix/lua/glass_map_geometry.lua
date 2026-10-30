-- GPL-2.0; part of Glass-Rewrite-Remix. Convex glass fragments in the source physics frame.
local G = {}
local EPSILON = 0.00001

function G.Bounds(mesh)
    local low, high = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
    for _, vertex in ipairs(mesh) do
        local p = vertex.pos or vertex
        low.x, low.y, low.z = math.min(low.x, p.x), math.min(low.y, p.y), math.min(low.z, p.z)
        high.x, high.y, high.z = math.max(high.x, p.x), math.max(high.y, p.y), math.max(high.z, p.z)
    end
    return low, high, (low + high) * 0.5
end

function G.Volume(mesh)
    local volume = 0
    for i = 1, #mesh - 2, 3 do
        local a, b, c = mesh[i].pos or mesh[i], mesh[i + 1].pos or mesh[i + 1], mesh[i + 2].pos or mesh[i + 2]
        volume = volume + a:Dot(b:Cross(c))
    end
    return volume / 6
end

function G.Copy(mesh)
    if type(mesh) ~= "table" or #mesh < 12 or #mesh > 1800 or #mesh % 3 ~= 0 then return end
    local copy = {}
    for i, vertex in ipairs(mesh) do
        local p = vertex.pos or vertex
        if not p.x or not p.y or not p.z or p.x ~= p.x or p.y ~= p.y or p.z ~= p.z then return end
        if math.abs(p.x) > 32768 or math.abs(p.y) > 32768 or math.abs(p.z) > 32768 then return end
        copy[i] = Vector(p.x, p.y, p.z)
    end
    if math.abs(G.Volume(copy)) < 0.1 then return end
    return copy
end

local function triangle(output, a, b, c)
    if (b - a):Cross(c - a):LengthSqr() <= EPSILON * EPSILON then return end
    output[#output + 1], output[#output + 2], output[#output + 3] = a, b, c
end

-- Keep the positive half-space. Cap it so VPhysics receives a closed three-dimensional shape.
function G.Clip(mesh, origin, normal)
    local output, edge = {}, {}
    local function intersection(a, b, da, db)
        local point = a + (b - a) * (da / (da - db))
        for _, old in ipairs(edge) do if (old - point):LengthSqr() < EPSILON * EPSILON then return point end end
        edge[#edge + 1] = point
        return point
    end
    for i = 1, #mesh - 2, 3 do
        local input, polygon = {mesh[i], mesh[i + 1], mesh[i + 2]}, {}
        local previous = input[3]
        local dp = (previous - origin):Dot(normal)
        for _, current in ipairs(input) do
            local dc = (current - origin):Dot(normal)
            if (dp >= 0) ~= (dc >= 0) then polygon[#polygon + 1] = intersection(previous, current, dp, dc) end
            if dc >= 0 then polygon[#polygon + 1] = current end
            previous, dp = current, dc
        end
        for j = 2, #polygon - 1 do triangle(output, polygon[1], polygon[j], polygon[j + 1]) end
    end
    if #edge >= 3 then
        local center = Vector()
        for _, point in ipairs(edge) do center = center + point end
        center = center / #edge
        local axis = math.abs(normal.z) < 0.9 and Vector(0, 0, 1) or Vector(0, 1, 0)
        local u = normal:Cross(axis):GetNormalized()
        local v = normal:Cross(u)
        table.sort(edge, function(a, b)
            a, b = a - center, b - center
            return math.atan2(a:Dot(v), a:Dot(u)) < math.atan2(b:Dot(v), b:Dot(u))
        end)
        local sign = G.Volume(mesh) >= 0 and 1 or -1
        for j = 1, #edge do
            local a, b = edge[j], edge[j % #edge + 1]
            if sign > 0 then triangle(output, center, b, a) else triangle(output, center, a, b) end
        end
    end
    if #output > 1800 or math.abs(G.Volume(output)) < 0.1 then return end
    return output
end

local function frame(mesh)
    local normal, tangent, largest = nil, nil, 0
    for i = 1, #mesh - 2, 3 do
        local direction = mesh[i + 1] - mesh[i]
        local cross = direction:Cross(mesh[i + 2] - mesh[i])
        if cross:LengthSqr() > largest then
            largest, normal, tangent = cross:LengthSqr(), cross:GetNormalized(), direction:GetNormalized()
        end
    end
    if normal then return tangent, normal:Cross(tangent) end
end

function G.Fracture(convexes, impact, desired)
    local pieces = {}
    for _, mesh in ipairs(convexes) do pieces[#pieces + 1] = mesh end
    local u, v
    if pieces[1] then u, v = frame(pieces[1]) end
    if not u then return pieces end
    desired = math.max(#pieces, math.min(24, math.max(2, desired)))
    for attempt = 1, desired * 3 do
        if #pieces >= desired then break end
        local selected, largest = 1, -1
        for i, mesh in ipairs(pieces) do
            local volume = math.abs(G.Volume(mesh))
            if volume > largest then selected, largest = i, volume end
        end
        local low, high, center = G.Bounds(pieces[selected])
        local hit = Vector(math.Clamp(impact.x, low.x, high.x), math.Clamp(impact.y, low.y, high.y), math.Clamp(impact.z, low.z, high.z))
        local origin = center * 0.8 + hit * 0.2
        local angle = attempt * 2.399963 + math.random() * 0.5
        local normal = u * math.cos(angle) + v * math.sin(angle)
        local first = G.Clip(pieces[selected], origin, normal)
        local second = G.Clip(pieces[selected], origin, -normal)
        if first and second then pieces[selected] = first pieces[#pieces + 1] = second end
    end
    return pieces
end

return G
