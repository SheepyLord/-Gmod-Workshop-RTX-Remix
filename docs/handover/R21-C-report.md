# R21-C report: the GPU timeout during a map load at 3840x2160 (closed by the user)

Brief: [R21-C-device-loss.md](R21-C-device-loss.md). Codex (gpt-6.1-sol) ran the trials; Claude wrote
this report after the user closed the task: "The problem is considered not reproducible, end the Codex
sessions and finalize". The cause is **not established**; nothing in the package or runtime changed.

## The field report

The user's field start of 2026-11-06 22:57 (everything the loader deploys removed, no `rtx.conf` or
`user.conf`, map gm_poolrooms, 3840x2160) looked stuck on the map load. It was a GPU timeout: Windows
logged nvlddmkm event 153 at 22:59:45 and 22:59:47 (this machine's WER LiveKernelEvents for these are
code 141, a video engine timeout and driver reset), about three seconds after the map's first ray-traced
frames (NRC activated 22:59:42); Remix reported `VK_ERROR_DEVICE_LOST` at 22:59:50 (frame 4529, 6.5 GB of
32 GB in use) and opened its "RTX Remix Crash Report" GPU-crash prompt, which held the game on the loading
screen until Claude declined the upload. The loader's fresh deployment had completed (35 s) and
activated the package. Evidence: `out/field-stuck-20261106/` in the main checkout.

## The trials (PoC, 3840x2160, gm_poolrooms, the published package, Aftermath on)

Each batch moved the PoC's own trees aside, deployed the uploaded package fresh, copied the field's map
add-ons, mounts and settings read-only, and ran cold starts from the menu to the map. Evidence under this
worktree's `out/r21c/` (logs, session records, crash records; the snapshot copies were deleted after
the verified restorations).

| Batch / trial | Result |
|---|---|
| `baseline-a` 01-03 | No map reached (harness setup runs); not counted |
| `baseline-b` 01, 02 | Map loaded (their screenshots failed: no Pillow in that Python) |
| `baseline-b` 03 | **GPU timeout**: nvlddmkm 153 at 23:35:45 and 23:35:47, `VK_ERROR_DEVICE_LOST` at 23:35:50, frame 4110, 34 s after start, after the map command and **before any ray-traced frame of the map** (no acceleration structures, no Opacity Micromaps, 3.7 GB in use); the crash prompt was declined. Aftermath was enabled ("Aftermath enabled") but **wrote no dump** |
| `formal-a` 04, 05 | Map loaded, no loss |
| `formal-a` 06 | Stopped when the user closed the task |

So one timeout in five counted 4K starts, and it came before NRC, Opacity Micromaps or the map's
geometry were in use: those leads from the field's timing are weaker than they looked. With R20-A's two
PoC losses (2026-11-06 03:51 and 03:54) this is the fourth GPU timeout at 3840x2160 around a map load on
this machine; nvlddmkm logged 74 such errors in the 14 days before. Nothing here separates a runtime
fault from a driver or hardware one, and no A/B was reached.

## What was added

- `tools/aftermath_decode.py` (with its `.md` and `tools/tests/test_aftermath_decode.py`): decodes an
  Aftermath `.nv-gpudmp` with the runtime's own `GFSDK_Aftermath_Lib.x64.dll` to the SDK's JSON and the
  active shaders' hashes. Checked on NVIDIA's example dump; it had no dump of ours to read.

## Cleanup

Claude ended the Codex worker and its batch mid-trial (the PoC kept launching), then repeated the batch's
own restore from its snapshot: 4,200 files equal, the video registry values restored, the lock released;
`tools/steam/verify_install.py` on the PoC passes (only `autoexec.cfg`, a user file, differs from the
depot, as before). The field was read only; no system setting changed.

## If it is picked up again

Why Aftermath wrote no dump on a TDR is the first question (a driver reset may end the process before the
dump callback runs; `dxvk_instance.cpp:359` names the file). Then a larger count per configuration,
including 1600x900 and the main menu alone, would show whether the timeouts follow the resolution, the
map load or the machine.
