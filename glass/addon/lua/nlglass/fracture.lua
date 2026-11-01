-- MIT. Pure Lua 5.1: no engine globals, random(), trigonometry or platform-dependent hash order.
local F = {MAX_IMPACTS = 8, MAX_CELLS = 512, GRID = 1024}
local abs, floor, min, max = math.abs, math.floor, math.min, math.max
local function clamp(x, a, b) return max(a, min(b, x)) end
local function snap(x) return floor(x * F.GRID + 0.5) / F.GRID end
F.Snap = snap

-- All products are exact integers below 2^53, including in a LuaJIT without the bit library.
function F.Generator(seed)
    seed = floor(abs(seed or 1)) % 2147483646 + 1
    return function(limit)
        seed = (seed * 16807) % 2147483647
        return limit and seed % limit or seed / 2147483647
    end
end

function F.Root(n)
    -- Integer square root: even velocities and ring selection avoid libm rounding differences.
    n = max(0, floor(n))
    local a, b = 0, min(n, 2147483647) + 1
    while b - a > 1 do
        local c = floor((a + b) / 2)
        if c * c <= n then a = c else b = c end
    end
    return a
end

function F.Area(poly)
    local a = 0
    for i, p in ipairs(poly) do
        local q = poly[i % #poly + 1]
        a = a + p[1] * q[2] - p[2] * q[1]
    end
    return a * 0.5
end

function F.Hull(points)
    local p = {}
    for _, v in ipairs(points) do p[#p + 1] = {snap(v[1]), snap(v[2])} end
    table.sort(p, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
    local function cross(a, b, c) return (b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1]) end
    local hull = {}
    for _, v in ipairs(p) do
        while #hull >= 2 and cross(hull[#hull-1], hull[#hull], v) <= 0 do table.remove(hull) end
        hull[#hull + 1] = v
    end
    local lower = #hull
    for i = #p - 1, 1, -1 do
        while #hull > lower and cross(hull[#hull-1], hull[#hull], p[i]) <= 0 do table.remove(hull) end
        hull[#hull + 1] = p[i]
    end
    table.remove(hull)
    return hull
end

-- Sutherland-Hodgman against a CCW convex tile. Snap every intersection to the wire grid.
function F.Clip(poly, tile)
    local out = poly
    for j, a in ipairs(tile) do
        local b = tile[j % #tile + 1]
        local input = out
        out = {}
        if #input < 3 then return nil end
        local function distance(p) return (b[1]-a[1])*(p[2]-a[2])-(b[2]-a[2])*(p[1]-a[1]) end
        local prev, dp = input[#input], distance(input[#input])
        for _, cur in ipairs(input) do
            local dc = distance(cur)
            if (dp >= 0) ~= (dc >= 0) then
                local t = dp / (dp - dc)
                out[#out + 1] = {snap(prev[1] + (cur[1]-prev[1])*t), snap(prev[2] + (cur[2]-prev[2])*t)}
            end
            if dc >= 0 then out[#out + 1] = cur end
            prev, dp = cur, dc
        end
    end
    -- Remove duplicate/collinear points before giving a convex to either physics engine.
    out = F.Hull(out)
    if #out >= 3 and F.Area(out) >= 0.02 then return out end
end

function F.Center(poly)
    local x, y = 0, 0
    for _, p in ipairs(poly) do x, y = x + p[1], y + p[2] end
    return {snap(x / #poly), snap(y / #poly)}
end

function F.Threshold(def)
    local areaScale = max(0.35, F.Root(abs(F.Area(def.outline)) * 10000 / 6144) / 100)
    local kindScale = def.kind == "tempered" and 3.5 or 1
    return clamp(floor(450000 * areaScale * def.thickness * def.thickness * def.strength * kindScale + 0.5),1,2000000000)
end

-- Integer circle, linearly interpolated. Rays jitter in angle, but their ordering cannot cross.
local circle = {{1024,0},{946,392},{724,724},{392,946},{0,1024},{-392,946},{-724,724},{-946,392},
    {-1024,0},{-946,-392},{-724,-724},{-392,-946},{0,-1024},{392,-946},{724,-724},{946,-392}}
local function direction(t)
    t = t % 16384
    local i, f = floor(t / 1024), t % 1024
    local a, b = circle[i+1], circle[(i+1)%16+1]
    return {(a[1]*(1024-f)+b[1]*f)/1024, (a[2]*(1024-f)+b[2]*f)/1024}
end

local function rings(def, hit)
    local r, limit = {0}, 1
    for _, p in ipairs(def.outline) do limit = max(limit, abs(p[1]-hit.x)+abs(p[2]-hit.y)) end
    local radius = def.piece_size * 0.55
    while r[#r] < limit * 2 + def.piece_size do
        r[#r+1] = snap(radius)
        radius = radius * 1.55 + def.piece_size * 0.3
    end
    return r
end

local function tiles(def, hit)
    local out, dirs, random = {}, {}, F.Generator(hit.seed)
    local offset = random(16384)
    for i = 1, hit.rays do dirs[i] = direction(offset + floor((i-1)*16384/hit.rays) + random(400)-200) end
    local radii = rings(def, hit)
    local function point(d, r) return {snap(hit.x+d[1]*r/1024), snap(hit.y+d[2]*r/1024)} end
    for ring = 2, #radii do
        for i, d in ipairs(dirs) do
            local e = dirs[i % #dirs+1]
            local poly = {point(d, radii[ring-1]), point(d, radii[ring]), point(e, radii[ring])}
            if ring > 2 then poly[#poly+1] = point(e, radii[ring-1]) end
            out[#out+1] = {poly=poly, ring=ring-1}
        end
    end
    return out, radii
end

local function bounds(poly)
    local b = {math.huge, math.huge, -math.huge, -math.huge}
    for _, p in ipairs(poly) do b[1], b[2], b[3], b[4] = min(b[1],p[1]),min(b[2],p[2]),max(b[3],p[1]),max(b[4],p[2]) end
    return b
end
local function overlap(a,b) return a[1]<=b[3]+0.01 and b[1]<=a[3]+0.01 and a[2]<=b[4]+0.01 and b[2]<=a[4]+0.01 end

local function partition(def, impacts)
    local cells = {{poly=def.outline, tags={}}}
    if def.kind == "tempered" then
        local box = bounds(def.outline)
        -- At most ~400 tiles even for a very large brush. Piece size remains a lower bound.
        local size = max(def.piece_size, F.Root((box[3]-box[1])*(box[4]-box[2])/360)+1)
        cells = {}
        for x=box[1],box[3]-0.001,size do for y=box[2],box[4]-0.001,size do
            local poly=F.Clip(def.outline,{{x,y},{x+size,y},{x+size,y+size},{x,y+size}})
            if poly then cells[#cells+1]={poly=poly,tags={}} end
        end end
    else
        for slot, hit in ipairs(impacts) do
            local nextCells = {}
            local cuts = tiles(def,hit)
            for _, tile in ipairs(cuts) do tile.bounds=bounds(tile.poly) end
            for _, cell in ipairs(cells) do
                local box=bounds(cell.poly)
                for _, tile in ipairs(cuts) do
                    if overlap(box,tile.bounds) then
                        local poly=F.Clip(cell.poly,tile.poly)
                        if poly then
                            local tags={}
                            for k,v in ipairs(cell.tags) do tags[k]=v end
                            tags[slot]=tile.ring
                            nextCells[#nextCells+1]={poly=poly,tags=tags}
                            if #nextCells>F.MAX_CELLS then return nil end
                        end
                    end
                end
            end
            cells=nextCells
        end
    end
    for _, c in ipairs(cells) do c.center, c.bounds = F.Center(c.poly), bounds(c.poly) end
    return cells
end

-- A shared edge may be subdivided by another cut; endpoint equality alone loses islands.
local function sharedEdge(a,b,c,d)
    local dx,dy=b[1]-a[1],b[2]-a[2]
    local scale=max(abs(dx),abs(dy))
    if scale<0.0004 then return false end
    if abs(dx*(c[2]-a[2])-dy*(c[1]-a[1]))>scale*0.008 or
       abs(dx*(d[2]-a[2])-dy*(d[1]-a[1]))>scale*0.008 then return false end
    local axis=abs(dx)>abs(dy) and 1 or 2
    return min(max(a[axis],b[axis]),max(c[axis],d[axis]))-max(min(a[axis],b[axis]),min(c[axis],d[axis]))>0.0004
end
local function touches(first,second)
    for i,a in ipairs(first) do for j,c in ipairs(second) do
        if sharedEdge(a,first[i%#first+1],c,second[j%#second+1]) then return true end
    end end
    return false
end

local function remaining(def, impacts, cells, all)
    local keep, queue = {}, {}
    for i,c in ipairs(cells) do
        local removed=all
        for slot,h in ipairs(impacts) do if (c.tags[slot] or math.huge)<=h.hole then removed=true end end
        if not removed then
            keep[i]=false
            if touches(c.poly,def.outline) then keep[i]=true queue[#queue+1]=i end
        end
    end
    local cursor=1
    while queue[cursor] do
        local c=cells[queue[cursor]]
        for j,d in ipairs(cells) do
            if keep[j]==false and overlap(c.bounds,d.bounds) and touches(c.poly,d.poly) then
                keep[j]=true queue[#queue+1]=j
            end
        end
        cursor=cursor+1
    end
    return keep
end

function F.New(def)
    return {def=def, impacts={}, damage=0, revision=0, all=false, cells=partition(def,{})}
end

function F.Restore(def, impacts, damage, revision, all)
    local state=F.New(def)
    state.impacts,state.damage,state.revision,state.all=impacts,damage,revision,all
    state.cells=assert(partition(def,impacts),"glass snapshot exceeds cell bound")
    return state
end

function F.Remaining(state)
    local out,keep={},remaining(state.def,state.impacts,state.cells,state.all)
    for i,c in ipairs(state.cells) do if keep[i] then out[#out+1]=c.poly end end
    return out
end

function F.Apply(state, impact, forceAll, watchOnly)
    local threshold=F.Threshold(state.def)
    local energy=clamp(floor(impact.energy+0.5),0,2147483647)
    if not forceAll and energy<max(1,floor(threshold*0.08)) then return {},false end
    local hits={}
    for i,h in ipairs(state.impacts) do local copy={} for k,v in pairs(h) do copy[k]=v end hits[i]=copy end
    local nearest,dist=1,math.huge
    for i,h in ipairs(hits) do
        local dx,dy=h.x-impact.x,h.y-impact.y
        local d=dx*dx+dy*dy
        if d<dist then nearest,dist=i,d end
    end
    local append=#hits<F.MAX_IMPACTS and dist>state.def.piece_size*state.def.piece_size
    if #hits==0 or append then
        hits[#hits+1]={x=snap(impact.x),y=snap(impact.y),energy=0,seed=impact.seed,
            rays=clamp(8+floor(energy/120000)*2,8,16),kind=impact.kind,hole=0,dx=impact.dx,dy=impact.dy,dz=impact.dz}
        nearest=#hits
    end
    local cells=partition(state.def,hits)
    if not cells then
        table.remove(hits)
        nearest,dist=1,math.huge
        for i,h in ipairs(hits) do
            local dx,dy=h.x-impact.x,h.y-impact.y
            local d=dx*dx+dy*dy
            if d<dist then nearest,dist=i,d end
        end
        cells=state.cells
    end
    local before=remaining(state.def,hits,cells,state.all)
    local hit=hits[nearest]
    hit.energy=min(2147483647,hit.energy+energy)
    state.damage=min(2147483647,state.damage+energy)
    local broke=forceAll or (not watchOnly and state.damage>=threshold)
    if broke then
        if forceAll or state.def.kind=="tempered" then state.all=true else
            local _,radii=tiles(state.def,hit)
            local radius=state.def.piece_size*(2+F.Root(state.damage*100/ max(1,threshold))/4)
            local oldHole=hit.hole
            for i=2,#radii do if radii[i]<=radius then hit.hole=max(hit.hole,i-1) end end
            hit.hole=min(#radii-1,max(oldHole+1,hit.hole,1))
        end
        state.damage=0
    end
    local after=remaining(state.def,hits,cells,state.all)
    local pieces={}
    for i,c in ipairs(cells) do
        if before[i] and not after[i] then
            local dx,dy=c.center[1]-impact.x,c.center[2]-impact.y
            local distance=F.Root(dx*dx+dy*dy)
            local reach=state.def.piece_size*10
            local falloff=max(0,1-distance/reach)
            local speed=min(650,F.Root(energy/2))*falloff*falloff*state.def.velocity_transfer
            local rng=F.Generator(impact.seed+i*977)
            pieces[#pieces+1]={poly=c.poly,thickness=state.def.thickness,
                velocity={impact.dx*speed,impact.dy*speed,impact.dz*speed},
                spin={(rng(361)-180)*falloff,(rng(361)-180)*falloff,rng(241)-120},seed=impact.seed+i}
        end
    end
    state.impacts,state.cells,state.revision=hits,cells,state.revision+1
    return pieces,true,broke
end

function F.Cracks(state)
    local lines,seen={},{}
    for _,poly in ipairs(F.Remaining(state)) do for i,a in ipairs(poly) do
        local b=poly[i%#poly+1]
        local mid={(a[1]+b[1])/2,(a[2]+b[2])/2}
        for _,h in ipairs(state.impacts) do
            local extent=state.def.piece_size*(1+F.Root(h.energy/1500)/3)
            local dx,dy=mid[1]-h.x,mid[2]-h.y
            if dx*dx+dy*dy<=extent*extent then
                local first,second=a,b
                if a[1]>b[1] or (a[1]==b[1] and a[2]>b[2]) then first,second=b,a end
                local key=table.concat({first[1],first[2],second[1],second[2]},":")
                if not seen[key] then lines[#lines+1]={a,b,sharp=h.kind=="sharp"} seen[key]=true end
            end
        end
    end end
    return lines
end

return F
