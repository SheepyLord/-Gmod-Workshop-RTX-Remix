-- Hair and clothing that float in water (mmdhl_secondary_buoyancy): the binary module needs the
-- height of the water surface around each character (SetSecondaryWater). Four times a second,
-- while the setting is on, util.PointContents finds it above the character's lowest bone: by
-- halving the span up to the highest one, or, under water, stepping up until it is dry.
-- Nothing runs while the setting is off.
local W={}
mmdhl.secondaryWater=W
local Interval=.25
local function liquid(contents) return bit.band(contents,bit.bor(CONTENTS_WATER,CONTENTS_SLIME))~=0 end
-- The surface height at (x, y) for a character from `bottom` to `top`, to an eighth of a unit,
-- or nil when its lowest point is out of the water. `contents(position)` is util.PointContents.
function W.Level(x,y,bottom,top,contents)
 local function wet(z) return liquid(contents(Vector(x,y,z))) end
 if not wet(bottom) then return nil end
 local low,high=bottom,math.max(top,bottom+1)
 if wet(high) then
  -- Deeper than the character is tall: up in doubling steps, at most 8192 units above it.
  local step=math.max(16,high-bottom)
  while wet(high) do
   if high-top>8192 then return high end
   low=high high=high+step step=step*2
  end
 end
 while high-low>.125 do
  local middle=(low+high)*.5
  if wet(middle) then low=middle else high=middle end
 end
 return (low+high)*.5
end
-- ent.MMDHLWaterLevel: the height last sent, false for "no water", nil when nothing was sent.
function mmdhl.UpdateSecondaryWater(ent,palette)
 local native=mmdhl.native
 if not isfunction(native.SetSecondaryWater) then return end
 local setting=GetConVar('mmdhl_secondary_buoyancy')
 if not (setting and setting:GetBool()) then
  if ent.MMDHLWaterLevel~=nil and native.SetSecondaryWater(mmdhl.GetInstance(ent),nil) then ent.MMDHLWaterLevel=nil end
  return
 end
 local now=RealTime() if (ent.MMDHLWaterAt or 0)>now then return end
 ent.MMDHLWaterAt=now+Interval
 -- palette: the bone-to-world matrices native_render.lua gathered this frame.
 local bottom,top=math.huge,-math.huge
 for i=1,#palette do local z=palette[i]:GetTranslation().z if z<bottom then bottom=z end if z>top then top=z end end
 if bottom>top then return end
 local center=ent:WorldSpaceCenter()
 -- A little above the highest bone: the top of the head.
 local level=W.Level(center.x,center.y,bottom,top+8,util.PointContents)
 local old=ent.MMDHLWaterLevel
 if level==nil then if old==false then return end
 elseif isnumber(old) and math.abs(level-old)<.25 then return end
 if native.SetSecondaryWater(mmdhl.GetInstance(ent),level) then ent.MMDHLWaterLevel=level or false end
end
