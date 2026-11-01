-- MIT. Only descendants need this heap: their original lifetime can predate their insertion order.
local H = {items = {}}
local function less(a, b) return a.ageBorn < b.ageBorn or (a.ageBorn == b.ageBorn and a.id < b.id) end
local function swap(a, b)
    local t = H.items;t[a], t[b] = t[b], t[a];t[a].expiryIndex, t[b].expiryIndex = a, b
end
local function up(i)
    while i > 1 do local p = math.floor(i / 2);if not less(H.items[i], H.items[p]) then break end;swap(i, p);i = p end
    return i
end
local function down(i)
    local t = H.items
    while i * 2 <= #t do
        local c = i * 2;if c < #t and less(t[c + 1], t[c]) then c = c + 1 end
        if not less(t[c], t[i]) then break end;swap(i, c);i = c
    end
end
function H.Remove(piece)
    local i, t = piece.expiryIndex, H.items
    if not i then return end
    swap(i, #t);t[#t], piece.expiryIndex = nil, nil
    if i <= #t then down(up(i)) end
end
function H.Add(piece)
    H.Remove(piece)
    local i = #H.items + 1;H.items[i], piece.expiryIndex = piece, i;up(i)
end
function H.PopBefore(birth)
    local p = H.items[1]
    if not p or p.ageBorn > birth then return end
    H.Remove(p);return p
end
function H.Clear()
    for _, p in ipairs(H.items) do p.expiryIndex = nil end
    H.items = {}
end
return H
