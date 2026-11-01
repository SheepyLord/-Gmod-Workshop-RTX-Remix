-- MIT. Pure numeric planning. Keep exact polygons; a group merely shares one rigid transform.
local A = {}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<=8192 end
local function bounds(f)
    if type(f)~="table" or type(f.poly)~="table" or #f.poly<3 or #f.poly>64 or
        not finite(f.thickness) or f.thickness<.01 or f.thickness>64 then return end
    local loX,loY,hiX,hiY,area,px,py=1e9,1e9,-1e9,-1e9,0
    for _,v in ipairs(f.poly) do
        if type(v)~="table" then return end
        local x,y=v[1] or v.x,v[2] or v.y
        if not finite(x) or not finite(y) then return end
        if px then area=area+px*y-py*x end
        px,py=x,y
        loX,loY,hiX,hiY=math.min(loX,x),math.min(loY,y),math.max(hiX,x),math.max(hiY,y)
    end
    local v=f.poly[1];area=area+px*(v[2] or v.y)-py*(v[1] or v.x)
    if area<=.0001 then return end
    return loX,loY,hiX,hiY
end
function A.Pack(fragments, first, last, coarse, eye)
    local out,cells={},{}
    for i=first,last do
        local f=fragments[i];local lx,ly,hx,hy=bounds(f)
        if lx then
            local cx,cy=(lx+hx)*.5,(ly+hy)*.5
            -- Preserve every fragment with any part of its bounds within 256 units of the eye.
            local radius=math.sqrt((hx-lx)^2+(hy-ly)^2)*.5
            local far=eye and (cx-eye[1])^2+(cy-eye[2])^2+eye[3]^2>(256+radius)^2
            local key=coarse and far and hx-lx<=64 and hy-ly<=64 and
                (math.floor(cx/32).."/"..math.floor(cy/32).."/"..f.thickness) or nil
            local group=key and cells[key]
            local points=#f.poly*2
            if not group or #group.parts==8 or group.points+points>512 then
                group={parts={},points=0};out[#out+1]=group
                if key then cells[key]=group end
            end
            group.parts[#group.parts+1],group.points=f,group.points+points
        end
    end
    return out
end
return A
