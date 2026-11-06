# 0117: A capability-aware startup hint and a running 20-minute sky day

- Status: Accepted 2026-11-06 for the Lua consumer/migration; the native live snapshot remains open
- Decided by: the user's R20 items 45 and 49; Codex choosing the implementation within R20-B's paths
- Builds on: [0020](0020-classic-rtx-settings-as-defaults.md),
  [0031](0031-physical-sky-time-and-weather.md), [0044](0044-remix-settings-persistence.md),
  [0105](0105-the-players-sky-applies-from-a-maps-start.md)

## Decision

1. The archived client defaults are `nativeloader_sky_time_passes = 1` and
   `nativeloader_sky_day_minutes = 20`. The 2–240 minute slider already contains 20 and keeps its
   existing range. Reset uses these same defaults. The sky still starts at the map's sun, or the
   player's chosen time; R16's ownership of a map add-on's sky is preserved.
2. `nativeloader_defaults.lua` migrates only a saved pair numerically equal to `0`/`30`. It changes
   both synchronously when `nativeloader_sky.lua` has created its ConVars, before callbacks and clock
   startup. It writes `nativeloader_companion/sky_defaults_client_v1.txt` whether it migrates or
   preserves the pair. Changing either setting preserves both; subsequent choices, including
   turning time off or choosing 30 minutes, are never migrated again. Missing ConVars defer marking.
3. The hint consumer waits 12 seconds after the first map draws and reads effective state after
   presets. It respects `cl_showhints` and the archived opt-out `nativeloader_upscaling_hint = 1`,
   offered beside Frame generation. Separate translated three-line sandbox notifications say
   whether upscaling, frame generation or both are off and point to RTX Remix > Remix settings or
   Alt+X. They use `NOTIFY_HINT` and the stock sandbox water-drip sound.
4. Advice requires active RTX in schema-1 status and a recognized selected NVIDIA RTX adapter, plus
   explicit live capability flags. DLSS-G requires RTX 40/50 and live support; RTX 20/30 can be
   offered FSR 3 when supported. Mixed vendor inventories do not prove the selected GPU is NVIDIA.
   Unknown hardware or unreadable state is silent. A `process_id`/`utc` DATA marker consumes the
   first decision (including both on or opt-out) across map changes, but permits a new game start.
   Readiness retries end 60 seconds after the first frame. Unwritable markers suppress notification.

## Correctness boundary discovered during implementation

The brief's getter assumption is false: `ConfigManager::GetConfigVariable` at the packaged
`packages/fixes/licenses/oversized-skinning/memory-limits/source/remixapi/remixapi.cpp:1111` parses
`rtx.conf` only. It cannot see the user layer, graphics/DLSS presets or Alt+X edits. The runtime's
`RtxOptionManager::logEffectiveValues` runs with no device, before later device-dependent preset
resolution. Neither is a reliable startup decision. Reconstructing state from files or saved RTX
tab drafts would violate the explicit requirement never to show a false hint.

The consumer therefore defines an optional atomic `RemixConfig.GetUpscalingState()` contract,
documented in [its reference](../../companion/nativeloader/lua/autorun/client/nativeloader_upscaling_hint.lua.md).
**No currently packaged provider exists. Production hints stay silent pending that native work.**
R20-B may edit only the named Lua, translations, tests and docs; the runtime, native fixes sources,
pins and packaged binaries are outside its assignment. This record keeps the necessary native
follow-up explicit rather than claiming the file getter is live. Injected snapshots exercise the
consumer in the harness and PoC; they are not evidence of native integration.

## Consequences

The sky change is independent of classic-default table versions and does not reapply other defaults.
Players retain changed pairs, and the clock migration cannot look like a deliberate sky takeover.
The hint reads no `user.conf`, changes no Remix setting, and never saves one. Its checkbox and every
new message/help/guide line use all six companion catalogs. The generic native readback and live
off/on PoC acceptance remain integration work; the shipped consumer's safe behavior on current
builds is silence.
