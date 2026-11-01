-- MIT. Pure Lua 5.1: no engine globals, random(), trigonometry or platform-dependent hash order.
local F = {MAX_IMPACTS = 8, MAX_CELLS = 512, ANNEALED_CELLS = 200, TEMPERED_CELLS = 300, GRID = 1024, MIN_EDGE = 1/256}
local abs, floor, min, max = math.abs, math.floor, math.min, math.max
local function clamp(x, a, b) return max(a, min(b, x)) end
local function snap(x) return floor(x * F.GRID + 0.5) / F.GRID end
F.Snap = snap
function F.CellLimit(def)
    return min(F.MAX_CELLS,def.kind=="tempered" and F.TEMPERED_CELLS or F.ANNEALED_CELLS)
end

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
    -- Clipping can produce distinct snapped points a single wire step apart. The debris mesh
    -- rejects such edges; collapse them here, identically in collision, drawing and snapshots.
    local changed=true
    while changed and #hull>=3 do
        changed=false
        for i,a in ipairs(hull) do
            local j=i%#hull+1 local b=hull[j]
            if (a[1]-b[1])^2+(a[2]-b[2])^2<F.MIN_EDGE^2 then
                table.remove(hull,j) changed=true break
            end
        end
    end
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
function F.CrackFloor(def) return min(36000,max(1,floor(F.Threshold(def)*0.08))) end

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
    local reach=limit*2+def.piece_size
    local budget=max(1,floor(F.CellLimit(def)/hit.rays))
    while r[#r] < reach do
        -- Keep the small impact rings. On an enormous pane the final ring stretches to the
        -- frame instead of adding more far-away pieces; one fresh cut always fits the budget.
        if #r>=budget then radius=reach end
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

local function adjacency(cells)
    -- Sweep bounds once to build adjacency. The previous flood repeatedly compared every pair,
    -- including distant cells, on every Remaining() call.
    local order,adj={},{}
    for i=1,#cells do order[i]=i adj[i]={} end
    table.sort(order,function(a,b) return cells[a].bounds[1]<cells[b].bounds[1] or
        (cells[a].bounds[1]==cells[b].bounds[1] and a<b) end)
    for a=1,#order do
        local i=order[a] local c=cells[i]
        for b=a+1,#order do
            local j=order[b] local d=cells[j]
            if d.bounds[1]>c.bounds[3]+0.01 then break end
            if overlap(c.bounds,d.bounds) and touches(c.poly,d.poly) then
                adj[i][#adj[i]+1]=j adj[j][#adj[j]+1]=i
            end
        end
    end
    return adj
end
local function supported(def,cells)
    local keep,queue={},{}
    for i,c in ipairs(cells) do
        keep[i]=false
        if touches(c.poly,def.outline) then keep[i]=true queue[#queue+1]=i end
    end
    local adj=adjacency(cells)
    local cursor=1
    while queue[cursor] do
        for _,j in ipairs(adj[queue[cursor]]) do if not keep[j] then keep[j]=true queue[#queue+1]=j end end
        cursor=cursor+1
    end
    return keep
end

local function cell(poly,tags,id) return {poly=poly,tags=tags or {},id=id,center=F.Center(poly),bounds=bounds(poly)} end
local function copyTags(tags)
    local out={} for i=1,F.MAX_IMPACTS do out[i]=tags[i] end return out
end
local function cache(state,topologyChanged)
    if not state.polys or topologyChanged~=false then
        state.polys={} for _,c in ipairs(state.cells) do state.polys[#state.polys+1]=c.poly end
    end
    state.cracks=nil state.visualRevision=state.revision
end
local function uniform(def)
    local box,cells=bounds(def.outline),{}
    local width,height=box[3]-box[1],box[4]-box[2]
    local limit=F.CellLimit(def)
    local size=max(def.piece_size,F.Root(width*height/limit),width/limit,height/limit)
    local nx,ny=max(1,math.ceil(width/size)),max(1,math.ceil(height/size))
    while nx*ny>limit do
        if nx>1 and (ny==1 or width/nx<height/ny) then nx=nx-1 else ny=ny-1 end
    end
    -- Divide the full bounds evenly: no tiny partial row along the far edge and no overflow
    -- from rounding the square-root estimate on long, thin windows.
    for i=0,nx-1 do for j=0,ny-1 do
        local x,y=snap(box[1]+width*i/nx),snap(box[2]+height*j/ny)
        local xx,yy=snap(box[1]+width*(i+1)/nx),snap(box[2]+height*(j+1)/ny)
        local poly=F.Clip(def.outline,{{x,y},{xx,y},{xx,yy},{x,yy}})
        if poly then cells[#cells+1]=cell(poly) end
    end end
    return cells
end

-- Retain the subdivision tree. A complete old subtree can return to its exact convex parent,
-- even when no pair of its clipped children has a convex union. An incomplete subtree (a hole)
-- can never coarsen. Only live nodes/complete groups survive, so the tree is bounded by 2*cells-1.
local function descendants(cells,groups)
    local nodes,memo={},{}
    for _,c in ipairs(cells) do memo[c.id]={c.id} end
    for _,g in ipairs(groups) do nodes[g.id]=g end
    local function visit(id)
        if memo[id]~=nil then return memo[id] end
        local g=nodes[id] if not g then memo[id]=false return false end
        local out,complete={},true
        for _,child in ipairs(g.children) do
            local leaves=visit(child)
            if not leaves then complete=false else for _,leaf in ipairs(leaves) do out[#out+1]=leaf end end
        end
        memo[id]=complete and out or false return memo[id]
    end
    for _,g in ipairs(groups) do visit(g.id) end
    return memo
end
local function prune(cells,groups)
    local leaves=descendants(cells,groups) local live,out={},{}
    for _,c in ipairs(cells) do live[c.id]=true end
    for _,g in ipairs(groups) do if not live[g.id] and leaves[g.id] then out[#out+1]=g end end
    return out
end
local function distanceSquared(poly,hit)
    local inside,closest=true,math.huge
    for i,a in ipairs(poly) do
        local b=poly[i%#poly+1] local dx,dy=b[1]-a[1],b[2]-a[2]
        if dx*(hit.y-a[2])-dy*(hit.x-a[1])<0 then inside=false end
        local t=clamp(((hit.x-a[1])*dx+(hit.y-a[2])*dy)/max(0.000001,dx*dx+dy*dy),0,1)
        closest=min(closest,(hit.x-a[1]-t*dx)^2+(hit.y-a[2]-t*dy)^2)
    end
    return inside and 0 or closest
end
local function coarsen(cells,groups,hit,target,protect)
    local leaves=descendants(cells,groups)
    local order={}
    for _,g in ipairs(groups) do
        local distance=distanceSquared(g.poly,hit)
        if leaves[g.id] and distance>protect*protect then order[#order+1]={group=g,distance=distance} end
    end
    table.sort(order,function(a,b) return a.distance>b.distance or (a.distance==b.distance and a.group.id<b.group.id) end)
    local replacement,chosen,count={},{},#cells
    for _,entry in ipairs(order) do
        if count<=target then break end
        local g=entry.group local list=leaves[g.id] local available=true
        for _,id in ipairs(list) do if replacement[id] then available=false break end end
        if available then
            for _,id in ipairs(list) do replacement[id]=g end
            chosen[g.id]=true count=count-#list+1
        end
    end
    local out,emitted={},{}
    for _,c in ipairs(cells) do
        local g=replacement[c.id]
        if not g then out[#out+1]=c elseif not emitted[g.id] then
            emitted[g.id]=true out[#out+1]=cell(g.poly,g.tags,g.id)
        end
    end
    return out,prune(out,groups)
end

local function refine(def,cells,groups,nextID,hit,slot,radius)
    local cuts=tiles(def,hit)
    for _,tile in ipairs(cuts) do tile.bounds=bounds(tile.poly) end
    local near={hit.x-radius,hit.y-radius,hit.x+radius,hit.y+radius}
    local out,newGroups,changed={},{},false
    for _,g in ipairs(groups) do newGroups[#newGroups+1]=g end
    for _,c in ipairs(cells) do
        if c.tags[slot] or not overlap(c.bounds,near) then out[#out+1]=c else
            changed=true
            local children={}
            for _,tile in ipairs(cuts) do if overlap(c.bounds,tile.bounds) then
                local poly=F.Clip(c.poly,tile.poly)
                if poly then
                    local tags=copyTags(c.tags) tags[slot]=tile.ring
                    nextID=nextID+1 children[#children+1]=cell(poly,tags,nextID)
                end
            end end
            if #children==1 then children[1].id=c.id end
            if #children==0 then out[#out+1]=c end
            if #children>1 then
                local ids={} for _,child in ipairs(children) do ids[#ids+1]=child.id end
                newGroups[#newGroups+1]={id=c.id,poly=c.poly,tags=c.tags,children=ids}
            end
            for _,child in ipairs(children) do out[#out+1]=child end
        end
    end
    if not changed then return cells,groups,nextID end
    return out,newGroups,nextID
end

function F.New(def)
    local s={def=def,impacts={},damage=0,pending=0,retiredEnergy=0,revision=0,all=false,cells={cell(def.outline,{},1)},groups={},nextCellID=1}
    cache(s) return s
end

function F.Restore(def,impacts,damage,revision,all,cells,pending,retiredEnergy,groups,nextCellID)
    local s={def=def,impacts=impacts,damage=damage,revision=revision,all=all,
        pending=pending or 0,retiredEnergy=retiredEnergy or 0,cells={},groups=groups or {},nextCellID=nextCellID or 1}
    for _,c in ipairs(cells or {}) do s.cells[#s.cells+1]=cell(c.poly,c.tags,c.id) end
    assert(#s.cells<=F.MAX_CELLS,"glass snapshot exceeds cell bound")
    cache(s) return s
end
function F.Snapshot(s)
    -- Cells/impacts are immutable across Apply. A pre-break snapshot needs no fracture rebuild.
    return {def=s.def,impacts=s.impacts,damage=s.damage,revision=s.revision,all=s.all,cells=s.cells,
        pending=s.pending,retiredEnergy=s.retiredEnergy,visualRevision=s.visualRevision,groups=s.groups,nextCellID=s.nextCellID}
end

function F.Remaining(state)
    if not state.polys then -- also supports hand-constructed diagnostic fixtures
        local keep=supported(state.def,state.cells)
        state.polys={}
        for i,c in ipairs(state.cells) do if keep[i] and not state.all then state.polys[#state.polys+1]=c.poly end end
    end
    return state.polys
end

function F.Apply(state, impact, forceAll, watchOnly)
    local threshold=F.Threshold(state.def)
    local energy=clamp(floor(impact.energy+0.5),0,2147483647)
    if state.all or (not forceAll and energy==0) then return {},false end
    state.damage=min(2147483647,state.damage+energy)
    state.pending=min(2147483647,state.pending+energy)
    state.revision=state.revision+1
    if not forceAll and state.pending<F.CrackFloor(state.def) then return {},true,false end
    local accumulated=state.pending state.pending=0
    local hits={}
    for i,h in ipairs(state.impacts) do local copy={} for k,v in pairs(h) do copy[k]=v end hits[i]=copy end
    local nearest,dist,furthest,far=1,math.huge,1,-1
    for i,h in ipairs(hits) do
        local dx,dy=h.x-impact.x,h.y-impact.y
        local d=dx*dx+dy*dy
        if d<dist then nearest,dist=i,d end
        if d>far then furthest,far=i,d end
    end
    local cells,groups,nextID=state.cells,state.groups,state.nextCellID
    if #hits==0 or dist>1 then
        nearest=#hits<F.MAX_IMPACTS and #hits+1 or furthest
        if hits[nearest] then state.retiredEnergy=min(2147483647,state.retiredEnergy+hits[nearest].energy) end
        hits[nearest]={x=snap(impact.x),y=snap(impact.y),energy=0,seed=impact.seed,
            rays=clamp(8+floor(accumulated/120000)*2,8,16),kind=impact.kind,hole=0,dx=impact.dx,dy=impact.dy,dz=impact.dz}
        local cleared={}
        for _,c in ipairs(cells) do
            if c.tags[nearest] then local tags=copyTags(c.tags) tags[nearest]=nil cleared[#cleared+1]=cell(c.poly,tags,c.id)
            else cleared[#cleared+1]=c end
        end
        cells=cleared
        local clearedGroups={}
        for _,g in ipairs(groups) do
            if g.tags[nearest] then local tags=copyTags(g.tags) tags[nearest]=nil
                clearedGroups[#clearedGroups+1]={id=g.id,poly=g.poly,tags=tags,children=g.children}
            else clearedGroups[#clearedGroups+1]=g end
        end
        groups=clearedGroups
    end
    local hit=hits[nearest]
    hit.energy=min(2147483647,hit.energy+accumulated)
    local broke=forceAll or (not watchOnly and state.damage>=threshold)
    local whole=forceAll or (broke and state.def.kind=="tempered")
    if state.def.kind=="annealed" then
        -- Refine just the contact neighbourhood. Extending every new ray through all old rings
        -- recreates the quadratic cross-cut explosion this bound is meant to avoid.
        local refined,newGroups,newID=refine(state.def,cells,groups,nextID,hit,nearest,state.def.piece_size)
        local limit=F.CellLimit(state.def)
        if #refined>limit then refined,newGroups=coarsen(refined,newGroups,hit,max(1,limit-32),state.def.piece_size*3) end
        if #refined>limit then refined,newGroups=coarsen(refined,newGroups,hit,limit,state.def.piece_size) end
        if #refined>limit then
            -- A pane with too many non-convex hole boundaries cannot be coarsened exactly. Release
            -- the remaining bounded topology rather than moving a hit or creating invisible glass.
            if watchOnly then
                -- An engine-owned pane is still whole: simplify its purely visual cuts and
                -- rebuild the latest contact instead of inventing an early native shatter.
                nextID=nextID+1
                cells,groups={cell(state.def.outline,{},nextID)},{}
                refined,newGroups,newID=refine(state.def,cells,groups,nextID,hit,nearest,state.def.piece_size)
                cells,groups,nextID=refined,newGroups,newID
            else whole,broke=true,true end
        else cells,groups,nextID=refined,newGroups,newID end
    elseif whole then cells=uniform(state.def) end
    if broke then
        if not whole then
            local radii=rings(state.def,hit)
            local radius=state.def.piece_size*(2+F.Root(state.damage*100/ max(1,threshold))/4)
            local oldHole=hit.hole
            for i=2,#radii do if radii[i]<=radius then hit.hole=max(hit.hole,i-1) end end
            hit.hole=min(#radii-1,max(oldHole+1,hit.hole,1))
        end
        state.damage=0
    end
    local candidates,removed={},{}
    local holeRadius=0
    if broke and not whole then local radii=rings(state.def,hit) holeRadius=radii[hit.hole+1] or 0 end
    for i,c in ipairs(cells) do
        local near=(c.center[1]-impact.x)^2+(c.center[2]-impact.y)^2<=holeRadius*holeRadius
        if whole or (broke and ((c.tags[nearest] or math.huge)<=hit.hole or (not c.tags[nearest] and near))) then removed[#removed+1]=c
        else candidates[#candidates+1]=c end
    end
    if broke and not whole then
        local keep=supported(state.def,candidates)
        local supportedCells={}
        for i,c in ipairs(candidates) do
            if keep[i] then supportedCells[#supportedCells+1]=c else removed[#removed+1]=c end
        end
        candidates=supportedCells
    end
    local pieces={}
    for i,c in ipairs(removed) do
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
    if not broke then candidates=cells end
    local changed=candidates~=state.cells
    state.impacts,state.cells,state.all=hits,candidates,whole or #candidates==0
    state.groups=whole and {} or (broke and prune(candidates,groups) or groups)
    state.nextCellID=nextID
    cache(state,changed)
    return pieces,true,broke
end

function F.Cracks(state)
    if state.cracks then return state.cracks end
    local lines,seen={},{}
    local polys=F.Remaining(state)
    if state.def.kind=="tempered" and not state.all then
        -- The uniform pieces exist only at shatter time. Before that, a small impact spiderweb.
        polys={}
        for _,h in ipairs(state.impacts) do
            for _,tile in ipairs(tiles(state.def,h)) do if tile.ring<=3 then
                local poly=F.Clip(state.def.outline,tile.poly) if poly then polys[#polys+1]=poly end
            end end
        end
    end
    for _,poly in ipairs(polys) do for i,a in ipairs(poly) do
        local b=poly[i%#poly+1]
        local mid={(a[1]+b[1])/2,(a[2]+b[2])/2}
        local border=false
        for j,c in ipairs(state.def.outline) do if sharedEdge(a,b,c,state.def.outline[j%#state.def.outline+1]) then border=true break end end
        for _,h in ipairs(state.impacts) do if not border then
            local extent=state.def.piece_size*(1+F.Root(h.energy/1500)/3)
            if state.def.kind=="tempered" then extent=min(extent,state.def.piece_size*2.5) end
            local dx,dy=mid[1]-h.x,mid[2]-h.y
            if dx*dx+dy*dy<=extent*extent then
                local first,second=a,b
                if a[1]>b[1] or (a[1]==b[1] and a[2]>b[2]) then first,second=b,a end
                local key=table.concat({first[1],first[2],second[1],second[2]},":")
                if not seen[key] then lines[#lines+1]={a,b,sharp=h.kind=="sharp"} seen[key]=true end
            end
        end end
    end end
    state.cracks=lines
    return lines
end

return F
