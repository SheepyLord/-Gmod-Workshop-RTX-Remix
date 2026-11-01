# R8-B report: Backrooms native fixes

Completed locally on `codex/r8-backrooms-native`, commit
`7094baf6edf6797fd5c3f0b58ca668f9307b4906`, based directly on packaged
`a2c8dbc5e00e3effe49a8de9609dd1b8af34d552`. The corresponding-source notes are on
`r8-backrooms`. Claude still owns the DLL import and game acceptance. No game was launched,
install changed, binary imported, download performed, Workshop upload made, push, merge or tag created.

The reviewed branch ends at `e4d548d`; there are no later changes on it. The port covers:

- **6b4794f, missing SW VTX cache:** avoids repeated GAME-wide failed searches for the same
  model during one map session. Also includes the model-loader prerequisite from `672ada9`.
  Review found that a zero checksum also means a malformed/zero-checksum file; those cases
  now retain alternate-mount fallback. Only genuine open failures are cached. Keys normalize
  case/slashes and preserve separate GAME/null-all-path scopes, specific path IDs bypass the
  cache, a mutex protects statistics and entries,
  the cache stops at 65,536 paths, and model-load shutdown clears it. Files supplied at a
  previously missing path during the same map session need the next map session.
- **62f4af0, lazy model transforms:** the checked coordinate-frame read runs once only when
  bone upload/per-strip state or diagnostics use it. Failed reads are cached too. Existing
  finite/range checks remain. Nested studio draws preserve their caller's pending or resolved
  transform and restore state on SEH exits. Both automatic oversized draws with force-hardware
  off and explicitly forced small draws still reach the resolver.
- **e4d548d, native PAS visibility:** adds default-off `rtx_patch_vis_pas` through existing
  `RTX_SyncPatches`, redirecting the loaded map's in-memory PVS rows to its existing PAS rows.
  The port validates a unique executable CM_Vis match, engine-relative globals, readable
  visibility memory, writable offsets, SDK size/cluster limits and offset bounds. It saves
  full offset pairs, allocation/map/size identity, restores only still-owned offsets, and
  explicitly restores them at native module close. Default-off sync does no vis-table reads.

There were **no textual patch conflicts**. The semantic conflicts were resolved by adding the
672ada9 model-loader prerequisite, retaining a2c8dbc5's complete oversized protections instead
of the Backrooms branch's older shortcut, and extending PAS restoration beyond its original
convar-only path. Complete strip certificates, palette/declaration restoration, flex exclusions,
static-fallback guards, small-model diagnostic filters and the memory-limit no-op are retained.
The policy and memory-limit implementation/test files were compared to the base unchanged.
The unrelated `0562ed8` texture-tracker change was reviewed for dependency scope and not ported.

PAS still depends on the installed engine signature and normal client-module lifecycle; its
convar existing does not prove resolution succeeded. Existing engine visibility streams are
reused, not decoded by a new BSP validator. Other maps can incur additional geometry cost if
the optional switch is enabled. A separate multiplayer server keeps its own PVS and entity
transmission decisions; shared listen-server data can follow the client module's edit.
Native module loading still requires Remix initialization, so RTX-off loading gains no new path.

Build used the unchanged recorded generated projects, `ReleaseWithSymbols|x64`, MSVC
**14.44.35207**, Windows SDK **10.0.26100.0**, and only `gmcl_RTXFixesBinary.vcxproj` plus its
library references. Prepared dependencies came from `oversized-native`; 2,334 pinned tracked
files matched local git blobs, with 59 omitted build/template files restored from local objects.
No network operation was needed. A full rebuild and final incremental build succeeded;
pre-existing SDK/source and LNK4229 warnings remain.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `gmcl_RTXFixesBinary_win64.dll` | 4,864,512 | `18e1ebc75ac96099211205203bb6ed58cdc8d8b1c7390cee62607ec5124d9f42` |
| `gmcl_RTXFixesBinary_win64.pdb` | 40,153,088 | `822d9356ca8900e599f3a84087cff82ab963dfdc3e14c6a5f26c145335759554` |

Both files are in
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r8-fixes-native\out\r8-module\`.
Build/test logs and comparison evidence are under this aggregate worktree's `out/r8-backrooms/`.

Validation passed:

- Three new production-code C++17 `/W4 /WX /UNDEBUG` harnesses: missing/malformed VTX and
  alternate mounts, 8,000 concurrent cache hits, cache bound/reset; lazy successful/failed
  reads, nested pending/resolved transforms, all nine draw arguments and SEH restoration;
  PAS bounds/max clusters, 1,000 toggles, ownership/map replacement, signature guards,
  protected/freed memory and module-close restoration.
- Existing oversized-skinning policy, complete strip-palette and borrowed-state test.
- Existing memory-limit harness: 8,000 concurrent calls, disconnected API, valid/invalid Lua
  calls, one compatibility notice and zero configuration writes.
- x64 PE normal/delay imports and named exports match the packaged R6 DLL; unsupported
  resource-limit key strings are absent. Patch reconstruction onto a2c8dbc5 reproduced every
  changed/new source file after CRLF normalization.

Aggregate `tools/test.ps1 -Config Release` **passed**: 26/26 CTests and 470 Python tests
(28 gmapack, 25 steam, 417 tools; two expected fixture skips). Repo conventions passed.
No provenance exemption was needed or used; the candidate DLL import remains pending by instruction.

The **Lua API check passed by static source/registration review**. The add-on calls
`RemixLight.CreateSphere`, `CreateRect`, `CreateDisk`, `DestroyLight`, and
`RemixConfig.GetConfigVariable`/`SetConfigVariable`; the native bindings already support its
parameter tables and entity ID `0`. Package Lua requires that module, syncs patches periodically,
exposes `Light2RTX.Clear` and `rtx_api_map_lights_autospawn`, and uses all three updater hooks
the add-on suspends. Packaged NikNaks supplies `ClusterFromPoint` and `PASForOrigin`; material
collection already avoids the old per-prop mesh extraction. **No matching Lua change is needed.**
The new visibility convar arrives with the candidate DLL. The add-on data contains 1,682 lights
for gm_br_complex and 2,687 for gm_br_pitfalls. No Lua VM or renderer was exercised here.

The [GPL source record](../../packages/fixes/licenses/oversized-skinning/backrooms/Source.md)
contains the complete patch, six changed native files, regression script, pins and hashes.
It is nested inside the source tree already shipped as `remixbinary/src/hw`, so packaging
needs no new source-bundle setting. The package index/binary still names the old R6 DLL until
Claude imports this candidate from its committed fixes worktree.

Claude's integration/QA steps:

1. Review the source commit, import only this DLL with `tools/inputs.py import fixes` from
   the committed fixes worktree's `out/r8-module` path. Re-run the Release gate and verify
   the deployment hash.
2. Load both gm_br_complex and gm_br_pitfalls with the existing gm_br_rtx add-on. Expect
   `[BRRTX] created: 1682 lights ...` or `2687 lights ...`, a nonzero active count and visible
   sphere/rect/disk fixture lighting. `brrtx_lights_debug 1` should show lights switching as
   the camera changes clusters, without the API-unavailable or light-failed messages.
3. Use `brrtx_vis pas`, `pvs`, then `all`; move into a different vis cluster after each switch.
   PAS should log that PVS rows became PAS, with `r_novis 0`, `rtx_patch_forcenovis 0` and
   `rtx_patch_vis_pas 1`. Verify a neighboring room contributes reflections, shadows and
   indirect light in PAS, beyond what PVS supplies. Record frame times at the same camera;
   `all` draws the full map and is expected to cost more. A convar read alone is insufficient.
4. Return to PVS, change maps, and repeat a map load. Check owned offsets are restored and no
   Backrooms settings or light handles leak into an ordinary map. Confirm expected return of
   gmRTX's own light updater, then exercise a listen server if server-side parity is needed.
5. On an ordinary map, exercise oversized non-flex models with `r_forcehwskin 0` and `1`,
   forced small models, flexes and first-person arms afterward. Check for palette/pose leakage,
   dynamic-vertex-buffer overflow, SEH diagnostics or new console errors. Also smoke-test RTX
   off. Keep the existing memory-limit compatibility notice/no-write behavior.

Rendered acceptance, actual engine signature matching and map/frame-time measurements remain
unverified until those game checks; R8-B's instructions prohibited launching the game.
