-- MIT. Local piece geometry and immutable settled meshes. No entity is needed for drawing.
local M = {}
local function vertex(pos, normal, u, v, color)
    return {pos = pos, normal = normal, u = u, v = v, color = color}
end
function M.Geometry(poly, thickness, color)
    if type(poly) ~= "table" or #poly < 3 or #poly > 64 or not isnumber(thickness) or
        thickness ~= thickness or thickness < .01 or thickness > 64 then return nil end
    local cx, cy, area = 0, 0, 0
    for i, p in ipairs(poly) do
        if type(p) ~= "table" or not isnumber(p.x or p[1]) or not isnumber(p.y or p[2]) then return nil end
        local x, y = p.x or p[1], p.y or p[2]
        if x ~= x or y ~= y or math.abs(x) > 8192 or math.abs(y) > 8192 then return nil end
        local nextp = poly[i % #poly + 1]
        if type(nextp) ~= "table" then return nil end
        local nx, ny = nextp.x or nextp[1], nextp.y or nextp[2]
        if not isnumber(nx) or not isnumber(ny) then return nil end
        local cross = x * ny - nx * y
        area, cx, cy = area + cross, cx + (x + nx) * cross, cy + (y + ny) * cross
    end
    if area < .0001 then return nil end -- counter-clockwise, nondegenerate
    cx, cy = cx / (3 * area), cy / (3 * area)
    local points, hull, vertices = {}, {}, {}
    local half = thickness / 2
    for _, p in ipairs(poly) do
        local x, y = (p.x or p[1]) - cx, (p.y or p[2]) - cy
        if math.abs(x) > 1024 or math.abs(y) > 1024 then return nil end
        points[#points + 1] = Vector(x, y, 0)
        hull[#hull + 1], hull[#hull + 2] = Vector(x, y, -half), Vector(x, y, half)
    end
    for i, p in ipairs(points) do
        local b = points[i % #points + 1]
        if (b - p):LengthSqr() < .000001 then return nil end
        for _, q in ipairs(points) do if (b - p):Cross(q - p).z < -.0001 then return nil end end
    end
    local function add(p, z, normal)
        vertices[#vertices + 1] = vertex(Vector(p.x, p.y, z), normal, (p.x + cx) / 32, (p.y + cy) / 32, color)
    end
    for i = 2, #points - 1 do
        for _, p in ipairs({points[1], points[i], points[i + 1]}) do add(p, half, Vector(0, 0, 1)) end
        for _, p in ipairs({points[1], points[i + 1], points[i]}) do add(p, -half, Vector(0, 0, -1)) end
    end
    for i, p in ipairs(points) do
        local b = points[i % #points + 1]
        local normal = Vector(b.y - p.y, p.x - b.x, 0):GetNormalized()
        add(p, -half, normal); add(b, -half, normal); add(b, half, normal)
        add(p, -half, normal); add(b, half, normal); add(p, half, normal)
    end
    return {vertices = vertices, hull = hull, center = Vector(cx, cy, 0), mass = area / 2 * thickness * .0254 ^ 3 * 2500}
end
function M.Build(vertices, material)
    local mesh = Mesh(material)
    local ok, reason = pcall(mesh.BuildFromTriangles, mesh, vertices)
    if not ok then mesh:Destroy(); error(reason, 0) end
    return mesh
end
function M.Transformed(piece, out)
    for _, v in ipairs(piece.geometry.vertices) do
        local p = LocalToWorld(v.pos, angle_zero, piece.position, piece.angles)
        local normal = LocalToWorld(v.normal, angle_zero, vector_origin, piece.angles)
        out[#out + 1] = vertex(p, normal, v.u, v.v, piece.color)
    end
end
function M.Draw(piece, scale)
    piece.matrix:SetTranslation(piece.position)
    piece.matrix:SetAngles(piece.angles)
    piece.scale:SetUnpacked(scale, scale, scale)
    piece.matrix:SetScale(piece.scale)
    cam.PushModelMatrix(piece.matrix)
    piece.mesh:Draw()
    cam.PopModelMatrix()
end
return M
