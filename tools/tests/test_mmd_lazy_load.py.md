# test_mmd_lazy_load.py

R13-A ([ADR 0099](../../docs/decisions/0099-saved-characters-load-on-first-use.md)): saved NPC and
player-model characters are published from metadata and load at their first use; the most recently
used stay ready. Runs [mmd_lazy_load_harness.lua](mmd_lazy_load_harness.lua.md) with LuaJIT through
unittest discovery, once per scenario.

Builds one snippet of production code (the real `mmdhl.MountPackage` from `autorun/mmdhl.lua`,
`RememberRig`/`ForgetAssetRigs` from `carrier.lua` and `GetRigForModel` from `materials.lua`) and lets
the harness load `actors.lua` (with the ready set, `mmdhl.readiness`), `persistence.lua` and (server)
`sharing.lua` whole. A second test checks that the map-start restoration hands every saved entry to
`mmdhl.RestoreActors`, and that no new bundled Lua file was added (the companion's render guard
lists every bundled Lua path, ADR 0086).

R13-A also added load-time stubs for the two server ConVars (`CreateConVar`, `cvars`, `FCVAR_NONE`)
to the R10-H and R12-A harnesses ([mmd_morph_harness.lua](mmd_morph_harness.lua.md),
[mmd_reimport_harness.lua](mmd_reimport_harness.lua.md)), which load `actors.lua` too.

Scenarios: no memory profile (nothing mounted or precached, every entry published), a profile's
count and MiB cap (the newest that fit; an oversized one passed over), the ConVar override applied at
once, first use through `SetModel` (the NPC tab, the player's model with its arms) and through
`util.PrecacheModel`/`util.IsValidModel`, the use record and its fallback (the native module's name
records), a map change, deletion, and the client: host entries published without mounting, names
renewed without mounting, menu icons that never give `ModelImage` a model nobody showed, a
`ClientsideModel` preview mounting its carrier, and a remote client that still mounts at registration.

Writes the snippet to a temporary folder in `out/tmp` and removes it. No game or installed data is
touched. Requires LuaJIT (otherwise one explicit skip). Exit 0 on pass, nonzero on an assertion, a Lua
error or a timeout.
