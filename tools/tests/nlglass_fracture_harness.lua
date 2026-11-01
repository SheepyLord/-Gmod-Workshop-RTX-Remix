-- MIT. Pure LuaJIT acceptance of the real shared fracture. No GMod globals are defined.
local F=dofile(arg[1].."/nlglass/fracture.lua")
local function check(v,msg) assert(v,msg) end
local function near(a,b,t,msg) assert(math.abs(a-b)<t,(msg or "near")..": "..a.." vs "..b) end
local function encode(t)
    if type(t)~="table" then return type(t)=="number" and string.format("%.12g",t) or tostring(t) end
    local keys={} for k in pairs(t) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    local out={"{"} for _,k in ipairs(keys) do out[#out+1]=tostring(k).."="..encode(t[k]).."," end
    out[#out+1]="}" return table.concat(out)
end
local function definition(kind)
    return {outline={{-48,-32},{48,-32},{48,32},{-48,32}},thickness=1,strength=1,
        kind=kind or "annealed",piece_size=8,velocity_transfer=1}
end
local function hit(x,y,energy,seed)
    return {x=x or 0,y=y or 0,energy=energy or 180000,seed=seed or 171,kind="sharp",dx=0,dy=0,dz=1}
end
local function copy(s)
    return F.Restore(s.def,s.impacts,s.damage,s.revision,s.all,s.cells,s.pending,s.retiredEnergy,s.groups,s.nextCellID)
end
local mode=arg[2]
if mode=="determinism" then
    math.random=function() error("global random used") end
    math.sin=function() error("libm sin used") end math.cos=math.sin math.sqrt=math.sin
    local a,b=F.New(definition()),F.New(definition())
    local pieces
    for i=1,3 do
        local h=hit(3,-2,180000,71+i)
        local p=F.Apply(a,h) pieces=F.Apply(b,h)
        check(encode(p)==encode(pieces),"same state produces identical pieces")
        check(encode(F.Remaining(a))==encode(F.Remaining(b)),"identical remaining collision")
    end
    local fresh=copy(a)
    check(encode(F.Remaining(a))==encode(F.Remaining(fresh)),"snapshot replay gives identical cells")
    print(encode({cells=a.cells,pieces=pieces}))
elseif mode=="strength" then
    local def=definition()
    near(F.Threshold(def),450000,1,"reference threshold")
    local s=F.New(def)
    local p,accepted=F.Apply(s,hit(0,0,100)) check(#F.Cracks(s)==0,"sub-crack hit has no visible crack")
    p,accepted=F.Apply(s,hit()) check(accepted and #p==0,"pistol cracks without breaking")
    local initialCracks=F.Cracks(s)
    local first=#initialCracks check(first>0,"first crack visible")
    F.Apply(s,hit()) check(#F.Cracks(s)>first,"repeated hit grows cracks")
    p=F.Apply(s,hit()) check(#p>0 and #F.Remaining(s)>0,"third pistol hit makes a hole")
    local finalPolys=F.Remaining(s)
    for _,piece in ipairs(p) do finalPolys[#finalPolys+1]=piece.poly end
    for _,line in ipairs(initialCracks) do
        local found=false
        for _,poly in ipairs(finalPolys) do for i,a in ipairs(poly) do
            local b=poly[i%#poly+1]
            if (encode(a)==encode(line[1]) and encode(b)==encode(line[2])) or (encode(b)==encode(line[1]) and encode(a)==encode(line[2])) then found=true end
        end end
        check(found,"visible crack survives as an actual final cell edge")
    end
    def.thickness=2 near(F.Threshold(def),1800000,1,"thickness squared")
    def=definition("tempered") near(F.Threshold(def),1575000,1,"tempered strength")
elseif mode=="pattern" then
    local center,corner=F.New(definition()),F.New(definition())
    local pc=F.Apply(center,hit(0,0,600000))
    local pe=F.Apply(corner,hit(-46,-30,600000))
    local function average(pieces)
        local x,y=0,0 for _,p in ipairs(pieces) do local c=F.Center(p.poly) x=x+c[1] y=y+c[2] end
        return x/#pieces,y/#pieces
    end
    local x,y=average(pc) near(x,0,5) near(y,0,5)
    x,y=average(pe) check(x<-20 and y<-10,"corner breakout follows corner")
    local small,large,ns,nl=0,0,0,0
    local sized={} for _,c in ipairs(center.cells) do sized[#sized+1]=c end
    for _,p in ipairs(pc) do sized[#sized+1]={poly=p.poly,center=F.Center(p.poly)} end
    for _,c in ipairs(sized) do
        local d=c.center[1]^2+c.center[2]^2
        if d<64 then small=small+F.Area(c.poly) ns=ns+1 elseif d>900 then large=large+F.Area(c.poly) nl=nl+1 end
    end
    check(large/nl>small/ns*3,"piece area grows away from impact")
    local slow,fast=0,0
    for _,p in ipairs(pc) do
        local c=F.Center(p.poly) local d=c[1]^2+c[2]^2
        if d<64 then fast=math.max(fast,p.velocity[3]) elseif d>400 then slow=math.max(slow,p.velocity[3]) end
    end
    check(fast>slow*1.5 and slow>0,"velocity falls off with distance")
    local remaining=F.Remaining(center) check(#remaining>0,"frame remains")
    local before=#remaining
    local p=F.Apply(center,hit(36,20,800000,912))
    check(#p>0,"later hit breaks out retained cells")
    local area=0
    for _,poly in ipairs(F.Remaining(center)) do area=area+F.Area(poly) end
    for _,piece in ipairs(pc) do area=area+F.Area(piece.poly) end
    for _,piece in ipairs(p) do area=area+F.Area(piece.poly) end
    near(area,6144,2,"subdivision conserves remaining plus released area")
    check(encode(pc)~=encode(pe),"different impact has different cells")
elseif mode=="tempered" then
    local s=F.New(definition("tempered"))
    local p=F.Apply(s,hit(0,0,180000)) check(#p==0 and #F.Cracks(s)>0,"tempered first cracks")
    p=F.Apply(s,hit(0,0,1600000)) check(#p>=80 and #F.Remaining(s)==0,"tempered shatters completely")
    local lo,hi=math.huge,0
    for _,piece in ipairs(p) do local a=F.Area(piece.poly) lo=math.min(lo,a) hi=math.max(hi,a) end
    check(hi/lo<1.1,"tempered cells are nearly uniform")
    local d=definition("tempered") d.outline={{-2048,-2048},{2048,-2048},{2048,2048},{-2048,2048}}
    check(#F.New(d).cells<=512,"large pane has bounded tessellation")
elseif mode=="bounded" then
    local s=F.New(definition())
    for i=1,30 do
        F.Apply(s,hit((i*37)%90-45,(i*19)%60-30,50000,900+i))
        check(#s.impacts<=F.MAX_IMPACTS and #s.cells<=F.MAX_CELLS,"bounded impacts/cells")
        local restored=copy(s)
        check(encode(F.Remaining(s))==encode(F.Remaining(restored)),"bounded history replay")
    end
    local total=(s.retiredEnergy or 0)+(s.pending or 0) for _,h in ipairs(s.impacts) do total=total+h.energy end
    check(total==1500000,"full impact slots merge energy instead of dropping damage")
elseif mode=="connectivity" then
    local d=definition()
    local function cell(poly) return {poly=poly,tags={},bounds={-48,-32,48,32}} end
    local s={def=d,impacts={},all=false,cells={cell({{-48,-32},{-40,-32},{-40,32},{-48,32}}),
        cell({{-4,-4},{4,-4},{4,4},{-4,4}}),cell({{-40,0},{-30,0},{-30,8},{-40,8}}),
        cell({{10,-32},{10+1/1024,-32},{10,31}})}}
    check(#F.Remaining(s)==3,"unsupported island falls; subdivided and one-grid-width edges keep support")
elseif mode=="forced" then
    for _,kind in ipairs({"annealed","tempered"}) do
        local s=F.New(definition(kind))
        local p=F.Apply(s,hit(0,0,1),true)
        check(#p>0 and #F.Remaining(s)==0,"nominal forced break always produces pieces")
    end
elseif mode=="cap_local" then
    local d=definition() d.outline={{-128,-64},{128,-64},{128,64},{-128,64}}
    local s=F.New(d)
    local locations={{-110,-45},{-70,40},{-30,-40},{20,45},{60,-40},{110,40},{-100,20},{80,15},{0,0},{40,-15},{-40,10},{100,-40}}
    for i,p in ipairs(locations) do
        F.Apply(s,hit(p[1],p[2],180000,171+i),false,true)
        local found=false
        for _,h in ipairs(s.impacts) do if (h.x-p[1])^2+(h.y-p[2])^2<=1 then found=true end end
        check(found,"new impact keeps its own centre beyond the cell/history cap: "..i)
        check(#s.cells<=F.MAX_CELLS,"local refinement stays bounded")
    end
    local point=locations[#locations]
    local pieces=F.Apply(s,hit(point[1],point[2],1200000,800))
    local closest=math.huge
    for _,p in ipairs(pieces) do local c=F.Center(p.poly) closest=math.min(closest,(c[1]-point[1])^2+(c[2]-point[2])^2) end
    check(closest<64,"late breakout is at the actual hit, not an old centre")
    check(encode(F.Remaining(s))==encode(F.Remaining(copy(s))),"coarsened topology survives a snapshot")
elseif mode=="weak" then
    local s=F.New(definition())
    for i=1,8 do F.Apply(s,hit(0,0,4000,50+i)) check(#F.Cracks(s)==0,"no crack before weak hits reach floor") end
    F.Apply(s,hit(0,0,4000,60))
    check(#F.Cracks(s)>0 and s.damage==36000,"sub-floor energy accumulates into a crack")
    for _,size in ipairs({{256,128,1},{128,128,2}}) do
        local d=definition() d.outline={{0,0},{size[1],0},{size[1],size[2]},{0,size[2]}} d.thickness=size[3]
        local pane=F.New(d) F.Apply(pane,hit(20,20,60000,71))
        check(#F.Cracks(pane)>0,"five-damage pistol round cracks ordinary large/thick glass")
    end
elseif mode=="incremental" then
    local s=F.New(definition()) F.Apply(s,hit())
    local clips,clip=0,F.Clip
    F.Clip=function(...) clips=clips+1 return clip(...) end
    F.Apply(s,hit())
    check(clips==0,"repeated hit reuses existing cells without whole-history clipping")
    check(F.Remaining(s)==F.Remaining(s) and F.Cracks(s)==F.Cracks(s),"remaining/cracks cached by revision")
elseif mode=="tempered_spider" then
    local s=F.New(definition("tempered")) F.Apply(s,hit())
    for _,line in ipairs(F.Cracks(s)) do
        local a,b=line[1],line[2]
        check(a[1]^2+a[2]^2<700 and b[1]^2+b[2]^2<700,"tempered cracks are a small local spiderweb, never the pane grid")
    end
elseif mode=="tiny_edges" then
    local p=F.Clip({{0,0},{10,0},{10,10},{0,10}},{{0,0},{1/1024,0},{10,10},{0,10}})
    check(p,"clipped polygon remains usable")
    for i,a in ipairs(p) do local b=p[i%#p+1] check((a[1]-b[1])^2+(a[2]-b[2])^2>=(1/256)^2,"clip merges vertices closer than 1/256") end
    local tested=0
    for seed=1,180 do
        local s=F.New(definition()) F.Apply(s,hit((seed*37)%90-45,(seed*19)%60-30,180000,seed),false,true)
        for _,c in ipairs(s.cells) do for i,a in ipairs(c.poly) do
            local b=c.poly[i%#c.poly+1] tested=tested+1
            check((a[1]-b[1])^2+(a[2]-b[2])^2>=(1/256)^2,"generated piece has no short mesh-rejected edge")
        end end
    end
    print("generated_edges="..tested)
elseif mode=="coarsen" then
    local d=definition() d.outline={{-128,-64},{128,-64},{128,64},{-128,64}}
    local s=F.New(d) local peak=0
    for i=1,100 do
        F.Apply(s,hit((i*37)%240-120,(i*19)%112-56,80000,900+i),false,true)
        check(not s.all,"bounded unbroken history coarsens instead of losing the pane")
        check(#s.cells<=512,"coarsened cell budget") peak=math.max(peak,#s.cells)
        check(#s.groups<#s.cells,"subdivision history is bounded by live cells")
    end
    local area=0 for _,poly in ipairs(F.Remaining(s)) do area=area+F.Area(poly) end
    near(area,32768,4,"coarsening conserves unbroken area within clipping grid tolerance")
    check(peak>F.CellLimit(d)*0.9,"probe actually reaches the cell cap")
    check(encode(F.Remaining(s))==encode(F.Remaining(copy(s))),"near-cap coarsening snapshot")
    print("peak_cells="..peak.." area_error="..math.abs(area-32768))
    local dense=F.New(d)
    for i=1,200 do
        local pieces=F.Apply(dense,hit((i*37)%31-15,(i*19)%31-15,180000,1700+i),false,true)
        check(not dense.all and #pieces==0 and #dense.cells<=512,"dense visual cuts never shatter engine-owned glass")
    end
elseif mode=="hole_coarsen" then
    local d=definition() d.outline={{-128,-64},{128,-64},{128,64},{-128,64}}
    local s=F.New(d) local pieces=F.Apply(s,hit(0,0,1200000,88))
    check(#pieces>0,"probe starts with a real hole")
    for i=1,100 do F.Apply(s,hit((i*37)%240-120,(i*19)%112-56,80000,900+i),false,true) end
    check(not s.all and #s.cells<=512,"perforated pane remains bounded")
    for _,piece in ipairs(pieces) do
        local p=F.Center(piece.poly)
        for _,poly in ipairs(F.Remaining(s)) do
            local inside=true
            for i,a in ipairs(poly) do local b=poly[i%#poly+1]
                if (b[1]-a[1])*(p[2]-a[2])-(b[2]-a[2])*(p[1]-a[1])<=0 then inside=false break end
            end
            check(not inside,"coarsening never fills an old hole")
        end
    end
elseif mode=="border" then
    local s=F.New(definition()) F.Apply(s,hit(45,28,300000,901))
    for _,line in ipairs(F.Cracks(s)) do
        local a,b=line[1],line[2]
        check(not (a[1]==b[1] and math.abs(a[1])==48) and not (a[2]==b[2] and math.abs(a[2])==32),"pane perimeter is not a crack")
    end
elseif mode=="timings" then
    local now=os.clock
    local ffi=require("ffi")
    if ffi.os=="Windows" then
        ffi.cdef("int QueryPerformanceCounter(int64_t*); int QueryPerformanceFrequency(int64_t*);")
        local tick,freq=ffi.new("int64_t[1]"),ffi.new("int64_t[1]")
        ffi.C.QueryPerformanceFrequency(freq) local frequency=tonumber(freq[0])
        now=function() ffi.C.QueryPerformanceCounter(tick) return tonumber(tick[0])/frequency end
    end
    local d=definition() d.outline={{-128,-64},{128,-64},{128,64},{-128,64}}
    local base=F.New(d)
    for i=1,100 do F.Apply(base,hit((i*37)%240-120,(i*19)%112-56,180000,900+i),false,true) end
    print("prepared_cells="..#base.cells)
    check(#base.cells>=F.CellLimit(d)*0.8,"timing probe actually measures near the cap")
    local hits,repeats,breaks={},{},{}
    for run=1,80 do
        local s=copy(base)
        local start=now() F.Apply(s,hit(0,0,180000,55),false,true) hits[#hits+1]=(now()-start)*1000
        start=now() F.Apply(s,hit(0,0,180000,55),false,true) repeats[#repeats+1]=(now()-start)*1000
        start=now() F.Apply(s,hit(0,0,600000,56)) breaks[#breaks+1]=(now()-start)*1000
    end
    local function report(name,values)
        table.sort(values) local sum=0 for _,v in ipairs(values) do sum=sum+v end
        print(string.format("%s n=%d mean_ms=%.4f p99_ms=%.4f",name,#values,sum/#values,values[math.ceil(#values*.99)]))
    end
    report("hit",hits) report("repeat",repeats) report("break",breaks)
elseif mode=="density" then
    for _,kind in ipairs({"annealed","tempered"}) do
        local limit=kind=="tempered" and 300 or 200
        for _,size in ipairs({{96,64},{256,128},{128,256},{8192,1},{1,8192},{8192,8192}}) do
            local d=definition(kind)
            d.outline={{0,0},{size[1],0},{size[1],size[2]},{0,size[2]}}
            for _,corner in ipairs({false,true}) do
                local x=corner and math.min(2,size[1]/4) or size[1]/2
                local y=corner and math.min(2,size[2]/4) or size[2]/2
                for _,spacing in ipairs({4,8,64}) do
                    d.piece_size=spacing
                    local s=F.New(d)
                    -- Native windows may collect many hits before the engine breaks them.
                    for i=1,24 do
                        F.Apply(s,hit(size[1]*((i*37)%97)/100,size[2]*((i*19)%97)/100,180000,900+i),false,true)
                        check(#s.cells<=limit,"live fracture stays inside its kind's piece budget")
                    end
                    local pieces=F.Apply(s,hit(x,y,2000000,171),true)
                    check(#pieces>0 and #pieces<=limit and #pieces<=F.MAX_CELLS,"break density bound for any pane aspect/hit/spacing")
                    local area=0 for _,p in ipairs(pieces) do area=area+F.Area(p.poly) end
                    near(area,size[1]*size[2],math.max(2,size[1]*size[2]*0.00002),"bounded pieces conserve pane area")
                    if spacing==8 and size[1]<=256 and size[2]<=256 then
                        local fresh=F.New(d) local first=F.Apply(fresh,hit(x,y,2000000,171),true)
                        print(string.format("%s %dx%d %s first=%d after_24=%d cap=%d",kind,size[1],size[2],corner and "corner" or "centre",#first,#pieces,limit))
                    end
                end
            end
        end
    end
else error("unknown fracture scenario "..tostring(mode)) end
print("fracture "..mode.." OK")
