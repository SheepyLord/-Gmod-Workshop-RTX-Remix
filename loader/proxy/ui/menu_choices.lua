-- Stock lua.Run formats only a quoted process token. No executable input comes from files.
local token = %s
if not IsValid(pnlMainMenu) then return end
local function small(path)
    local size = file.Size(path, "DATA")
    if size < 0 or size > 128 then return "" end
    local value = file.Read(path, "DATA")
    return isstring(value) and #value <= 128 and value or ""
end
local result = {
    session_token = token,
    update_seen = _G.NativeLoaderUpdateSession == token,
    ignored_version = small("native-loader/loader-update-ignored.txt"),
    multiplayer_dismissed = small("native-loader/multiplayer-warning-dismissed.txt") == "1"
}
pnlMainMenu:Call("window.NativeLoaderReceiveMenuState(" .. util.TableToJSON(result) .. ")")
