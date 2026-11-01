-- MIT. One camera snapshot per draw pass; conservative sphere/frustum and subpixel rejection.
local V = { ready = false }
function V.Capture()
    local setup = render.GetViewSetup and render.GetViewSetup()
    local origin = setup and setup.origin or (EyePos and EyePos())
    local angles = setup and setup.angles or (EyeAngles and EyeAngles())
    V.ready = isvector(origin) and isangle(angles)
    if not V.ready then return end -- retain drawing if a render context supplies no camera
    V.x, V.y, V.z = origin.x, origin.y, origin.z
    local pitch, yaw, roll = math.rad(angles.p), math.rad(angles.y), math.rad(angles.r)
    local cp, sp, cy, sy, cr, sr = math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw), math.cos(roll), math.sin(roll)
    V.fx, V.fy, V.fz = cy * cp, sy * cp, -sp
    V.rx, V.ry, V.rz = cy * sp * sr - sy * cr, sy * sp * sr + cy * cr, cp * sr
    V.ux, V.uy, V.uz = cy * sp * cr + sy * sr, sy * sp * cr - cy * sr, cp * cr
    local height = ScrH and math.max(1, ScrH()) or 1080
    local aspect = setup and setup.aspect or 0
    if aspect <= 0 then aspect = ScrW and ScrW() / height or 16 / 9 end
    local fov = math.max(1, math.min(175, setup and setup.fov or 90))
    local tangent = math.tan(math.rad(fov * .5))
    -- Source's 4:3 reference FOV and APIs supplying a literal horizontal FOV are both covered.
    V.horizontal, V.vertical = math.max(tangent, tangent * .75 * aspect), math.max(tangent * .75, tangent / aspect)
    V.hplane, V.vplane = math.sqrt(1 + V.horizontal ^ 2), math.sqrt(1 + V.vertical ^ 2)
    V.pixelScale2 = (height / (2 * V.vertical)) ^ 2
end
function V.Visible(position, radius, small)
    if not V.ready then return true end
    local x, y, z = position.x - V.x, position.y - V.y, position.z - V.z
    local distance2 = x * x + y * y + z * z
    if distance2 > (8192 + radius) ^ 2 then return false end
    local front = x * V.fx + y * V.fy + z * V.fz
    if front < -radius then return false end
    if small and distance2 > 256 ^ 2 and radius * radius * V.pixelScale2 < math.max(1, front) ^ 2 * .75 ^ 2 then return false end
    local side, up = x * V.rx + y * V.ry + z * V.rz, x * V.ux + y * V.uy + z * V.uz
    return math.abs(side) <= front * V.horizontal + radius * V.hplane and
        math.abs(up) <= front * V.vertical + radius * V.vplane
end
return V
