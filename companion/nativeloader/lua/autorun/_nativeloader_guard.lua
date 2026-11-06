-- NATIVELOADER_RENDER_GUARD_V2
-- Verified early startup installs this after stock includes/init.lua. A local RTX start without
-- that view installs it from this autorun instead, and the separate verified multiplayer bootstrap
-- route may run after community/server autoruns. Self-contained and idempotent.
-- Lua containment is not native SEH/GPU fault recovery.
if SERVER or MENU_DLL then return end
local environment = getfenv(1)
local early = __NATIVELOADER_RTX_GUARD_EARLY == true
local verifiedMultiplayer = environment ~= _G and rawget(environment, "NATIVELOADER_VERIFIED_MULTIPLAYER") == true
if NativeLoaderRenderGuard and NativeLoaderRenderGuard.version == 2 then return end
-- A listen host serves this file and its generated initializer to remote clients too. Outside the
-- private multiplayer environment, install only where this machine's own loader activated RTX in
-- this start. It rewrites status.json at every start, before any Lua runs, but that file stays after
-- the game exits, and a start through an off switch (-nonativeloader, NATIVE_LOADER_DISABLE=1, the
-- native-loader/disable file) never runs the loader: its "active" can be an earlier start's. Loader
-- 0.14.0 and later therefore also hold native-loader/rtx-session.txt open for the life of an RTX
-- start; Windows deletes it when the game exits, however it exits (R19, proxy F-02). An older
-- loader holds none, and its report alone decides, as before.
local sessionMarker, markingLoader = "native-loader/rtx-session.txt", {0, 14, 0}
local function markerHeld()
    if not file then return false end
    if file.Exists then
        local ok, found = pcall(file.Exists, sessionMarker, "DATA")
        if ok and found == true then return true end
    end
    -- A directory listing never opens the file, whatever the engine's existence check does.
    if file.Find then
        local ok, found = pcall(file.Find, sessionMarker, "DATA")
        if ok and type(found) == "table" then
            for _, name in ipairs(found) do
                if type(name) == "string" and name:lower() == "rtx-session.txt" then return true end
            end
        end
    end
    return false
end
local function marks(text)
    local version = {text:match('"loader_version":"(%d+)%.(%d+)%.(%d+)')}
    if #version ~= 3 then return false end
    for i = 1, 3 do
        local part = tonumber(version[i])
        if part ~= markingLoader[i] then return part > markingLoader[i] end
    end
    return true
end
local function localRTXStart()
    if not (file and file.Read) then return false end
    local ok, text = pcall(file.Read, "native-loader/status.json", "DATA")
    -- No report (it is written last, and can fail): the marker alone shows this start's RTX.
    if not ok or type(text) ~= "string" or text:find('"schema":1', 1, true) == nil then return markerHeld() end
    if text:find('\n"activation":{"outcome":"active"', 1, true) == nil then return false end
    return not marks(text) or markerHeld()
end
local installation
if verifiedMultiplayer then installation = "verified multiplayer bootstrap"
elseif localRTXStart() then installation = early and "early" or "autorun"
else return end
local late = installation == "verified multiplayer bootstrap"
-- Verified multiplayer chunks receive a scoped hook proxy. Change the real
-- hook table, not a field written only into that chunk's private proxy.
local hook = _G.hook

local enabled = CreateClientConVar("nativeloader_guard", "1", true, false,
    "Keep incompatible add-on rendering from undoing the RTX session")
local playerMeta, convarMeta = FindMetaTable("Player"), FindMetaTable("ConVar")
-- The native getter: the motion-blur read compatibility below wraps ConVar:GetBool.
local getBool = convarMeta and convarMeta.GetBool
local state = {version = 2, installation = installation, policy = "inert screen-space shaders under RTX",
    blocked = {}, errors = {}, cleanup_errors = {}, limitations = {
    "Lua errors only: native faults, GPU failures and infinite loops are not caught",
    "Unknown native state and partially built meshes cannot be universally restored",
    "Later API replacements or unwrapped native aliases can bypass these guards"}}
NativeLoaderRenderGuard = state
local function active()
    local on
    if getBool then on = getBool(enabled) else on = enabled:GetBool() end
    state.enabled = on
    return on
end
state.enabled_at_install = active()
local function pack(...) return {n = select("#", ...), ...} end
local getinfo, traceback, pcall, xpcall, unpack = debug.getinfo, debug.traceback, pcall, xpcall, unpack
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function integer(n) return finite(n) and n % 1 == 0 end
-- Native size arguments are truncated toward zero, so ScrW() / 3 and similar sizes are valid.
local function whole(n) if finite(n) then return n < 0 and math.ceil(n) or math.floor(n) end end
local function virtual(s)
    s = tostring(s or "?"):gsub("\\", "/"):gsub("^@", "")
    local pos = s:find("/lua/", 1, true)
    if pos then s = s:sub(pos + 1) end
    if s:sub(1, 4) == "lua/" then return s:sub(1, 180) end
    if s:find("^[%a]:") or s:sub(1, 1) == "/" then return "<external Lua>" end
    if s:sub(1, 1) == "[" or s:sub(1, 1) == "=" then return "<dynamic Lua>" end
    return s:sub(1, 180)
end
local function location(info)
    return virtual(info and info.source) .. ":" .. tostring(info and info.currentline or 0)
end
local function caller() return location(getinfo(3, "Sl")) end
local function functionSource(fn)
    local info = type(fn) == "function" and getinfo(fn, "S")
    return virtual(info and info.source)
end
local guardSource = getinfo(1, "S").source
-- The first caller outside this guard and native frames, resolved only when a call is refused.
local function externalCaller()
    for level = 3, 32 do
        local info = getinfo(level, "Sl")
        if not info then break end
        if info.what ~= "C" and info.source ~= guardSource then return location(info) end
    end
    return "<unknown>"
end
local told, reportCounts = {}, {}
local function report(kind, api, reason, source)
    source = virtual(source)
    local key = kind .. "|" .. api .. "|" .. source .. (kind == "blocked" and "" or "|" .. reason)
    local count = reportCounts[kind] or 0
    -- Each category has its own cap, so a flood of refusals cannot hide later error records.
    if told[key] or count >= 128 then return end
    told[key], reportCounts[kind] = true, count + 1
    local list = state[kind]
    list[#list + 1] = {api = api, reason = reason, source = source}
    if MsgN then MsgN("[nativeloader] RTX guard: " .. api .. ": " .. reason .. " (" .. source .. ")") end
end
local function reject(api, reason, source)
    report("blocked", api, reason, source or externalCaller())
    return false
end
local function rejectNul(api, value, source)
    if type(value) == "string" and value:find("%z") then
        reject(api, "embedded NUL in native string", source)
        return true
    end
end

-- Keep the existing pin exemptions and motion-blur read compatibility.
local pinned = {}
local session = file and file.Read and file.Read("cfg/nativeloader_session.cfg", "MOD") or ""
for line in session:gmatch("[^\r\n]+") do
    local name, value = line:match('^%s*([%w_%.]+)%s+"([^"]*)"')
    if not name then name, value = line:match("^%s*([%w_%.]+)%s+([^%s;]+)") end
    if name then pinned[name:lower()] = value end
end
pinned.mat_motion_blur_enabled = pinned.mat_motion_blur_enabled or "0"
-- r_forcehwlight 1 sends every model Source skins on the GPU through fixed-function hardware
-- skinning, which gives Remix no bones: player models and other vanilla characters draw in bind
-- pose around the pelvis (R3-016: Modern House RTX; R8: a Backrooms map add-on). No Lua may set it.
pinned.r_forcehwlight = "0"
for _, name in ipairs({"mat_dxlevel", "mat_hdr_level"}) do
    local value = GetConVar(name)
    if value then pinned[name] = pinned[name] or value:GetString() end
end
-- Video/depth allocations cannot be changed safely during this D3D9 session.
for _, name in ipairs({"r_flashlightdepthres", "mat_antialias", "mat_aaquality", "mat_disable_d3d9ex"}) do
    local value = GetConVar(name)
    if value then pinned[name] = pinned[name] or value:GetString() end
end
local function exempt(s)
    return s:find("remixbinary", 1, true) or s:find("remixlua", 1, true) or s:find("nativeloader", 1, true)
end
local criticalPins = {mat_dxlevel = true, mat_hdr_level = true, r_flashlightdepthres = true,
    mat_antialias = true, mat_aaquality = true, mat_disable_d3d9ex = true, r_forcehwlight = true}
-- RTX map remasters (lua/autorun/<name>_rtx.lua and lua/<name>_rtx/, such as the Backrooms' br_rtx.lua)
-- scope the engine's visibility to their own maps: gm_br_complex draws at about 13 ms with r_novis 0 and
-- the fixes' PAS patch, but ran at 9 FPS with the session's r_novis 1 (R8 field check). They may set that
-- pin only; critical pins stay enforced.
local function remaster(source)
    return source:match("^lua/autorun/[%w_]+_rtx%.lua") ~= nil or source:match("^lua/[%w_]+_rtx/") ~= nil
end
local function allowPin(name, value, source, query)
    if not active() then return true end
    local key = tostring(name or ""):lower()
    if key == "r_novis" and remaster(source) then return true end
    local csm = source:find("lua/realcsm/", 1, true) == 1 or source:find("lua/entities/edit_csm/", 1, true) == 1
        or source:find("lua/autorun/realcsm_client.lua", 1, true) == 1
    if csm and value ~= nil and (key == "r_ambientlightingonly" or key == "r_lightstyle" or key == "r_radiosity"
        or key == "r_shadows_gamecontrol" or key == "r_shadowrendertotexture" or key == "r_shadowdist" or key == "r_farz") then
        report("blocked", key, "Real CSM raster world-lighting settings are inert under RTX", source) return false
    end
    if source:find("lua/autorun/client/cl_bloom_config.lua", 1, true)
        and (key == "mat_bloomscale" or key == "mat_bloom_scalefactor_scalar") then
        report("blocked", key, "Quick Bloom raster bloom settings are inert under RTX", source) return false
    end
    local want = pinned[key]
    if want == nil or (exempt(source) and not criticalPins[key]) or (query and value == nil) then return true end
    if type(value) == "boolean" then value = value and "1" or "0" end
    local a, b = tonumber(value), tonumber(want)
    if tostring(value) == want or (a ~= nil and b ~= nil and finite(a) and a == b) then return true end
    report("blocked", tostring(name), "kept session value " .. want, source)
    return false
end
local function tokens(text)
    local out, part, quoted = {}, {}, false
    local function finish() if #part > 0 then out[#out + 1] = table.concat(part) part = {} end end
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == '"' then quoted = not quoted
        elseif not quoted and ch:match("%s") then finish()
        else part[#part + 1] = ch end
    end
    finish()
    return out
end
local function segments(text)
    local out, part, quoted, comment = {}, {}, false, false
    for i = 1, #text do
        local ch = text:sub(i, i)
        if comment then
            if ch == "\n" or ch == "\r" then comment = false out[#out + 1] = table.concat(part) part = {} end
        elseif not quoted and ch == "/" and text:sub(i + 1, i + 1) == "/" then comment = true
        elseif ch == '"' then quoted = not quoted part[#part + 1] = ch
        elseif not quoted and (ch == ";" or ch == "\n" or ch == "\r") then out[#out + 1] = table.concat(part) part = {}
        else part[#part + 1] = ch end
    end
    out[#out + 1] = table.concat(part)
    return out
end
local indirect = {toggle = true, incrementvar = true, multvar = true, cycle = true}
local unsafeCommands = {mat_setvideomode = true, mat_restart = true, vid_restart = true}
local checkCommands
local function checkTokens(args, source, depth)
    local name = tostring(args[1] or ""):lower()
    if unsafeCommands[name] or name:match("^mat_reload") then
        report("blocked", name, "renderer reload/video transitions require an RTX restart", source) return false
    end
    local target = tostring(args[2] or ""):lower()
    if indirect[name] and pinned[target] and (criticalPins[target] or not exempt(source)) then
        report("blocked", name, "indirect write to a session setting", source) return false
    end
    if (name == "alias" or name == "bind") and args[3] then
        if depth >= 4 then report("blocked", name, "nested command limit", source) return false end
        if not checkCommands(table.concat(args, " ", 3), source, depth + 1) then return false end
    end
    return allowPin(name, args[2], source, true)
end
checkCommands = function(text, source, depth)
    for _, command in ipairs(segments(text)) do
        if not checkTokens(tokens(command), source, depth or 0) then return false end
    end
    return true
end
if RunConsoleCommand then
    local original = RunConsoleCommand
    RunConsoleCommand = function(name, ...)
        if not active() then return original(name, ...) end
        local source = caller()
        if rejectNul("RunConsoleCommand", name, source) then return end
        for i = 1, select("#", ...) do if rejectNul("RunConsoleCommand", select(i, ...), source) then return end end
        if checkTokens({name, ...}, source, 0) then return original(name, ...) end
    end
end
if playerMeta and playerMeta.ConCommand then
    local original = playerMeta.ConCommand
    playerMeta.ConCommand = function(self, command, ...)
        if not active() then return original(self, command, ...) end
        local source = caller()
        if rejectNul("Player.ConCommand", command, source) then return end
        if type(command) ~= "string" or checkCommands(command, source, 0) then return original(self, command, ...) end
    end
end
if game and game.ConsoleCommand then
    local original = game.ConsoleCommand
    game.ConsoleCommand = function(command, ...)
        if not active() then return original(command, ...) end
        local source = caller()
        if rejectNul("game.ConsoleCommand", command, source) then return end
        if type(command) ~= "string" or checkCommands(command, source, 0) then return original(command, ...) end
    end
end
if convarMeta then
    local getName = convarMeta.GetName
    for _, method in ipairs({"SetInt", "SetFloat", "SetBool", "SetString"}) do
        local original = convarMeta[method]
        if original and getName then
            convarMeta[method] = function(self, value, ...)
                -- pcall(cv.SetString, cv, value) puts a native frame first; name the Lua caller instead.
                local source = caller()
                if source:sub(1, 13) == "<dynamic Lua>" then source = externalCaller() end
                if allowPin(getName(self), value, source, false) then return original(self, value, ...) end
            end
        end
    end
    if pinned.mat_motion_blur_enabled == "0" then
        local blur = GetConVar("mat_motion_blur_enabled")
        for method, on in pairs({GetInt = 1, GetFloat = 1, GetBool = true, GetString = "1"}) do
            local original = convarMeta[method]
            if original then
                convarMeta[method] = function(self, ...)
                    if rawequal(self, blur) and active() then return on end
                    return original(self, ...)
                end
            end
        end
    end
end

-- The policy is self-contained because the verified early initializer embeds this file alone.
local policy = {inertTextures = setmetatable({}, {__mode = "k"}), inertMaterials = setmetatable({}, {__mode = "k"})}
do
    local sources = {
        ["lua/autorun/!!shaderlib.lua"] = true,
        ["lua/autorun/client/worldpos.lua"] = true,
        ["lua/autorun/client/depthbuffer.lua"] = true,
        ["lua/autorun/client/bumps_building.lua"] = true,
        ["lua/autorun/client/lightmaps_building.lua"] = true,
        ["lua/autorun/client/lut_writing.lua"] = true,
        ["lua/autorun/client/stencil_masks.lua"] = true,
        ["lua/autorun/client/translucent_crutch.lua"] = true,
        ["lua/autorun/client/fixes_for_workshop_addons.lua"] = true,
        ["lua/postprocess/shader_lib.lua"] = true,
        ["lua/postprocess/fxaa.lua"] = true,
        ["lua/postprocess/ssdo.lua"] = true,
        ["lua/postprocess/pp_ssr.lua"] = true,
    }
    function policy.effect(source)
        source = source:lower():gsub(":%d+$", "")
        return sources[source] or source:find("lua/lifemod/render/modules/", 1, true) == 1
    end
    function policy.csm(source)
        source = source:lower()
        return source:find("lua/realcsm/", 1, true) == 1 or source:find("lua/entities/edit_csm/", 1, true) == 1
    end
    -- Initialization still defines the add-ons' API and receives real engine-backed fallbacks.
    -- Rendering/reconstruction/world-mesh callbacks are inert even through cached hook.Call.
    function policy.skipCallback(fn, event)
        if event == "Initialize" or event == "InitReconstruction" or event == "InitPostReconstruction"
            or event == "OnScreenSizeChanged" or event == "OnReloaded" or event == "ShutDown" then return false end
        if not policy.effect(functionSource(fn)) then return false end
        reject("hook." .. tostring(event), "screen-space shader effect is inert under RTX", functionSource(fn))
        return true
    end
    local wrapperPaths = { ["lua/autorun/!!projected_texture_wrapper.lua"] = true,
        ["lua/autorun/!!dynamic_light_wrapper.lua"] = true }
    local function wrapper(source) return wrapperPaths[source:gsub(":%d+$", "")] end
    local function copy(tbl) local out = {} for k, v in pairs(tbl) do out[k] = v end return out end
    -- GShader repeatedly edits the shared native PT __index, nesting it once per created lamp.
    -- Its dlight wrapper also replaces native userdata metatables. Keep those edits in Lua copies.
    local findMeta = FindMetaTable
    FindMetaTable = function(name, ...)
        local result = findMeta(name, ...)
        if active() and wrapper(caller()) and type(result) == "table" then
            reject("FindMetaTable", "native light metatable edits isolated", caller())
            return copy(result)
        end
        return result
    end
    local getMeta, setMeta = debug.getmetatable, debug.setmetatable
    local privateMetas = setmetatable({}, {__mode = "k"})
    debug.getmetatable = function(obj)
        local result = getMeta(obj)
        if active() and wrapper(caller()) and type(result) == "table" then return privateMetas[obj] or copy(result) end
        return result
    end
    debug.setmetatable = function(obj, meta)
        if active() and wrapper(caller()) then
            reject("debug.setmetatable", "native light metatable replacement ignored", caller())
            privateMetas[obj] = meta
            return obj
        end
        return setMeta(obj, meta)
    end
end
-- Exact bundled virtual paths, checked against the indexed package inputs/companion by tests.
-- Source labels omit the add-on directory. This is a compatibility exemption, not authentication:
-- a colliding file or forged chunk label can bypass these material filters (ADR 0086).
do
    local bundled = {}
    for path in ([[
lua/advanced_bodygroup_tool/cl_i18n.lua
lua/advanced_bodygroup_tool/cl_uv_hide.lua
lua/advanced_bodygroup_tool/cl_vertex_keep_editor.lua
lua/advmat/cl_05_i18n.lua
lua/advmat/cl_19_help_i18n.lua
lua/advmat/cl_20_help.lua
lua/advmat/cl_23_backend.lua
lua/advmat/cl_27_rtx_bridge.lua
lua/advmat/cl_28_rtx_enhance.lua
lua/advmat/cl_29_rtx_normals.lua
lua/advmat/cl_30_theme.lua
lua/advmat/cl_31_windowux.lua
lua/advmat/cl_40_store.lua
lua/advmat/cl_41_rtx_store.lua
lua/advmat/cl_50_apply.lua
lua/advmat/cl_55_normalgen.lua
lua/advmat/cl_56_texops.lua
lua/advmat/cl_57_surfacegen.lua
lua/advmat/cl_58_meshuv.lua
lua/advmat/cl_59_assets.lua
lua/advmat/cl_60_texpicker.lua
lua/advmat/cl_61_import.lua
lua/advmat/cl_65_rows.lua
lua/advmat/cl_67_gendialog.lua
lua/advmat/cl_68_surfacedialog.lua
lua/advmat/cl_70_ui.lua
lua/advmat/cl_71_rtx_source.lua
lua/advmat/cl_72_canvas.lua
lua/advmat/cl_73_modelview.lua
lua/advmat/cl_74_texeditor.lua
lua/advmat/cl_75_rtx_nodes.lua
lua/advmat/cl_76_rtx_editor.lua
lua/advmat/cl_78_vmtexport.lua
lua/advmat/cl_80_browser.lua
lua/advmat/cl_88_dispatch.lua
lua/advmat/cl_90_probe.lua
lua/advmat/sh_00_config.lua
lua/advmat/sh_10_util.lua
lua/advmat/sh_15_mmd.lua
lua/advmat/sh_20_net.lua
lua/advmat/sh_25_vmt.lua
lua/advmat/sh_30_shaderdb.lua
lua/advmat/sh_31_shaderdb_ext.lua
lua/advmat/sh_35_matname.lua
lua/advmat/sh_36_rtx_schema.lua
lua/advmat/sh_40_gen.lua
lua/advmat/sh_41_sel.lua
lua/advmat/sh_42_gen_normal.lua
lua/advmat/sh_43_texedit.lua
lua/advmat/sh_44_gen_surface.lua
lua/advmat/sh_45_assets.lua
lua/advmat/sh_50_finalise.lua
lua/advmat/sv_29_assets.lua
lua/advmat/sv_30_store.lua
lua/advmat/sv_31_rtx_store.lua
lua/advmat/sv_32_rtx_tool.lua
lua/advmat/sv_40_apply.lua
lua/autorun/_nativeloader_effect_categories.lua
lua/autorun/_nativeloader_guard.lua
lua/autorun/advanced_bodygroup_tool.lua
lua/autorun/advmat_loader.lua
lua/autorun/bullet_break_simulator_loader.lua
lua/autorun/cl_rtx.lua
lua/autorun/client/cl_remix_portals.lua
lua/autorun/client/cl_render_core.lua
lua/autorun/client/hl2rtx_model_compat_viewmodels.lua
lua/autorun/client/nativeloader.lua
lua/autorun/client/nativeloader_eye_whites.lua
lua/autorun/client/nativeloader_guide.lua
lua/autorun/client/nativeloader_imported_normals.lua
lua/autorun/client/nativeloader_imported_parts.lua
lua/autorun/client/nativeloader_menu.lua
lua/autorun/client/nativeloader_mmd_alpha.lua
lua/autorun/client/nativeloader_model_layers.lua
lua/autorun/client/nativeloader_motion_tab.lua
lua/autorun/client/nativeloader_toolgun.lua
lua/autorun/client/nativeloader_vram.lua
lua/autorun/client/removehalo.lua
lua/autorun/client/rtx_agent.lua
lua/autorun/client/rtx_debug.lua
lua/autorun/matdebug.lua
lua/autorun/mmd_vmd_npc.lua
lua/autorun/mmdhl.lua
lua/autorun/nativeloader_defaults.lua
lua/autorun/nativeloader_i18n.lua
lua/autorun/nativeloader_sky.lua
lua/autorun/nlglass.lua
lua/autorun/poolrooms_rtx.lua
lua/autorun/rtx_water.lua
lua/autorun/server/hl2rtx_model_compat.lua
lua/autorun/server/sv_portals_pvs.lua
lua/autorun/server/sv_prop_teleport.lua
lua/autorun/sh_detours.lua
lua/autorun/sh_player_teleport.lua
lua/autorun/sh_rtx.lua
lua/autorun/sv_rtx.lua
lua/autorun/tmc.lua
lua/bullet_break_simulator/cl_10_i18n.lua
lua/bullet_break_simulator/cl_20_filters.lua
lua/bullet_break_simulator/cl_21_mdl_bodyparts.lua
lua/bullet_break_simulator/cl_22_shape.lua
lua/bullet_break_simulator/cl_25_profiler.lua
lua/bullet_break_simulator/cl_29_mesh_preparation.lua
lua/bullet_break_simulator/cl_30_overlay.lua
lua/bullet_break_simulator/cl_32_mesh_persistence.lua
lua/bullet_break_simulator/cl_39_material_safety.lua
lua/bullet_break_simulator/cl_40_damage.lua
lua/bullet_break_simulator/cl_90_settings.lua
lua/bullet_break_simulator/sh_00_config.lua
lua/bullet_break_simulator/sh_10_network.lua
lua/bullet_break_simulator/sv_20_hits.lua
lua/entities/gmod_lamp.lua
lua/entities/gmod_light.lua
lua/entities/mmdhl_attach_link.lua
lua/entities/mmdhl_prop/cl_init.lua
lua/entities/mmdhl_prop/init.lua
lua/entities/mmdhl_prop/shared.lua
lua/entities/mmdhl_ragdoll/cl_init.lua
lua/entities/mmdhl_ragdoll/init.lua
lua/entities/mmdhl_ragdoll/shared.lua
lua/entities/mmdhl_ragdoll/tool_api.lua
lua/entities/nlglass_pane/cl_init.lua
lua/entities/nlglass_pane/init.lua
lua/entities/nlglass_pane/shared.lua
lua/entities/remix_rt_light/cl_init.lua
lua/entities/remix_rt_light/init.lua
lua/entities/remix_rt_light/shared.lua
lua/entities/remix_sky_editor/cl_init.lua
lua/entities/remix_sky_editor/init.lua
lua/entities/remix_sky_editor/shared.lua
lua/entities/rtx_pseudoplayer.lua
lua/entities/rtx_pseudoweapon.lua
lua/entities/seamless_portal/cl_init.lua
lua/entities/seamless_portal/init.lua
lua/entities/seamless_portal/sh_init.lua
lua/includes/modules/niknaks.lua
lua/mmd_vmd_npc/cl_camera.lua
lua/mmd_vmd_npc/cl_flashlight.lua
lua/mmd_vmd_npc/cl_import_bake.lua
lua/mmd_vmd_npc/cl_import_data.lua
lua/mmd_vmd_npc/cl_importer.lua
lua/mmd_vmd_npc/cl_menu.lua
lua/mmd_vmd_npc/cl_radial.lua
lua/mmd_vmd_npc/sh_core.lua
lua/mmd_vmd_npc/sv_cache.lua
lua/mmd_vmd_npc/sv_commands.lua
lua/mmdhl/actors.lua
lua/mmdhl/bodygroups.lua
lua/mmdhl/bone_mapper.lua
lua/mmdhl/bone_mapper_rules.lua
lua/mmdhl/bone_mapper_ui.lua
lua/mmdhl/carrier.lua
lua/mmdhl/client.lua
lua/mmdhl/client_ragdolls.lua
lua/mmdhl/collision_editor.lua
lua/mmdhl/compat.lua
lua/mmdhl/compatibility_policy.lua
lua/mmdhl/debug.lua
lua/mmdhl/entity_editor.lua
lua/mmdhl/faceposer.lua
lua/mmdhl/file_access.lua
lua/mmdhl/first_person.lua
lua/mmdhl/i18n.lua
lua/mmdhl/installation.lua
lua/mmdhl/installation_ui.lua
lua/mmdhl/instances.lua
lua/mmdhl/library.lua
lua/mmdhl/materials.lua
lua/mmdhl/menu.lua
lua/mmdhl/names.lua
lua/mmdhl/native_policy.lua
lua/mmdhl/native_render.lua
lua/mmdhl/native_tools.lua
lua/mmdhl/performance.lua
lua/mmdhl/persistence.lua
lua/mmdhl/physics_editor.lua
lua/mmdhl/physics_editor_ui.lua
lua/mmdhl/physics_lod.lua
lua/mmdhl/physics_profile.lua
lua/mmdhl/physics_reset.lua
lua/mmdhl/physics_settings.lua
lua/mmdhl/player_copies.lua
lua/mmdhl/props/collision.lua
lua/mmdhl/props/editor.lua
lua/mmdhl/props/library.lua
lua/mmdhl/props/render.lua
lua/mmdhl/props/server.lua
lua/mmdhl/props/shared.lua
lua/mmdhl/props/tool.lua
lua/mmdhl/scene_sharing.lua
lua/mmdhl/secondary_backend.lua
lua/mmdhl/secondary_collision.lua
lua/mmdhl/secondary_water.lua
lua/mmdhl/server.lua
lua/mmdhl/server_settings.lua
lua/mmdhl/settings.lua
lua/mmdhl/sharing.lua
lua/mmdhl/terms.lua
lua/mmdhl/ui.lua
lua/mmdhl/workshop.lua
lua/mmdhl/workshop_export.lua
lua/nativeloader/classic_defaults.lua
lua/nativeloader/eye_white_names.lua
lua/nativeloader/eye_white_vtf.lua
lua/nativeloader/guide_pages.lua
lua/nativeloader/i18n.lua
lua/nativeloader/painted_shadows.lua
lua/nativeloader/sky_model.lua
lua/nativeloader/solid_hair.lua
lua/nativeloader/weather_presets.lua
lua/niknaks/framework/sh_localbsp.lua
lua/niknaks/modules/sh_bignumber.lua
lua/niknaks/modules/sh_bitbuffer.lua
lua/niknaks/modules/sh_bsp_brushes.lua
lua/niknaks/modules/sh_bsp_entities.lua
lua/niknaks/modules/sh_bsp_faces.lua
lua/niknaks/modules/sh_bsp_leafs.lua
lua/niknaks/modules/sh_bsp_module.lua
lua/niknaks/modules/sh_bsp_pvspas.lua
lua/niknaks/modules/sh_bsp_staticprops.lua
lua/niknaks/modules/sh_bsp_trace.lua
lua/niknaks/modules/sh_bsp_worldlights.lua
lua/niknaks/modules/sh_color_extended.lua
lua/niknaks/modules/sh_datapackage.lua
lua/niknaks/modules/sh_datetime.lua
lua/niknaks/modules/sh_enums.lua
lua/niknaks/modules/sh_file_extended.lua
lua/niknaks/modules/sh_hooks.lua
lua/niknaks/modules/sh_linq_module.lua
lua/niknaks/modules/sh_model_extended.lua
lua/niknaks/modules/sh_randomizer.lua
lua/niknaks/modules/sh_sound_module.lua
lua/niknaks/modules/sh_timedelta.lua
lua/niknaks/modules/sh_util_extended.lua
lua/niknaks/submodules/ai/sh_file.lua
lua/niknaks/submodules/ai/sh_map.lua
lua/niknaks/submodules/ai/sh_node.lua
lua/niknaks/submodules/ai/sh_pathfinder.lua
lua/niknaks/submodules/sh_submodules.lua
lua/nlglass/client.lua
lua/nlglass/config.lua
lua/nlglass/damage.lua
lua/nlglass/debris.lua
lua/nlglass/debris_batches.lua
lua/nlglass/debris_bullets.lua
lua/nlglass/debris_detail.lua
lua/nlglass/debris_draw.lua
lua/nlglass/debris_expiry.lua
lua/nlglass/debris_fallback.lua
lua/nlglass/debris_melee.lua
lua/nlglass/debris_mesh.lua
lua/nlglass/debris_scene.lua
lua/nlglass/debris_settings.lua
lua/nlglass/debris_view.lua
lua/nlglass/fracture.lua
lua/nlglass/geometry.lua
lua/nlglass/i18n.lua
lua/nlglass/i18n_data.lua
lua/nlglass/menu.lua
lua/nlglass/protocol.lua
lua/nlglass/server.lua
lua/nlglass/world.lua
lua/patcher/addons/cl_mwbase.lua
lua/patcher/cl_init.lua
lua/patcher/cl_intercepts.lua
lua/patcher/sh_core.lua
lua/patcher/tests/cl_mwbase_dependency_tests.lua
lua/patcher/tests/cl_patcher_core_tests.lua
lua/patcher/tests/cl_patcher_intercepts_tests.lua
lua/patcher/tests/cl_patcher_loader_tests.lua
lua/poolrooms_rtx/cl_lights_data.lua
lua/poolrooms_rtx/cl_main.lua
lua/poolrooms_rtx/sh_config.lua
lua/remixlua/cl/cl_fix_bft_materials.lua
lua/remixlua/cl/cl_fix_pbr_materials.lua
lua/remixlua/cl/cl_fix_refract_materials.lua
lua/remixlua/cl/cl_fix_solid_color_materials.lua
lua/remixlua/cl/cl_map_fixes.lua
lua/remixlua/cl/cl_map_markers.lua
lua/remixlua/cl/cl_material_inspector.lua
lua/remixlua/cl/cl_material_pipeline.lua
lua/remixlua/cl/cl_nonapi_flashlight.lua
lua/remixlua/cl/cl_remove_detail_textures.lua
lua/remixlua/cl/cl_rtx_light_updater.lua
lua/remixlua/cl/cl_rtx_material_fixer.lua
lua/remixlua/cl/cl_rtx_misc.lua
lua/remixlua/cl/cl_rtx_settings.lua
lua/remixlua/cl/cl_rtx_topbr_conversion.lua
lua/remixlua/cl/customrender/cl_2d_skybox_renderer.lua
lua/remixlua/cl/customrender/cl_build_progress.lua
lua/remixlua/cl/customrender/cl_displacement_renderer.lua
lua/remixlua/cl/customrender/cl_rtx_meshed_world_renderer.lua
lua/remixlua/cl/customrender/cl_rtx_skybox_boundary_renderer.lua
lua/remixlua/cl/customrender/cl_static_prop_renderer.lua
lua/remixlua/cl/customrender/render_core.lua
lua/remixlua/cl/remixapi/cl_physgun_color_sync.lua
lua/remixlua/cl/remixapi/cl_remix_category_0_manager.lua
lua/remixlua/cl/remixapi/cl_remix_category_1_pseudoplayer.lua
lua/remixlua/cl/remixapi/cl_remix_category_debug.lua
lua/remixlua/cl/remixapi/cl_remix_flashlight.lua
lua/remixlua/cl/remixapi/cl_remix_light_cmd.lua
lua/remixlua/cl/remixapi/cl_remix_map_configs.lua
lua/remixlua/cl/remixapi/debug_hash_hud.lua
lua/remixlua/cl/remixapi/rtx_hash_lookup.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_api_map_lights.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_api_map_lights_menu.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_dynamiclight_wrapper.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_dynamiclight_wrapper_menu.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_light_wrapper.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_light_wrapper_menu.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_maplight_animator.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_projectedtexture_wrapper.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_projectedtexture_wrapper_menu.lua
lua/remixlua/sh/sh_flashlight_override.lua
lua/remixlua/sv/sv_nonapi_flashlight.lua
lua/remixlua/sv/sv_remix_flashlight.lua
lua/remixlua/sv/sv_remix_maplight_bridge.lua
lua/remixlua/sv/sv_remove_entities.lua
lua/remixlua/sv/sv_skybox_fix.lua
lua/rtx_water/cl_bodies.lua
lua/rtx_water/cl_core.lua
lua/rtx_water/cl_data.lua
lua/rtx_water/cl_menu.lua
lua/rtx_water/cl_native.lua
lua/rtx_water/cl_ripples.lua
lua/rtx_water/cl_splash.lua
lua/rtx_water/cl_surface.lua
lua/rtx_water/sv_bullets.lua
lua/tmc/init.lua
lua/tmc/types.lua
lua/unittest/niknaks/bignumber.lua
lua/unittest/niknaks/bitbuffer.lua
lua/unittest/niknaks/bsp.lua
lua/unittest/niknaks/color.lua
lua/unittest/niknaks/datetime.lua
lua/unittest/niknaks/gunit_emmy.lua
lua/unittest/niknaks/linq.lua
lua/unittest/niknaks/main.lua
lua/unittest/niknaks/timedelta.lua
lua/weapons/gmod_tool/stools/advanced_bodygroup.lua
lua/weapons/gmod_tool/stools/advmateditor.lua
lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua
lua/weapons/gmod_tool/stools/mmdhl_prop.lua
lua/weapons/gmod_tool/stools/portal_creator_tool.lua
lua/weapons/gmod_tool/stools/portal_fitter_tool.lua
lua/weapons/gmod_tool/stools/portal_resizer_tool.lua
lua/weapons/gmod_tool/stools/procedural_glass_tool.lua
lua/weapons/gmod_tool/stools/remix_rt_light_bonemerge.lua
lua/weapons/gmod_tool/stools/remix_rt_light_cylinder.lua
lua/weapons/gmod_tool/stools/remix_rt_light_disk.lua
lua/weapons/gmod_tool/stools/remix_rt_light_distant.lua
lua/weapons/gmod_tool/stools/remix_rt_light_rect.lua
lua/weapons/gmod_tool/stools/remix_rt_light_sphere.lua
lua/weapons/portal_gun.lua
lua/weapons/weapon_mmdhl.lua
    ]]):gmatch("%S+") do bundled[path] = true end
    function policy.bundled(source) return bundled[source:lower():gsub(":%d+$", "")] == true end
end
local nativeRender = {}
for name, value in pairs(render or {}) do nativeRender[name] = value end
local nativeCam = {}
for name, value in pairs(cam or {}) do nativeCam[name] = value end
local nativeRT, nativeRTEx, nativeMaterial, nativeCreate = GetRenderTarget, GetRenderTargetEx, Material, CreateMaterial
local function canonical(name) return name:gsub("\\", "/"):lower():gsub("%.[^./]*$", "") end
function policy.reserved(name)
    -- GLua's type() can report "ITexture", rather than LuaJIT's ordinary "userdata".
    if name ~= nil and type(name) ~= "string" then
        local ok, value = pcall(function() return name:GetName() end)
        if not ok then return false end
        name = value
    end
    if type(name) ~= "string" then return false end
    local base = canonical(name):match("([^/]+)$") or ""
    return base:match("^_rt_shadowdepthtexture") or base:match("^_rt_resolvedfullframedepth")
        or base:match("^_nativeloader_inert_rt")
end
do
    local meta = FindMetaTable("ProjectedTexture")
    local remove = meta and meta.Remove
    if remove then
        meta.Remove = function(self, ...)
            local result = pack(remove(self, ...))
            if active() then
                -- GShader's Remove replacement lives in its private copy. Retire its public
                -- caches here instead, otherwise that list retains every removed native lamp.
                local lights, indices, cache = rawget(_G, "ENV_PROJTEXS"), rawget(_G, "ENV_PROJTEXS_I"), rawget(_G, "ptCache")
                if type(lights) == "table" and type(indices) == "table" and type(cache) == "table" then
                    rawset(cache, self, nil)
                    local count, kept = #lights, 0
                    for i = 1, count do
                        local light = rawget(lights, i)
                        local ok, valid = pcall(IsValid, light)
                        if light ~= self and ok and valid then kept = kept + 1 rawset(lights, kept, light) end
                    end
                    for i = kept + 1, count do rawset(lights, i, nil) end
                    for id in pairs(indices) do rawset(indices, id, nil) end
                    for i = 1, kept do
                        local id = rawget(cache, rawget(lights, i))
                        if id ~= nil then rawset(indices, id, i) end
                    end
                end
            end
            return unpack(result, 1, result.n)
        end
    end
    for _, method in ipairs({"Update", "SetEnableShadows", "SetFOV", "SetHorizontalFOV", "SetVerticalFOV",
        "SetNearZ", "SetFarZ", "SetShadowDepthBias", "SetShadowSlopeScaleDepthBias", "SetBrightness"}) do
        local original = meta and meta[method]
        if original then
            meta[method] = function(self, ...)
                if active() then
                    local source, value = caller(), ...
                    if policy.csm(source) and (method == "Update" or method == "SetEnableShadows") then
                        reject("ProjectedTexture." .. method, "Real CSM raster shadow pass is inert under RTX", source) return
                    end
                    if method ~= "Update" and method ~= "SetEnableShadows" and (not finite(value)
                        or (method:find("FOV", 1, true) and (value <= 0 or value >= 180))) then
                        reject("ProjectedTexture." .. method, "invalid projection parameter ignored", source) return
                    end
                end
                return original(self, ...)
            end
        end
    end
end
function policy.inertTarget()
    if policy.target then return policy.target end
    local ok, target
    if nativeRTEx then
        ok, target = pcall(nativeRTEx, "_nativeloader_inert_rt_v1", 1, 1, 8, 2, 0, 0, 0)
    elseif nativeRT then ok, target = pcall(nativeRT, "_nativeloader_inert_rt_v1", 1, 1) end
    -- An allocator can itself fail (Lua error, not native/GPU recovery). Reuse an engine texture.
    if (not ok or not target) and nativeRender.GetScreenEffectTexture then
        ok, target = pcall(nativeRender.GetScreenEffectTexture)
    end
    if ok and target then policy.target = target policy.inertTextures[target] = true end
    return policy.target
end
function policy.inertMaterial()
    if not policy.material then
        policy.material = nativeCreate("_nativeloader_inert_material_v1", "UnlitGeneric", {
            ["$basetexture"] = "vgui/white", ["$translucent"] = "1", ["$alpha"] = "0", ["$ignorez"] = "1"})
        policy.inertMaterials[policy.material] = true
    end
    return policy.material
end
-- A reviewed color subset, not every IMAGE_FORMAT enum exported by this engine or by an add-on.
-- Raw R32F27 remains supported for MMDHL. Depth/INTZ/NULL/compressed/RGB32F/R16F and unreviewed
-- formats become the single shared RGBA8 target, even when an add-on exports their enum names.
do
    local formats = {[-1] = 4, [0] = 4, [1] = 4, [2] = 4, [3] = 4, [4] = 2,
        [11] = 4, [12] = 4, [16] = 4, [24] = 8, [25] = 8, [27] = 4}
    -- Stock D3D9 enum values: late multiplayer globals may already have been replaced.
    local fullFrame = {[3] = true, [4] = true, [6] = true}
    local allocations, counts, bytes, total = {}, {}, {}, 0
    state.allocations_by_source, state.allocation_bytes_by_source = counts, bytes
    local function check(name, w, h, sizeMode, format, source)
        if type(name) ~= "string" or #name == 0 or #name > 256 or name:find("%z") then return "invalid target name" end
        if policy.reserved(name) then return "engine-owned shadow/depth target kept unchanged" end
        if policy.effect(source) then return "screen-space shader target is inert under RTX" end
        w, h = whole(w), whole(h)
        if not w or not h then return "target dimensions must be finite numbers" end
        local fw, fh = w, h
        if fullFrame[sizeMode] then
            if w < -1 or h < -1 or w == 0 or h == 0 then return "invalid full-frame dimensions" end
            fw, fh = ScrW(), ScrH()
            if sizeMode == 6 and finite(fw) and finite(fh) and fw > 0 and fh > 0 then
                fw, fh = 2 ^ math.ceil(math.log(fw) / math.log(2)), 2 ^ math.ceil(math.log(fh) / math.log(2))
            end
        elseif w <= 0 or h <= 0 then return "target dimensions must be positive" end
        if not finite(fw) or not finite(fh) or fw <= 0 or fh <= 0 or fw > 16384 or fh > 16384
            or fw * fh > 67108864 then return "render-target allocation exceeds the guard limit" end
        if not formats[format] then return "unreviewed RTX color format; using inert RGBA8 target" end
        local key, owner = canonical(name), source:gsub(":%d+$", "")
        local cost = fw * fh * formats[format]
        if not allocations[key] then
            if (counts[owner] or 0) >= 128 then return "caller render-target name limit" end
            if cost > 134217728 or (bytes[owner] or 0) + cost > 536870912 or total + cost > 1073741824 then
                return "render-target byte budget exceeded"
            end
            return nil, key, owner, cost
        end
    end
    local function allocated(target, key, owner, cost)
        if not target or not key then return end
        allocations[key], counts[owner] = true, (counts[owner] or 0) + 1
        bytes[owner], total = (bytes[owner] or 0) + cost, total + cost
        state.allocation_bytes = total
    end
    local function fallback(api, reason, source, name)
        reject(api, reason, source)
        -- The getter only fetches Source's texture; NeedsDepthPass is suppressed below. Never
        -- call GetRenderTarget[Ex] with the reserved name (that may reconfigure a live resource).
        if type(name) == "string" and canonical(name) == "_rt_resolvedfullframedepth"
            and nativeRender.GetResolvedFullFrameDepth then return nativeRender.GetResolvedFullFrameDepth() end
        return policy.inertTarget()
    end
    if nativeRT then
        GetRenderTarget = function(name, w, h, ...)
            if not active() then return nativeRT(name, w, h, ...) end
            local source = caller()
            local reason, key, owner, cost = check(name, w, h, nil, -1, source)
            if reason then return fallback("GetRenderTarget", reason, source, name) end
            local result = pack(nativeRT(name, w, h, ...))
            allocated(result[1], key, owner, cost)
            return unpack(result, 1, result.n)
        end
    end
    if nativeRTEx then
        GetRenderTargetEx = function(name, w, h, size, depth, flags, rtFlags, format, ...)
            if not active() then return nativeRTEx(name, w, h, size, depth, flags, rtFlags, format, ...) end
            local source, reason = caller()
            if not integer(size) or size < 0 or size > 9 then reason = "unknown size mode"
            elseif not integer(depth) or depth < 0 or depth > 3 then reason = "unknown depth mode"
            elseif depth == 3 then reason = "depth-only targets are unsupported under RTX"
            elseif not integer(flags) or not integer(rtFlags) or flags < 0 or flags > 4294967295
                or rtFlags < 0 or rtFlags > 4294967295 then reason = "flags must be finite unsigned integers"
            elseif math.floor(flags / 16384) % 2 == 1 then reason = "cubemap render targets are unsafe" end
            if reason then return fallback("GetRenderTargetEx", reason, source, name) end
            local key, owner, cost
            reason, key, owner, cost = check(name, w, h, size, format, source)
            if reason then return fallback("GetRenderTargetEx", reason, source, name) end
            local result = pack(nativeRTEx(name, w, h, size, depth, flags, rtFlags, format, ...))
            allocated(result[1], key, owner, cost)
            return unpack(result, 1, result.n)
        end
    end
end
local unsupported = {depthwrite = true, screenspace_general = true, screenspace_general_dx9 = true,
    lux_custom = true, lux_screenspace_general = true}
local shaderNames = setmetatable({}, {__mode = "k"})
local function shaderMethod(mat) return mat.GetShader end
local function shaderName(mat)
    if mat == nil then return end
    local name = shaderNames[mat]
    if name ~= nil then return name or nil end
    name = false
    local ok, method = pcall(shaderMethod, mat)
    if ok and type(method) == "function" then
        local success, value = pcall(method, mat)
        if success and type(value) == "string" then name = value:lower() end
    end
    local kind = type(mat)
    if kind == "userdata" or kind == "table" or kind == "IMaterial" then shaderNames[mat] = name end
    return name or nil
end
function policy.shader(shader, data)
    if type(shader) == "string" and (unsupported[shader:lower()] or shader:lower():match("^lux_")
        or shader:lower():match("^screenspace_general") or shader:find("%z")) then return true end
    if type(data) == "table" then
        for key, value in pairs(data) do
            if type(key) == "string" and (key:lower() == "$pixshader" or key:lower() == "$vertexshader") then return true end
            if policy.reserved(value) then return true end
        end
    end
    return false
end
do
    local checks, creationHints = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    -- Inspect only at an untrusted binding. Loading/reading a material is native, including
    -- ExoPBR/GPBR conversion and MMDHL's immediate shaders. No guard VMT/FS lookup is needed.
    function policy.incompatibleMaterial(mat)
        if mat == nil then return false end
        if policy.inertMaterials[mat] or creationHints[mat] then return true end
        if checks[mat] ~= nil then return checks[mat] end
        local denied = policy.shader(shaderName(mat))
        if not denied then
            local ok, method = pcall(function() return mat.GetString end)
            if ok and type(method) == "function" then
                for _, key in ipairs({"$pixshader", "$vertexshader", "$basetexture"}) do
                    local success, value = pcall(method, mat, key)
                    if success and type(value) == "string" and value ~= "" then
                        if key ~= "$basetexture" or policy.reserved(value) then denied = true break end
                    end
                end
            end
        end
        checks[mat] = denied
        return denied
    end
    if nativeCreate then
        CreateMaterial = function(name, shader, data, ...)
            local on = active()
            if on and (rejectNul("CreateMaterial", name) or rejectNul("CreateMaterial", shader)) then
                return policy.inertMaterial()
            end
            local result = pack(nativeCreate(name, shader, data, ...))
            -- CreateMaterial caches by name: safe parameters on a later call cannot clear a hint.
            if on and result[1] and policy.shader(shader, data) then creationHints[result[1]] = true end
            return unpack(result, 1, result.n)
        end
    end
    if nativeMaterial then
        Material = function(path, ...)
            if active() and rejectNul("Material", path) then return policy.inertMaterial() end
            return nativeMaterial(path, ...)
        end
    end
    local meta = FindMetaTable("IMaterial")
    for _, method in ipairs({"SetShader", "SetShaderAndParams", "SetTexture", "SetString", "SetInt", "SetFloat",
        "SetVector", "SetVector4D", "SetMatrix", "SetUndefined", "SetDynamicImage", "Recompute"}) do
        local original = meta and meta[method]
        if original then
            meta[method] = function(self, ...)
                local key, value = ...
                if active() then
                    local source = caller()
                    local denied = policy.inertMaterials[self]
                    if not policy.bundled(source) then
                        denied = denied or policy.effect(source)
                        if method == "SetShader" or method == "SetShaderAndParams" then
                            denied = denied or policy.shader(key, value)
                        elseif method == "SetTexture" or method == "SetString" then
                            denied = denied or policy.inertTextures[value] or policy.reserved(value)
                        end
                    end
                    if denied then reject("IMaterial." .. method, "incompatible material mutation ignored", source) return end
                end
                shaderNames[self], checks[self] = nil, nil
                if method == "SetShader" or method == "SetShaderAndParams" then creationHints[self] = nil end
                return original(self, ...)
            end
        end
    end
end
do
    local meta = FindMetaTable("Entity")
    -- Resolve named bindings through the native material cache, including !CreateMaterial names.
    -- Weak values and per-material decisions avoid extra lookups while the object is live.
    local boundPaths = setmetatable({}, {__mode = "v"})
    local function materialPath(path)
        if type(path) ~= "string" or path == "" or not nativeMaterial then return false end
        local mat = boundPaths[path]
        if not mat then
            mat = nativeMaterial(path:sub(1, 1) == "!" and path:sub(2) or path)
            boundPaths[path] = mat
        end
        return policy.incompatibleMaterial(mat)
    end
    for _, method in ipairs({"SetMaterial", "SetSubMaterial"}) do
        local original = meta and meta[method]
        if original then
            meta[method] = function(self, ...)
                local path = method == "SetMaterial" and select(1, ...) or select(2, ...)
                if active() then
                    local source = caller()
                    if rejectNul("Entity." .. method, path, source) then return end
                    if not policy.bundled(source) and (policy.effect(source) or materialPath(path)) then
                        reject("Entity." .. method, "unsupported world/entity material replacement ignored", source) return
                    end
                end
                return original(self, ...)
            end
        end
    end
    local setMaterial = surface and surface.SetMaterial
    if setMaterial then
        surface.SetMaterial = function(mat, ...)
            local on, source = active()
            if on then source = caller() end
            policy.surfaceInert = on and (policy.inertMaterials[mat] or
                (not policy.bundled(source) and (policy.effect(source) or policy.incompatibleMaterial(mat))))
            if policy.surfaceInert then
                reject("surface.SetMaterial", "unsupported RTX surface material", source)
                return setMaterial(policy.inertMaterial(), ...)
            end
            return setMaterial(mat, ...)
        end
    end
    for _, method in ipairs({"DrawTexturedRect", "DrawTexturedRectUV", "DrawTexturedRectRotated", "DrawPoly"}) do
        local original = surface and surface[method]
        if original then
            surface[method] = function(...)
                if active() and (policy.surfaceInert or policy.effect(caller()) or (policy.suppressed and policy.suppressed())) then
                    reject("surface." .. method, "screen-space effect surface draw is inert", caller()) return
                end
                return original(...)
            end
        end
    end
end
for _, name in ipairs({"SetMaterial", "MaterialOverride", "BrushMaterialOverride", "WorldMaterialOverride"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(mat, ...)
            local on, source = active()
            if on then source = caller() end
            local denied = on and (policy.inertMaterials[mat] or
                (not policy.bundled(source) and (policy.effect(source) or policy.incompatibleMaterial(mat))))
            if name == "SetMaterial" then policy.boundInert = denied end
            if denied then
                reject("render." .. name, "unsupported RTX shader draw", source)
                if name == "SetMaterial" then return original(policy.inertMaterial(), ...) end
                return
            end
            return original(mat, ...)
        end
    end
end
for _, name in ipairs({"DrawScreenQuad", "DrawScreenQuadEx", "DrawQuad", "DrawQuadEasy", "DrawSprite"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            if active() and (policy.boundInert or (policy.suppressed and policy.suppressed()) or policy.effect(caller())) then
                reject("render." .. name, "screen-space shader draw is inert under RTX", caller()) return
            end
            return original(...)
        end
    end
end
if nativeRender.RedownloadAllLightmaps then
    render.RedownloadAllLightmaps = function(...)
        if active() then reject("render.RedownloadAllLightmaps", "RTX lightmap rebuild ignored", caller()) return end
        return nativeRender.RedownloadAllLightmaps(...)
    end
end
-- Native color-material helpers also change the sprite/quad binding. A valid white binding must
-- clear an earlier rejected shader, including engines whose helpers do not call Lua SetMaterial.
for _, name in ipairs({"SetColorMaterial", "SetColorMaterialIgnoreZ"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            if active() and ((policy.suppressed and policy.suppressed()) or policy.effect(caller())) then
                reject("render." .. name, "inert effect material binding ignored", caller()) return
            end
            policy.boundInert = false
            return original(...)
        end
    end
end

-- Track only observed Lua pushes. Never guess native contexts or use mesh.End as an abort.
local frame, busy = nil, 0
local stacks = {rt = {}, camera = {}, clip = {}, model = {}}
-- An entry is live while its owner, or one of the owner's callers, is a protected callback still running.
local function live(action)
    local owner = action.owner
    while owner do
        if owner.completed == nil then return true end
        owner = owner.parent
    end
    return false
end
-- A push left open by code that failed outside a protected callback (the stock toolgun screen around
-- a tool's DrawToolScreen, an ENT:Draw error between cam.Start3D2D and End3D2D) is never popped.
-- At each frame boundary (a new FrameNumber, or PreRender where that is unavailable), forget the
-- tracked entries no running callback owns. Native state is neither guessed nor popped: only the
-- guard's own bookkeeping is resynchronized.
local function resync()
    for _, stack in pairs(stacks) do
        local kept = 0
        for i = 1, #stack do
            local action = stack[i]
            if live(action) then kept = kept + 1 stack[kept] = action else action.active = false end
        end
        for i = #stack, kept + 1, -1 do stack[i] = nil end
    end
end
local frameNumber, seenFrame = FrameNumber, nil
local function sync()
    if not frameNumber then return end
    local ok, now = pcall(frameNumber)
    if ok and now ~= seenFrame then
        if seenFrame ~= nil then resync() end
        seenFrame = now
    end
end
-- Only the running callback chain's own scopes count toward its limit; unowned leftovers never do.
local function chainDepth(stack)
    if not frame then return 0 end
    local count = 0
    for i = 1, #stack do if live(stack[i]) then count = count + 1 end end
    return count
end
-- A protected callback's entry render target, recorded when it first changes render targets.
local function noteTarget()
    local f = frame
    while f and f.haveTarget == nil do
        if nativeRender.GetRenderTarget then f.haveTarget, f.target = pcall(nativeRender.GetRenderTarget)
        else f.haveTarget = false end
        f = f.parent
    end
end
local function log(f)
    local list = f.actions
    if not list then list = {} f.actions = list end
    return list
end
local function pushed(kind, undo, replay)
    local action = {stack = stacks[kind], owner = frame, undo = undo, replay = replay, active = true}
    action.stack[#action.stack + 1] = action
    if frame then local list = log(frame) list[#list + 1] = action end
end
local function descendant(owner, ancestor)
    while owner do
        if owner == ancestor then return true end
        owner = owner.parent
    end
    return false
end
local function popped(kind)
    local action = table.remove(stacks[kind])
    if not action then return end
    action.active = false
    if action.skipped then return end -- no native state to replay after a virtual pop
    -- A completed Pre hook may deliberately leave a scope for its Post hook.
    -- If that later callback fails, retain the exact known RT push for replay.
    -- A descendant's scope was created after our entry and is already gone.
    if frame and action.owner ~= frame and not descendant(action.owner, frame) then
        local list = log(frame)
        list[#list + 1] = {restore = action, previous = stacks[kind][#stacks[kind]], depth = #stacks[kind]}
    end
end
local function invokeBusy(fn, ...)
    busy = busy + 1
    local result = pack(pcall(fn, ...))
    busy = busy - 1
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end
-- Failed pushes get a virtual scope. Its matching pop must not consume the caller's real
-- native scope. Repeated suppressed pushes share a counter, keeping runaway loops bounded.
function policy.suppressed()
    for _, stack in pairs(stacks) do
        local top = stack[#stack]
        if top and top.skipped then return true end
    end
    return false
end
-- Install each closer once. End and End3D share the native 3D counter; End2D has its own
-- painter counter. Capturing an already wrapped pop as an undo hid aliases (ADR 0122).
local closers = {}
local function pair(tbl, push, pop, kind, validate, family, describe)
    local registered = tbl and closers[tbl]
    if not registered and tbl then registered = {} closers[tbl] = registered end
    local first, last = tbl and tbl[push], registered and registered[pop] or (tbl and tbl[pop])
    if not first or not last then return end
    family = family or kind
    tbl[push] = function(...)
        if busy > 0 then return first(...) end
        sync()
        local scopeFamily, undo = family, last
        if describe then scopeFamily, undo = describe(...) end
        if active() then
            local top = stacks[kind][#stacks[kind]]
            local skip = top and top.skipped
            if chainDepth(stacks[kind]) >= 32 then reject(push, "tracked stack limit") skip = true end
            if validate and validate(nil, ...) == false then skip = true end
            if skip then
                if top and top.skipped and top.owner == frame and top.family == scopeFamily then top.count = top.count + 1
                else
                    pushed(kind, function() end, function() end)
                    top = stacks[kind][#stacks[kind]]
                    top.skipped, top.count, top.family = true, 1, scopeFamily
                end
                return
            end
        end
        if kind == "rt" and frame then noteTarget() end
        local replay
        if kind == "rt" then
            local args = pack(...)
            replay = function()
                if validate and validate("<tracked render-target push>", unpack(args, 1, args.n)) == false then return end
                return first(unpack(args, 1, args.n))
            end
        end
        local result = pack(invokeBusy(first, ...))
        pushed(kind, undo, replay)
        stacks[kind][#stacks[kind]].family = scopeFamily
        return unpack(result, 1, result.n)
    end
    if registered[pop] then return end
    registered[pop] = last
    tbl[pop] = function(...)
        if busy > 0 then return last(...) end
        sync()
        local top = stacks[kind][#stacks[kind]]
        if active() then
            if not top then reject(pop, "no tracked Lua push to pop") return end
            if top.family ~= family then reject(pop, "closer does not match tracked Lua push") return end
            if frame and top.owner ~= frame and (not top.owner or not top.owner.completed) then
                reject(pop, "protected callback cannot consume caller-owned state") return
            end
        end
        if top and top.skipped then
            top.count = top.count - 1
            if top.count == 0 then popped(kind) end
            return
        end
        if kind == "rt" and frame then noteTarget() end
        local result = pack(invokeBusy(last, ...))
        popped(kind)
        return unpack(result, 1, result.n)
    end
end
local function viewValues(api, source, view)
    if view == nil then return true end
    if type(view) ~= "table" then return reject(api, "view must be a table", source) end
    for _, key in ipairs({"x", "y", "w", "h", "fov", "znear", "zfar", "zNear", "zFar", "aspect"}) do
        if view[key] ~= nil and not finite(view[key]) then return reject(api, "non-finite view parameter " .. key, source) end
    end
    for _, key in ipairs({"w", "h"}) do
        if view[key] ~= nil and (view[key] < 1 or view[key] > 16384) then return reject(api, "invalid explicit viewport", source) end
    end
    if view.fov ~= nil and (view.fov <= 0 or view.fov >= 180) then return reject(api, "invalid field of view", source) end
    for _, key in ipairs({"origin", "angles"}) do
        if view[key] ~= nil then
            local ok, a, b, c = pcall(function()
                if key == "origin" then return view[key].x, view[key].y, view[key].z end
                return view[key].p, view[key].y, view[key].r
            end)
            if not ok or not finite(a) or not finite(b) or not finite(c) then return reject(api, "invalid " .. key, source) end
        end
    end
    return true
end
local function dimensions(texture) return texture:Width(), texture:Height() end
local validTextures = setmetatable({}, {__mode = "k"})
local function targetValues(source, texture, x, y, w, h)
    if texture ~= nil then
        if policy.inertTextures[texture] then return reject("render target", "inert target cannot be bound or copied", source) end
        if not validTextures[texture] then
            local ok, width, height = pcall(dimensions, texture)
            if not ok or not finite(width) or not finite(height) or width <= 0 or height <= 0
                or width > 16384 or height > 16384 then return reject("render target", "invalid texture", source) end
            local named, name = pcall(function() return texture:GetName() end)
            if named and policy.reserved(name) then return reject("render target", "engine-owned depth target cannot be bound or copied", source) end
            local kind = type(texture)
            if kind == "userdata" or kind == "table" or kind == "ITexture" then validTextures[texture] = true end
        end
    end
    if (x ~= nil and not finite(x)) or (y ~= nil and not finite(y)) or (w ~= nil and not finite(w)) or (h ~= nil and not finite(h)) then
        return reject("PushRenderTarget", "non-finite viewport", source)
    end
    if (w and (w < 1 or w > 16384)) or (h and (h < 1 or h > 16384)) then
        return reject("PushRenderTarget", "invalid explicit viewport", source)
    end
    return true
end
pair(render, "PushRenderTarget", "PopRenderTarget", "rt", targetValues)
pair(render, "PushCustomClipPlane", "PopCustomClipPlane", "clip")
pair(cam, "PushModelMatrix", "PopModelMatrix", "model")
pair(cam, "Start", "End", "camera", function(s, view) return viewValues("cam.Start", s, view) end,
    "camera3d", function(view)
        if type(view) == "table" and type(view.type) == "string" and view.type:sub(1, 1) == "2" then
            return "camera2d", nativeCam.End2D
        end
        return "camera3d", nativeCam.End
    end)
pair(cam, "Start2D", "End2D", "camera", nil, "camera2d")
pair(cam, "Start3D", "End3D", "camera", function(s, pos, angle, fov, x, y, w, h, near, far)
    return viewValues("cam.Start3D", s, {origin = pos, angles = angle, fov = fov, x = x, y = y, w = w, h = h, znear = near, zfar = far})
end, "camera3d")
-- Start3D2D also pushes a model matrix. An ordinary camera closer cannot unwind that scope,
-- nor may End3D2D consume an ordinary camera and an unrelated caller-owned matrix.
pair(cam, "Start3D2D", "End3D2D", "camera", nil, "camera3d2d")
pair(cam, "StartOrthoView", "EndOrthoView", "camera", nil, "cameraortho")
if nativeRender.SetRenderTarget then
    render.SetRenderTarget = function(texture, ...)
        if active() and (policy.suppressed() or not targetValues(nil, texture)) then return end
        if frame and busy == 0 then noteTarget() end
        local result = pack(nativeRender.SetRenderTarget(texture, ...))
        if frame and busy == 0 then frame.targetChanged = true end
        return unpack(result, 1, result.n)
    end
end
if nativeRender.SetRenderTargetEx then
    render.SetRenderTargetEx = function(index, texture, ...)
        if active() then
            if index == 0 and policy.suppressed() then return end
            if not integer(index) or index < 0 or index > 3 then reject("render.SetRenderTargetEx", "unknown render-target slot") return
            elseif index ~= 0 and texture ~= nil then reject("render.SetRenderTargetEx", "MRT is unsupported by the RTX path") return
            elseif not targetValues(nil, texture) then return end
        end
        local primary = index == 0 and frame ~= nil and busy == 0
        if primary then noteTarget() end
        local result = pack(nativeRender.SetRenderTargetEx(index, texture, ...))
        if primary then frame.targetChanged = true end
        return unpack(result, 1, result.n)
    end
end
for _, name in ipairs({"Clear", "ClearDepth", "ClearStencil", "DepthRange", "OverrideDepthEnable",
    "OverrideColorWriteEnable", "OverrideAlphaWriteEnable", "OverrideBlend", "SetBlend", "SetLightingMode",
    "FogMode", "FogColor", "FogStart", "FogEnd", "FogMaxDensity", "UpdateScreenEffectTexture", "UpdateRefractTexture"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            if active() and (policy.suppressed() or policy.effect(caller())) then
                reject("render." .. name, "inert effect state change ignored", caller()) return
            end
            return original(...)
        end
    end
end
for _, name in ipairs({"CopyRenderTargetToTexture", "CopyTexture"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            local target, other = ...
            if active() then
                local source = caller()
                if policy.effect(source) or target == nil or (name == "CopyTexture" and other == nil)
                    or not targetValues(source, target) or (other ~= nil and not targetValues(source, other)) then
                    reject("render." .. name, "incompatible color/depth copy ignored", source) return
                end
                if policy.suppressed() then return end
                if name == "CopyRenderTargetToTexture" and nativeRender.GetRenderTarget then
                    local current = nativeRender.GetRenderTarget()
                    if current and not targetValues(source, current) then return end
                end
            end
            return original(...)
        end
    end
end
local viewDepth = 0
if nativeRender.RenderView then
    render.RenderView = function(view, ...)
        if not active() then return nativeRender.RenderView(view, ...) end
        if policy.suppressed() then reject("render.RenderView", "ignored render scope has no secondary view", caller()) return end
        if not viewValues("render.RenderView", caller(), view) then return end
        if policy.effect(caller()) then reject("render.RenderView", "screen-space secondary view is inert", caller()) return end
        if viewDepth >= 4 then reject("render.RenderView", "nested view limit", caller()) return end
        viewDepth = viewDepth + 1
        local result = pack(pcall(nativeRender.RenderView, view, ...))
        viewDepth = viewDepth - 1
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
end
local function sourceOf(f)
    local source = f.source
    if not source then source = functionSource(f.fn) f.source = source end
    return source
end
local function cleanup(f)
    local actions = f.actions
    busy = busy + 1
    for i = actions and #actions or 0, 1, -1 do
        local action = actions[i]
        if action.restore then
            local prior = action.restore
            if #prior.stack ~= action.depth or prior.stack[#prior.stack] ~= action.previous then
                report("cleanup_errors", f.event, "tracked state changed before popped-scope restoration", sourceOf(f))
            elseif not prior.replay then
                -- Camera/clip/matrix defaults and mutable arguments are not
                -- enough to reconstruct an earlier native context safely.
                report("cleanup_errors", f.event, "completed camera/clip/matrix pop cannot be safely replayed", sourceOf(f))
            else
                local ok = pcall(prior.replay)
                if ok then prior.stack[#prior.stack + 1] = prior prior.active = true
                else report("cleanup_errors", f.event, "popped render-target restoration failed", sourceOf(f)) end
            end
        elseif action.active then
            if action.stack[#action.stack] == action then
                local ok = pcall(action.undo)
                if ok then table.remove(action.stack) action.active = false
                else report("cleanup_errors", f.event, "tracked stack restoration failed", sourceOf(f)) end
            else report("cleanup_errors", f.event, "untracked state prevents stack restoration", sourceOf(f)) end
        end
    end
    if f.targetChanged and f.haveTarget and nativeRender.SetRenderTarget then
        local ok = pcall(nativeRender.SetRenderTarget, f.target)
        if not ok then report("cleanup_errors", f.event, "target restoration failed", sourceOf(f)) end
    end
    busy = busy - 1
end
-- A failure prints the original error and its stack through the engine's own error output, at most
-- once per callback every ten seconds; the guard's records keep virtual sources only. Three
-- consecutive failures within ten seconds quarantine a hook, timer or cvar callback. Gamemode
-- methods are never quarantined: base GM:PostDrawViewModel draws the hands for every weapon.
local clock = SysTime or RealTime or os.clock
local reportInterval, quarantineWindow, quarantineFailures = 10, 10, 3
local failures = setmetatable({}, {__mode = "k"})
local function printError(text)
    if ErrorNoHaltWithStack then ErrorNoHaltWithStack(text)
    elseif ErrorNoHalt then ErrorNoHalt(traceback(text, 3) .. "\n")
    elseif MsgN then MsgN(traceback(text, 3)) end
end
local function failed(f, text)
    local now = clock()
    local record = failures[f.fn]
    if not record then record = {streak = 0, first = now, suppressed = 0} failures[f.fn] = record end
    if record.streak == 0 or now - record.first > quarantineWindow then record.streak, record.first = 1, now
    else record.streak = record.streak + 1 end
    if record.reported and now - record.reported < reportInterval then
        record.suppressed = record.suppressed + 1
        return
    end
    local suppressed = record.suppressed
    record.reported, record.suppressed = now, 0
    pcall(printError, text)
    report("errors", f.event, "Lua error contained; its message and stack are in the console", sourceOf(f))
    if suppressed > 0 and MsgN then
        MsgN("[nativeloader] RTX guard: " .. f.event .. ": " .. suppressed .. " further Lua errors from "
            .. sourceOf(f) .. " since the last report")
    end
end
-- The xpcall message handler runs where the error was raised, so the printed stack is the callback's.
local function handler(err)
    local text = tostring(err)
    if frame then pcall(failed, frame, text) end
    return text
end
local function quarantined(fn, event)
    local record = failures[fn]
    if not record or record.streak < quarantineFailures then return false end
    report("errors", event, "callback quarantined after " .. quarantineFailures .. " consecutive Lua errors", functionSource(fn))
    return true
end
local function settle(f, ok, ...)
    frame = f.parent
    f.completed = ok
    if not ok then cleanup(f) return false end
    local record = failures[f.fn]
    if record then record.streak = 0 end
    -- Successful nested work is part of its active caller's chronological
    -- undo log. Failed children already cleaned their own log and must not
    -- replay those restores a second time if an ancestor subsequently fails.
    local parent, actions = f.parent, f.actions
    if parent then
        if actions then
            local list = log(parent)
            for i = 1, #actions do list[#list + 1] = actions[i] end
        end
        if f.targetChanged then parent.targetChanged = true end
    end
    return true, ...
end
local function protectedCall(fn, event, ...)
    if policy.skipCallback(fn, event) then return true end
    local f = {event = event, fn = fn, parent = frame}
    frame = f
    return settle(f, xpcall(fn, handler, ...))
end
local events = {Initialize = true, InitPostEntity = true, OnReloaded = true,
    PreRender = true, PostRender = true, RenderScene = true, RenderScreenspaceEffects = true,
    PreDrawEffects = true, PostDrawEffects = true, PreDrawOpaqueRenderables = true,
    PostDrawOpaqueRenderables = true, PreDrawTranslucentRenderables = true, PostDrawTranslucentRenderables = true,
    PreDrawViewModel = true, PostDrawViewModel = true, PostDrawPlayerHands = true,
    HUDPaint = true, PreDrawHUD = true, PostDrawHUD = true, PostRenderVGUI = true,
    SetupWorldFog = true, SetupSkyboxFog = true, NeedsDepthPass = true,
    InitPostShaderlib = true, InitPostReconstruction = true, PreDrawReconstruction = true, PostDrawReconstruction = true}
local getHooks, quarantine = hook.GetTable, {}
local function gamemodeResult(ok, ...) if ok then return ... end end
if not late then
    local originalCall = hook.Call
    hook.Call = function(name, gm, ...)
        if not events[name] or not active() then return originalCall(name, gm, ...) end
        if name == "NeedsDepthPass" then return false end
        if name == "PreRender" and not frameNumber and frame == nil and busy == 0 then resync() end
        local entries = getHooks()[name]
        local stopped = quarantine[name]
        if not stopped then stopped = setmetatable({}, {__mode = "k"}) quarantine[name] = stopped end
        if entries then
            for id, fn in pairs(entries) do
                if type(id) ~= "string" and not IsValid(id) then entries[id] = nil
                elseif stopped[id] ~= fn then
                    local ok, a, b, c, d, e, g
                    if type(id) == "string" then ok, a, b, c, d, e, g = protectedCall(fn, name, ...)
                    else ok, a, b, c, d, e, g = protectedCall(fn, name, id, ...) end
                    if not ok then
                        if quarantined(fn, name) then stopped[id] = fn end
                    elseif a ~= nil then return a, b, c, d, e, g end
                end
            end
        end
        local fn = gm and gm[name]
        if fn then return gamemodeResult(protectedCall(fn, name, gm, ...)) end
    end
end
-- Capability policy applies to remote callbacks too, without catching their unrelated errors.
-- Wrapping these entries also covers an engine/add-on that cached the original hook.Call.
do
    local allowed = {Initialize = true, InitReconstruction = true, InitPostReconstruction = true,
        OnScreenSizeChanged = true, OnReloaded = true, ShutDown = true}
    local filtered = setmetatable({}, {__mode = "k"})
    local function filter(event, fn)
        if type(fn) ~= "function" or (event ~= "NeedsDepthPass"
            and (allowed[event] or not policy.effect(functionSource(fn)))) then return fn end
        local entries = filtered[fn]
        if not entries then entries = {} filtered[fn] = entries end
        if not entries[event] then
            entries[event] = function(...)
                if active() then
                    if event == "NeedsDepthPass" then return false end
                    if policy.skipCallback(fn, event) then return end
                end
                return fn(...)
            end
        end
        return entries[event]
    end
    policy.filter = filter
    for event, entries in pairs(getHooks()) do
        for id, fn in pairs(entries) do entries[id] = filter(event, fn) end
    end
    local originalAdd = hook.Add
    hook.Add = function(event, id, fn, ...) return originalAdd(event, id, filter(event, fn), ...) end
end
local function callback(fn, event)
    local stopped = false
    local function finish(ok, ...)
        if ok then return ... end
        if quarantined(fn, event) then stopped = true end
    end
    return function(...)
        if not active() then return fn(...) end
        if policy.skipCallback(fn, event) then return end
        if stopped then return end
        return finish(protectedCall(fn, event, ...))
    end
end
-- In the verified multiplayer route the remote server's own Lua stays as it is (ADR 0052): only
-- callbacks defined in the owned, hash-verified environments are protected, recognized by the
-- private marker raw-set in their environment.
local function owned(fn)
    if type(fn) ~= "function" then return false end
    local ok, env = pcall(getfenv, fn)
    return ok and type(env) == "table" and env ~= _G and rawget(env, "NATIVELOADER_VERIFIED_MULTIPLAYER") == true
end
local function protects(fn) return type(fn) == "function" and (not late or owned(fn)) end
if late then
    -- The engine may already hold the original hook.Call. Protect owned render
    -- functions themselves in this late path. Loading-hook identity stays intact
    -- for the verified bootstrap's initialization replay.
    local loadingEvents = {Initialize = true, InitPostEntity = true, OnReloaded = true}
    local lateEvents, registrations = {}, {}
    for event in pairs(events) do
        if not loadingEvents[event] then lateEvents[event] = true end
    end
    local function renderCallback(event, id, fn)
        local entries = registrations[event]
        if not entries then
            entries = setmetatable({}, {__mode = "k"})
            registrations[event] = entries
        end
        local prior = entries[id]
        if prior and (prior.original == fn or prior.wrapper == fn) then return prior.wrapper end
        local wrapper = callback(fn, event)
        entries[id] = {original = fn, wrapper = wrapper}
        return wrapper
    end
    for event, entries in pairs(getHooks()) do
        if lateEvents[event] and type(entries) == "table" then
            for id, fn in pairs(entries) do
                if owned(fn) then entries[id] = renderCallback(event, id, fn) end
            end
        end
    end
    local originalAdd = hook.Add
    hook.Add = function(event, id, fn, ...)
        if lateEvents[event] and id ~= nil and owned(fn) then fn = renderCallback(event, id, fn) end
        return originalAdd(event, id, fn, ...)
    end
    state.late_render_wrappers = true
end
if timer and timer.Create then
    local original = timer.Create
    timer.Create = function(id, delay, count, fn, ...)
        if protects(fn) then fn = callback(fn, "timer.Create") end
        fn = policy.filter("timer.Create", fn)
        return original(id, delay, count, fn, ...)
    end
end
if timer and timer.Simple then
    local original = timer.Simple
    timer.Simple = function(delay, fn, ...)
        if protects(fn) then fn = callback(fn, "timer.Simple") end
        fn = policy.filter("timer.Simple", fn)
        return original(delay, fn, ...)
    end
end
if cvars and cvars.AddChangeCallback then
    local original = cvars.AddChangeCallback
    cvars.AddChangeCallback = function(name, fn, id, ...)
        if protects(fn) then fn = callback(fn, "cvars.AddChangeCallback") end
        fn = policy.filter("cvars.AddChangeCallback", fn)
        return original(name, fn, id, ...)
    end
end
local postprocess = {"DrawBloom", "DrawColorModify", "DrawSharpen", "DrawMotionBlur", "DrawToyTown",
    "DrawMaterialOverlay", "DrawSobel", "DrawSunbeams", "DrawTexturize", "DrawBokehDOF"}
local wrappedPost = {}
local function installPost()
    for _, name in ipairs(postprocess) do
        local original = _G[name]
        if type(original) == "function" and original ~= wrappedPost[name] then
            local wrapper = function(...) if not active() then return original(...) end end
            wrappedPost[name], _G[name] = wrapper, wrapper
        end
    end
    if halo and type(halo.Render) == "function" and halo.Render ~= wrappedPost.halo then
        local original = halo.Render
        local wrapper = function(...) if not active() then return original(...) end end
        wrappedPost.halo, halo.Render = wrapper, wrapper
    end
end
installPost()
hook.Add("Initialize", "nativeloader_guard", installPost)
