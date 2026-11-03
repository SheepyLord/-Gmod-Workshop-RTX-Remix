-- Player-facing glue: identity states, candidate/file actions, source-less choices and thumbnails.
SERVER=false CLIENT=true BRANCH="x86-64" TOP=1 LEFT=2 FILL=3
local hooks,commands,buttons,images={},{},{},0
function isstring(v) return type(v)=="string" end
function IsValid(v) return type(v)=="table" end
function RealTime() return 100 end
function ScrW() return 1280 end
function ScrH() return 720 end
function GetConVar() return nil end
file={Exists=function() return false end}
hook={Add=function(_,key,fn) hooks[key]=fn end}
concommand={Add=function(key,fn) commands[key]=fn end}
spawnmenu={AddToolMenuOption=function(_,_,_,_,_,_,build) assert(type(build)=="function") end}
local ent={}
function LocalPlayer() return {GetEyeTrace=function() return {Entity={}} end,
    GetEyeTraceNoCursor=function() return {Entity=ent} end} end
mmdhl={GetAsset=function(e) assert(e==ent) return "asset" end,
    Entities=function() return {ent} end,
    assets={asset={materials={{path="first"},{path="second"},{path="unseen"}}}},
    library={entries={asset={source="E:/model.pmx",info={materials={{base="衣服.png"},{base="copy.png"},{base="unseen.png"}}}}}}}
local calls={}
local identity="mmd/t/0123456789abcdef"
local p={GetGameMaterial=function(name) return {identity=name=="unseen" and "" or identity,state="cached",choices={},files={}} end,
    GameMaterialAction=function(...) calls[#calls+1]={...} return true end}
MaterialPipeline={ToPBR=p}
function Material(name) assert(name~="unseen") images=images+1 return name end
local helps={}
local function widget()
    local w={choices={}}
    for _,key in ipairs({"CheckBox","SetTall","AddItem","Dock","DockMargin","SetWrap","SetDark","SetWide","SetMaterial","SetSize","Center","SetTitle","SetName","MakePopup","Clear","ScrollToChild"}) do w[key]=function() end end
    function w:SetText(text) self.text=text end
    function w:Help(text) local h=widget() h.text=text helps[#helps+1]=h return h end
    function w:ComboBox() return widget() end
    function w:Button(label) local b=widget() buttons[label]=b return b end
    function w:Add() return widget() end
    function w:AddChoice(label,data) self.choices[#self.choices+1]={label,data} end
    function w:GetSelected() local c=self.choices[self.chosen or 1] return c and c[1],c and c[2] end
    function w:ChooseOptionID(i) self.chosen=i end
    return w
end
vgui={Create=widget}
local input=assert(io.open(arg[1],"rb")) local script=input:read("*a") input:close()
local begin=assert(script:find("-- BEGIN R12 IMPORTED GAME PBR PANEL",1,true))
local ending=assert(script:find("-- END R12 IMPORTED GAME PBR PANEL",begin,true))
assert(loadstring(script:sub(begin,ending-1),"packaged imported-game panel"))()
local rows=RTXGamePBRPanel.Materials(ent)
assert(#rows==3 and rows[1].base=="衣服.png")
assert(RTXGamePBRPanel.State(rows[1]).identity==RTXGamePBRPanel.State(rows[2]).identity)
assert(RTXGamePBRPanel.Action(rows[1],"maps",{normal="maps/n.png",packed="maps/m.png",emission="",layout=2}))
assert(calls[1][1]=="first" and calls[1][2]=="E:/model.pmx" and calls[1][3]=="衣服.png" and calls[1][4]=="maps" and calls[1][5]=="maps/n.png" and calls[1][8]==2)
local originalView=p.GetGameMaterial
p.GetGameMaterial=function() return {identity=identity,state="cached",choices={{normal="MAPS/N.PNG",layout=1}}} end
assert(not RTXGamePBRPanel.Action(rows[1],"maps",{normal="maps/n.png",layout=2}))
assert(#calls==1 and RTXGamePBRPanel.State(rows[1]).error=="Selected maps use another game layout.")
p.GetGameMaterial=originalView
RTXGamePBRPanel.Action(rows[2],"none") assert(calls[2][4]=="none")
mmdhl.library.entries.asset=nil
local absent=RTXGamePBRPanel.Materials(ent)[1]
assert(absent.source=="" and absent.base=="")
RTXGamePBRPanel.Action(absent,"automatic") assert(calls[3][2]=="" and calls[3][4]=="automatic")
RTXGamePBRPanel.Build(widget())
assert(images==2 and buttons["No game maps for this texture"] and buttons["Return to automatic"])
hooks.RTXImportedGamePBR()
assert(commands.rtx_topbr_game_editor)
commands.rtx_topbr_game_editor()
assert(RTXGamePBRPanel.Frame and images==4)
assert(#RTXGamePBRPanel.Targets()==1)
-- R13-M: a refused conversion's one-line reason (never "DDS publication failed") reaches the
-- selected material's status, with the native error state.
mmdhl.library.entries.asset={source="E:/model.pmx",info={materials={{base="衣服.png"},{base="copy.png"},{base="unseen.png"}}}}
local refusal="free disk space limit: 3 MiB free in C:\\game\\textures, 69 MiB needed (5592580 bytes for this map plus 64 MiB kept free)"
p.GetGameMaterial=function(name) return {identity=name=="unseen" and "" or identity,state="error",error=refusal,choices={},files={}} end
helps={}
local form=widget()
RTXGamePBRPanel.Build(form)
buttons["List looked-at character"].DoClick()
form:Think()
local shown=false
for _,h in ipairs(helps) do if type(h.text)=="string" and h.text:find(refusal,1,true) then shown=true end end
assert(shown,"refusal line not shown in the panel status")
p.GetGameMaterial=originalView
print("PASS imported game PBR panel: metadata, shared identities, family/files/none/automatic, missing source, drawn-only thumbnails, refusal reason shown")
