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
    return F.Restore(s.def,s.impacts,s.damage,s.revision,s.all)
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
    local p,accepted=F.Apply(s,hit(0,0,100)) check(not accepted and #s.impacts==0,"sub-crack hit ignored")
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
    for _,c in ipairs(center.cells) do
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
    local area=0 for _,c in ipairs(center.cells) do area=area+F.Area(c.poly) end
    near(area,6144,1,"subdivision conserves pane area")
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
    local total=0 for _,h in ipairs(s.impacts) do total=total+h.energy end
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
else error("unknown fracture scenario "..tostring(mode)) end
print("fracture "..mode.." OK")
