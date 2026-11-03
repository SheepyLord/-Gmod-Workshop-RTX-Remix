# cl_rtx_topbr_conversion.lua

GPL client ToPBR driver and imported-game PBR editor, loaded by remixbinary on x86-64/Chromium.
World conversion defaults off; imported game maps default on. It synchronizes client convars,
pumps native snapshots and submits bounded hotloader metadata; unresolved drawn hashes retry.
Clear retracts/requeues registrations while native DDS and persistent records remain available.

Commands: `rtx_topbr_stats`, `rtx_topbr_inspect`, `rtx_topbr_clear`, `rtx_topbr_process`,
`rtx_topbr_help`, and `rtx_topbr_game_editor`. The editor is also the RTX menu's Imported game PBR
panel. It offers a selector for visible imported characters, uses the cursor-independent eye trace when
possible, and lists the chosen character's materials, thumbnails for drawn materials, live states,
candidate families and individual source-folder files. Choose maps with an explicit layout, none,
or automatic. The console editor fits the viewport and scrolls, initially selects a drawn material, and refreshes row states. Bundled i18n is preferred, with
new GPL phrases supplied for all six bundled languages. It stays in this existing trusted Lua path.

Reads hotloader source/library metadata and native worker snapshots. Map discovery, conversion,
durable texture-scoped choices and DDS validation run on the native worker. Changes apply across
all observed materials/characters sharing a live texture. Authored replacements and the independent
game-map switch retain publication priority. Lua does not decode images, write source files, change
Steam settings or touch Remix user.conf. Saved convars use the ordinary game configuration.
Known discovered map layouts are checked case-insensitively before a manual submission.
No standalone exit code; queue failures remain retryable and native conversion/save errors appear
in the editor/console. Native and Lua regressions are described in `docs/TOPBR_R11.md`.
