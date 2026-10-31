local scenario, source, other = arg[1], arg[2], arg[3]
function isstring(v) return type(v) == 'string' end
function isfunction(v) return type(v) == 'function' end
function istable(v) return type(v) == 'table' end
function IsValid(v) return type(v) == 'table' and v.valid ~= false end
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected)) end
if scenario == 'ame' then
    AdvMat = {NormalizeMaterial = function(v) return v:lower():gsub('^!', '') end}
    dofile(source)
    equal(AdvMat.MaterialDisplayName('Textures/Body', nil, 0), 'textures/body')
    local rig = {materials = {{path='mmd/a/skin',name='肌'}, {path='mmd/a/hair',name='Hair'}, {path='mmd/a/blank',name=''}}}
    local entity = {GetModel=function() return 'model.mdl' end}
    mmdhl = {GetRig=function() return rig end, props={RenderCache={abc={info={materials={{name='Paint'}}}}}}}
    equal(AdvMat.MaterialDisplayName('mmd/a/skin', entity, 0), '肌')
    equal(AdvMat.MaterialDisplayName('mmd/a/hair', entity, 0), 'Hair')
    equal(AdvMat.MaterialDisplayName('mmd/a/missing', entity, 1), 'mmd/a/missing')
    equal(AdvMat.MaterialDisplayName('mmd/a/blank', entity, 2), 'mmd/a/blank')
    equal(AdvMat.MaterialDisplayName('!mmdhl_prop_r2_abc_1g', nil, 0), 'Paint')
    dofile(other)
    local sourceTab, rtxTab, graphTab = {}, {}, {}
    local editor = setmetatable({Materials={'mmd/a/skin','mmd/a/hair'},MaterialSlots={[0]=4,[1]=7},
        MaterialSlotGroups={[0]={4,6},[1]={7}},TargetEntity=entity,Selected=1,SourceDisplaySelected=0,
        SourceSheet={Tab=sourceTab},MaterialLines={[0]={},[1]={}},Working={[1]={dirty='rtx'}},
        SourceWorking={[4]={dirty='source'}},active=sourceTab}, {__index=PANEL})
    editor.ActiveMaterial = {SetText=function(_,v) editor.title=v end,SetTooltip=function(_,v) editor.path=v end}
    editor.SourcePanel = {SetMaterialSelection=function(_,index,material,group)
        editor.sourceRow=index editor.sourcePath=material editor.group=group
    end}
    editor.MaterialList = {SelectItem=function(_,line) editor.line=line end}
    function editor:IsSourceTabActive() return self.active == sourceTab end
    function editor:UpdateActionMode() end
    function editor:CanonicalSlot(index) return index == 1 and 0 or index end
    function editor:SelectMaterial(index) self.Selected=index end
    local rtxWorking, sourceWorking = editor.Working, editor.SourceWorking
    editor:OnWorkspaceChanged(rtxTab,sourceTab)
    equal(editor.sourceRow,1) equal(editor.sourcePath,'mmd/a/hair') equal(editor.group[1],7)
    equal(editor.title,'Hair') equal(editor.path,'mmd/a/hair')
    editor.active=rtxTab editor:OnWorkspaceChanged(sourceTab,rtxTab)
    equal(editor.Selected,0) equal(editor.line,editor.MaterialLines[0])
    function editor:CanonicalSlot(index) return index end
    editor.Selected=1 editor.SourceDisplaySelected=0
    editor.active=graphTab editor:OnWorkspaceChanged(rtxTab,graphTab)
    equal(editor.Selected,1)
    equal(editor.Working,rtxWorking) equal(editor.SourceWorking,sourceWorking)
elseif scenario == 'normals' then
    local on, now, tick, callback = false, 0
    local calls, tracks, captured = {}, {}, {}
    function CreateClientConVar() return {GetBool=function() return on end} end
    function RealTime() return now end
    hook={Add=function(_,_,fn) tick=fn end}
    cvars={AddChangeCallback=function(_,fn) callback=fn end}
    local actor={GetMaterial=function() return '' end,GetMaterials=function() return {'mmd/a/skin'} end,
        GetSubMaterial=function() return '' end}
    local preview={MMDHLEditorPreview=true}
    local hands={MMDHLHands=true}
    local actors={actor,preview,hands}
    local props={}
    mmdhl={Entities=function() return actors end,props={RenderCache={a={materials={{GetName=function() return 'prop' end}}}}}}
    ents={FindByClass=function() return props end}
    local fail=false
    RemixConfig={SetConfigVariable=function(key,value)
        equal(key,'rtx.gmod.importedModelSmoothNormalTextures')
        calls[#calls+1]=value return not fail
    end}
    RemixMaterial={TrackMaterial=function(name) tracks[name]=(tracks[name] or 0)+1 end,
        GetAllTextureHashes=function(name) return captured[name] or {} end}
    dofile(source)
    -- Clear owned state on a fresh Lua state/map, even when the saved checkbox is off.
    tick() equal(#calls,1) equal(calls[1],'')
    on=true callback() tick() equal(#calls,1)
    captured['mmd/a/skin']={'0xA','0xa','0x0','bad'} now=1 tick()
    equal(calls[#calls],'0xa') equal(tracks['mmd/a/skin'],1)
    props={{GetAssetID=function() return 'a' end}} captured.prop={'0xB'} now=2 tick()
    equal(calls[#calls],'0xa, 0xb')
    actor.GetSubMaterial=function() return '!override' end captured.override={'0xC'} now=3 tick()
    equal(calls[#calls],'0xb, 0xc') equal(tracks.override,nil)
    on=false callback() tick() equal(calls[#calls],'')
    on=true fail=true callback() tick() local count=#calls
    fail=false now=4 tick() equal(#calls,count+1) equal(calls[#calls],'0xb, 0xc')
    actors={} props={} now=5 tick() equal(calls[#calls],'')
    RemixMaterial=nil now=6 tick()
elseif scenario == 'motion' then
    TOP=1
    local tabs, callbacks, phrases, children = {}, {}, {}, {}
    local translated=false
    include=function() return {L=function(text) return translated and 'translated:'..text or text end} end
    language={Add=function(key,value) phrases[key]=value end}
    spawnmenu={AddCreationTab=function(key,build,icon,order,tooltip) tabs[key]={build=build,Tooltip=tooltip} end,
        GetCreationTabs=function() return tabs end}
    cvars={AddChangeCallback=function(key,fn) callbacks[key]=fn end}
    local function panel(kind)
        local p={kind=kind}
        for _,name in ipairs({'Dock','DockPadding','SetWrap','SetAutoStretchVertical','SetDark','DockMargin','SetTall'}) do p[name]=function() end end
        p.SetText=function(self,text) self.text=text end
        p.SetEnabled=function(self,value) self.enabled=value end
        p.Add=function(_,childKind) local child=panel(childKind) children[#children+1]=child return child end
        return p
    end
    vgui={Create=panel}
    dofile(source)
    local tab=tabs['#nativeloader.motion_importer'] assert(tab)
    local opens, closed=0,0
    tab.build()
    local button=children[2] button:Think() equal(button.enabled,false) equal(opens,0)
    MMDVMDNPC={OpenMotionManager=function() opens=opens+1 end}
    g_SpawnMenu={Close=function() closed=closed+1 end}
    button:Think() equal(button.enabled,true) equal(opens,0)
    button:DoClick() equal(opens,1) equal(closed,1)
    MMDVMDNPC=nil button:DoClick() equal(opens,1)
    translated=true callbacks.nativeloader_language()
    equal(phrases['nativeloader.motion_importer'],'translated:Motion importer')
    assert(tab.Tooltip:find('translated:',1,true))
else error('unknown scenario') end
print('PASS '..scenario)
