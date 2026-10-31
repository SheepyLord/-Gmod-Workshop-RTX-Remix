# R4: review and field QA of the QoL batch

Claude's review of Codex Astra's QoL batch: the 35 commits from the handover `2901563` to `614dcb5`
(loader 0.6.0 to 0.10.0, runtime patches 0005-0013, the GPL native changes, the companion and add-on
Lua, the tools and CI), the user's four field reports, fixes with tests on `r4-review-qa` (merged from
the branches `r4-legacy`, `r4-startup`, `r4-rtxdebug`, `r4-runtime`, `r4-companion`, `r4-motion`), field
QA on the user's install and the release. Seven reviewers read one slice each, read-only, against the
code and the ADRs; every finding below was checked again against the code before it was accepted.

## State found

- `main` = `origin/main` at `614dcb5`; the full suite passed there (22 CTests, 294 Python and Lua
  tests, 3 skips). The main checkout's working tree held 23 files rewritten at 01:59:09 on 10-31 with
  older committed versions (each matched a blob in history, so no work was lost); it was put back to
  `HEAD` and fast-forwarded, the diff kept in `out\qa-review\`.
- The field install ran loader 0.10.0 (`95303c86`), copied in by hand: its install receipt still
  named 0.7.0 (`c70c492b`), and its `winmm.pdb` was 0.7.0's.
- The latest GitHub release was v0.5.0, while the Workshop item requires loader 0.10.0.

## The user's field reports

| # | Report | Cause | Done |
|---|---|---|---|
| U1 | Shooting a window on modern_house crashes the game | Every `procedural_shard` drawn through DrawModel + GetRenderMesh crashed on the material system's render thread (`studiorender.dll+0x6603b`, read of -1) with `mat_queue_mode 2`; the map-glass debris (ADR 0040) only made it reachable from map windows. Bisected in the field: no crash without the break hook, none with debris hidden, a crash from the add-on's own pane alone, none once shards draw their mesh themselves | Shards draw their own mesh; meshes a queued frame may use are retired for eight frames (`fcc7bb5`) |
| U2 | The Motion importer tab is only a button and does not resemble the desktop importer | ADR 0049 added a launcher tab | The tab hosts the importer and the Motion Manager in place, laid out like `GmodMMDMotionImporter.exe`, built by the add-on's own builders; the part was 20 days behind its add-on and had no in-game importer, so it now carries the add-on's main (fcd56f4) (`r4-motion`, ADR 0060) |
| U3 | The toolgun's rolling text is still smeared | ADR 0046's redraw was a perspective draw into a render target, which Remix takes into its scene; only the path-traced screen was visible | Projected 2D overlay (ADR 0057, `9bfdbce`), sharp in the field |
| U4 | External Models shows `mmdhl.ui.character.rtx_normals` | Two keys without the `mmdhl.` prefix in all seven catalogs | Prefixed; `check_addon_i18n.py` checks every literal lookup (`909d1d9`) |

## Review findings

Severity is this review's. "Fixed" means fixed with a regression test unless noted.

| ID | Area | Sev. | Finding | Done |
|---|---|---|---|---|
| R4-01 | Multiplayer | high | RTXDebug decided single-player from client Lua (`game.SinglePlayer`), which a server can replace while replicating `sv_cheats`: memory writes and Lua eval for a player with `-insecure` on a malicious insecure server | Fixed: native loopback/one-slot check; read-only leaks (addresses, file probes, convars) closed outside single-player (RTXDebug 0.2.1) |
| R4-02 | Multiplayer | high | Without `-insecure` the RTX fixes module's own engine/client code patches and detours run on VAC-secured servers; ADR 0052 named only the seven recipes | Kept as the user's decision (2026-10-31: multiplayer is a must-have; upstream runs without `-insecure`); risk recorded in ROADMAP |
| R4-03 | Guard | high | Tracked RT/camera stacks leaked across frames; after 32 entries every push was refused for the session | Fixed: per-frame resync, limit counts the running chain only (ADR 0056) |
| R4-04 | Guard | high | One Lua error quarantined a hook or a gamemode method for good, error text discarded | Fixed: original error reported (rate-limited), three consecutive failures, gamemode methods never quarantined |
| R4-05 | Guard | high | The guarded `init.lua` view was served by a listen host to remote vanilla clients | Fixed: local proof (loader-written cache file plus the machine's active status); `AddCSLuaFile` removed |
| R4-06 | Start-up | med | A GMod update to `init.lua` (or a changed cache) disabled RTX for everyone until a new `winmm.dll`; other preparation failures left RTX unguarded | Fixed: RTX activates, the guard installs from its autorun, the cache is kept aside and rewritten (ADR 0056) |
| R4-07 | Start-up | med | The only multiplayer trigger lived in the display-only diagnostics overlay | Fixed: its own menu hook |
| R4-08 | Multiplayer | med | The bootstrap ran the RTX scripts a second time on listen hosts and `sv_allowcslua 1` servers | Fixed: normal-load marker; servers shipping the fixes skip only that add-on |
| R4-09 | Multiplayer | med | `allow_rtx_render_patches:false` without `-insecure` ran the renderer without its fixes (the crashing case) | Fixed: stays vanilla with a reason |
| R4-10 | Legacy | high | A link inside a catalogued root (Mount HL2 RTX) failed every deployment | Fixed: links stay, never followed; planning errors are notes (ADR 0055) |
| R4-11 | Legacy | high | After a GMod update, leftover Remix files failed every start; Steam verification could not clear it | Fixed: other builds and unknown edits keep Steam's files, the rest is archived |
| R4-12 | Legacy | med | A junctioned game folder failed every deployment, even with no legacy Remix | Fixed: links checked below the root only |
| R4-13 | Legacy | med | Files adopted by an RTX-off deployment escaped the archive and could come back at uninstall | Fixed |
| R4-14 | Legacy | low | `..` check could never fire; every move re-hashed the 1.5 GB payload | Fixed; re-hash limited to migration moves (0.75 s per update saved) |
| R4-15 | Runtime | high | The outline-shell rule hid every opaque CW-culled draw: flipped view models, their hands, Seamless Portals faces | Fixed twice: the companion leaves the cull rule off by default (`nativeloader_ignore_outline_shells`, ADR 0059); patch 0014 skips view models and mirrored draws |
| R4-16 | Runtime | med | 0008: Discard/Revert did nothing without a `user.conf`; an unreadable settings file became an empty saveable layer | Fixed (patch 0014) |
| R4-17 | Runtime | low | Saves without retry; links replaced by plain files | Fixed (patch 0014) |
| R4-18 | Companion | med | Primary shadows forced on 4 s after every map start, overriding Remix's saved setting (ADR 0044) | Fixed (`r4-companion`) |
| R4-19 | Companion | med | Outline suppression scanned every entity every frame; map textures named `*_outline` were hidden | Fixed (`r4-companion`) |
| R4-20 | Glass | med | A full resync sent every batch in one tick; any client could make the server serialize all shards | Fixed (`r4-companion`) |
| R4-21 | Tools | med | The publish fingerprint missed `companion_i18n.py`, `LICENSE`, `third_party/gmod` and `.gitattributes` | Fixed (`r4-companion`) |
| R4-22 | Tools | med | Uploads go through a byte-patched copy of `gmpublish.exe`, recorded only inside ADR 0039 | Kept and recorded (ADR 0058) |
| R4-23 | i18n | low | `check_addon_i18n.py` could pass with a part missing and printed its pass line on failure | Fixed |
| R4-24 | Native | low | Oversized skinning: the declaration cache outlives a recreated device; the test's stale-cache assertion is vacuous; "all nine arguments preserved" holds for eight | Noted, not changed: a GPL module rebuild for no user-visible defect; the test file is pinned in `build-pins.json` |
| R4-25 | Tools | low | `inputs.py` records the containing repository's commit for build outputs under `out\` | Noted; the helper DLL was re-imported from a committed 0.10.1 build |
| R4-26 | Runtime | low | Splash text file writable by any server's client Lua; PSR spread angle zero in ray-query mode; full material built for cutout rejection; welcome timeout uses unclamped time; the crash-report decline shows a blocking notice when reports cannot be removed | Noted for a later runtime round |
| R4-27 | Loader | med | Found in field QA: the main menu's diagnostics panel showed mojibake (`Ryzen ... Â· 32 logical threads`) and every translated label broke: GMod's menu decodes the generated `control.Menu.js` copy as Windows-1252 | Fixed: the loader writes the appended script as ASCII, `\uXXXX` escapes (`02aaf43`) |
| R4-28 | Fixes | high | Found in PoC QA: the RTX fixes flush the studio hardware meshes one second after `InitPostEntity`, while the world is drawn; with queued rendering the material system's thread was drawing them (`[HWSkin] CRASH in DrawGroupHWSkin` during the flush, then `studiorender.dll+0x5d353`, read of 0): 4 of 8 PoC starts crashed. Upstream code (2026-08), not the QoL batch; none of the 14 field starts that reached a map crashed there (the user's 766 add-ons change the timing) | Fixed: queued rendering is off for that one flush and the player's `mat_queue_mode` comes back; the flush is skipped if the switch does not take |
| R4-29 | Tools | med | Found in PoC QA: `poc_session.py` declined the next start's crash prompt, and Remix then deleted the report: the first R4-28 crash lost its only dump | Fixed: minidumps are copied into the evidence before each launch and after a crash; `release_qa.py` runs the whole protocol (`a4ddba4`) |

## Field QA

On the user's install (`H:\SteamLibrary\steamapps\common\GarrysMod`, the user's own settings and
launch options `-insecure -tickrate 120`, 766 Workshop subscriptions), with `poc_session.py --root
<field> --allow-steam-managed`. Evidence under `out\qa-field\`:

- `baseline`: Codex's 0.10.0 as installed: RTX active, 7 patches, guard early, 765/766 add-ons mounted,
  map in 27 s, zero Lua errors, normal quit; `user.conf`, `rtx.conf`, the loader files and the
  registry key unchanged.
- `glass`: U1 reproduced (exit `0xC0000005`), bisected (runs 02-09) and the fix checked live.
- `toolgun`: U3 diagnosed (redraw counters, render-target probes in both passes) and the fix checked live.
- The release run is recorded in the section below once the release is installed.

## Not changed, and why

- The secure-launch default (ADR 0052) stays: the user's decision.
- The GPL oversized-skinning module is not rebuilt for its low findings (R4-24).
- Runtime low findings (R4-26) wait for a runtime round that needs a shader build.
