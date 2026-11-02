-- The hotloader emits single-frame RGBA8888 VTF 7.2 atlases. Give only the selected material a
-- distinct image hash by toggling one RGB low bit in the top mip; alpha and every other mip stay exact.
-- Prefer a transparent corner pixel. This is an identity tag, never an emissive UV mask.
local function uint(bytes, start, count)
    local out = 0
    for i = count - 1, 0, -1 do out = out * 256 + bytes:byte(start + i) end
    return out
end
local MAX = 128 * 1024 * 1024 -- a 4096-square RGBA atlas with mips is ~85 MiB
local function proxy(bytes)
    if type(bytes) ~= "string" or #bytes < 84 or #bytes > MAX then return nil, "size" end
    if bytes:sub(1, 4) ~= "VTF\0" or uint(bytes, 5, 4) ~= 7 or uint(bytes, 9, 4) ~= 2 or
        uint(bytes, 13, 4) ~= 80 or uint(bytes, 25, 2) ~= 1 or uint(bytes, 64, 2) ~= 1 or
        uint(bytes, 53, 4) ~= 0 or uint(bytes, 58, 4) ~= 4294967295 or
        bytes:byte(62) ~= 0 or bytes:byte(63) ~= 0 then return nil, "unsupported VTF layout" end
    local width, height, mips = uint(bytes, 17, 2), uint(bytes, 19, 2), bytes:byte(57)
    if width == 0 or height == 0 or width > 8192 or height > 8192 or mips == 0 or mips > 14 or
        math.floor(uint(bytes, 21, 4) / 16384) % 2 ~= 0 then return nil, "dimensions/frames" end
    local size, w, h = 80, width, height
    for _ = 1, mips do size, w, h = size + w * h * 4, math.max(1, math.floor(w / 2)), math.max(1, math.floor(h / 2)) end
    if size ~= #bytes then return nil, "truncated/extra image data" end
    local start = #bytes - width * height * 4 + 1
    local pixel = start
    for p = start, math.min(start + 4092, #bytes - 3), 4 do
        if bytes:byte(p + 3) == 0 then pixel = p break end
    end
    local value = bytes:byte(pixel)
    value = value % 2 == 0 and value + 1 or value - 1
    return bytes:sub(1, pixel - 1) .. string.char(value) .. bytes:sub(pixel + 1), pixel
end
return {proxy = proxy, maxBytes = MAX}
