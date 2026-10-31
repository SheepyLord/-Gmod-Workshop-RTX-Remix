-- Menu-only, formatted by the stock lua.Run bridge (quoted token, numeric PID).
local token, process_id = %s, %s
if not IsValid( pnlMainMenu ) then return end
local function read( path, maximum )
    local size = file.Size( path, "DATA" )
    if size < 0 or size > maximum then return end
    local text = file.Read( path, "DATA" )
    if not text or #text > maximum then return end
    local value = util.JSONToTable( text )
    if istable( value ) then return value end
end
local status = read( "native-loader/status.json", 1048576 )
local memory = read( "native-loader/memory.json", 4096 )
local result = { session_token = token, warning_allowed = _G.NativeLoaderRAMWarningSession ~= token }
if status and status.process_id == process_id and status.session_token == token then result.previous_session = status.previous_session end
if memory and memory.schema == 1 and memory.session_token == token then result.commit = memory end
-- Encode parsed data again: file contents are never concatenated into executable JavaScript.
pnlMainMenu:Call( "window.NativeLoaderReceiveNotices(" .. util.TableToJSON( result ) .. ")" )
