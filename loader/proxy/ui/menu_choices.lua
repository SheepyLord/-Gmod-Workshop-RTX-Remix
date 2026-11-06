-- Stock lua.Run formats only a quoted process token. No executable input comes from files.
local token = %s
if not IsValid(pnlMainMenu) then return end
local function small(key)
    local value = cookie.GetString(key, "")
    return isstring(value) and #value <= 128 and value or ""
end
local result = {
    session_token = token,
    update_seen = _G.NativeLoaderUpdateSession == token,
    ignored_version = small("nativeloader.loader-update-ignored"),
    multiplayer_dismissed = small("nativeloader.multiplayer-warning-dismissed") == "1"
}
pnlMainMenu:Call("window.NativeLoaderReceiveMenuState(" .. util.TableToJSON(result) .. ")")
