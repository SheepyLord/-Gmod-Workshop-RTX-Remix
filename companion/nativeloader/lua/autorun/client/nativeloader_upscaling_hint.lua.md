# nativeloader_upscaling_hint.lua

Client-only R20-B startup advice ([ADR 0117](../../../../../docs/decisions/0117-startup-upscaling-hint-and-sky-defaults.md)).
The companion loads this automatically in its RTX-only add-on. No command or manual invocation.

`nativeloader_upscaling_hint` is archived, default `1`; its translated checkbox follows Frame
generation in RTX Remix > Remix settings. `cl_showhints 0` also suppresses the hint. The first map's
first `PostRender` starts a 12-second minimum delay. The first-run guide, spawn/pause menus and
Remix's own menu defer the decision until the map is unobstructed; the current snapshot is read
after closing them, never queued from before an edit. An unavailable live readout is retried every
two seconds, at most 25 attempts (60 seconds when unobstructed). UI waiting spends no readiness
attempt and does no DATA/snapshot reads. Nothing runs in a render callback
except scheduling the timer. No snapshot, invalid state or unsupported hardware means silence.

The schema-1 loader status must report active RTX, a selected performance-tier adapter, NVIDIA's
vendor id (`4318`) and `non_nvidia = false`. Only recognized RTX 20/30/40/50 model names qualify.
DLSS-G is suggested only for an RTX 40/50 with a positive live capability flag. RTX 20/30 can receive
FSR 3 advice when its live capability flag is true. A file-only getter is never consulted.

## Live snapshot contract and current limitation

The optional native `RemixConfig.GetUpscalingState()` must return a fresh, atomic table:

| Field | Meaning |
|---|---|
| `ready` | Boolean true only after startup graphics/DLSS presets and pending option callbacks resolve |
| `upscaler` | Effective `rtx.upscalerType`, integer 0 through 5 |
| `frame_generation` | Effective `rtx.frameGenerationType`, integer 0 through 2 |
| `dlss_supported` | Boolean true only when DLSS is usable on the selected device |
| `dlss_frame_generation_supported` | Boolean true only when DLSS-G is usable |
| `fsr_frame_generation_supported` | Boolean true only when FSR 3 frame generation is usable |

`nil`, a raised error, `ready ~= true`, unknown enum values and absent capability flags never
produce advice about the corresponding feature. **The currently packaged native module does not
provide this function.** Its `GetConfigVariable` reads only `rtx.conf`, and the runtime's startup
log precedes device-dependent graphics presets. Production hints therefore remain silent until
that native contract is implemented outside R20-B's assigned Lua/docs/test paths. An injected
snapshot in QA demonstrates the consumer, not a live runtime readout.

## Lifetime and side effects

The marker `garrysmod/data/nativeloader_companion/upscaling_hint_start.txt` contains the loader's
process id and startup UTC. It consumes a successful decision (including both features on), an
opt-out/unsupported GPU, or an exhausted readout retry. It prevents a second hint when the Lua
realm restarts for another map; a new process startup UTC permits another. Failed marker writes
suppress the hint, and DATA/JSON/native read errors never interrupt the game.

One `notification.AddLegacy(..., NOTIFY_HINT, 18)` with three short lines and sandbox's water-drip
hint sound is emitted. Wording distinguishes upscaling off, frame generation off and both, with
DLSS-G/FSR 3 advice chosen by capabilities. All five messages and the checkbox are in all six catalogs.
The file writes no Remix option, `user.conf` or other settings file. No exit code; runs as game Lua.

Tests: [QoL harness](../../../../../tools/tests/companion_qol_harness.lua.md) and
[runner](../../../../../tools/tests/test_companion_qol.py.md).
