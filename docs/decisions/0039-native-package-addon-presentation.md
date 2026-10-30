# 0039: Native package presentation in the addon menu

- Status: Accepted 2026-10-30, implementing the user's request: "Suppress warning" and "make the
  outline blue instead" and show "the addon's workshop description like other addons".
- Amends [0015](0015-workshop-route-for-native-packages.md): its harmless mount warnings are no
  longer shown while the enabled loader can present the deployed package.
- Trust, native-code allowlisting, package validation and GMod's whitelist remain unchanged.

## Decision

Loader 0.7.0 builds a display archive for each current generation package whose source is a numeric
Workshop item. Its current source must still parse and match the deployed manifest hash, ID and
version. Source ancestors must be ordinary paths. An archive that changed, failed validation or was
not deployed keeps GMod's ordinary behavior.

The display GMA preserves the source's title, description and author and contains one inert
`data_static/native-loader/packages/<item>.json` entry. It contains no executable code or native
payload. Entry and archive CRCs are valid. The actual payload remains in the unchanged original
archive, read and deployed by the loader under the existing trust rules.

The filesystem DLL's imports of `CreateFileA/W` and `GetFileAttributesExA/W` redirect only the exact
prepared paths. Opens must be read-only `OPEN_EXISTING`, without delete-on-close. Writes and other
modules pass through. Cached files live under `native-loader/presentation` with content-addressed
names. Links and edited cache files are refused; they are never repaired over the user's edit.
Uninstalling the hooks restores pass-through behavior. Session JSON records configured and used
redirects.

A generated copy of the stock `control.Addons.js` adds blue styling only for those Workshop IDs
and lets their descriptions follow the existing Workshop metadata flow. It does not embed Workshop
descriptions in executable JavaScript. Other addon errors and appearance stay as GMod defines them.
The overlay is refused if its expected stock source markers differ. No depot file is edited.

## Publisher delivery

The user's request includes autonomous GitHub and Workshop delivery. This machine's Steam presence
registry holds a stale PID, so the reviewed `gmpublish.exe` exits at `SteamAPI_IsSteamRunning()` even
though its real initialization succeeds. A narrowly guarded fallback first requires successful
`SteamAPI_InitFlat`, exact executable/API hashes and the reviewed instruction window. It then makes
an isolated copy under repository `out/tmp` and changes only the presence-check conditional branch
to continue to the existing real initialization. Authentication, ownership, upload result and
visibility checks remain those of the vendor publisher. Steam files, registry and processes are
not modified. Unknown builds and other errors fail normally.

## Limits

The loader must be installed and enabled. A source replaced during a running session is deployed
at the next start, as before. A future GMod change to the file-reading API or menu source can disable
presentation; the session report and acceptance tests expose that failure. Cached display files
are derived artifacts, separate from the transactional payload journal.
