# vram_probe.lua

Client Lua for `poc_session.py run --lua tools/qa/vram_probe.lua --settle 5` or an explicitly
sent probe in an owned PoC session. `NL_VRAM_LABEL` optionally labels the snapshot.

Reads loaded hotloader metadata and Remix VRAM categories; when the local QA `nlvramprobe`
module is available, enables Source debug texture collection for one second, then disables it
and prints one `R12_TEXTURE <label> <JSON>` line per engine record. Also prints `R12_CONTEXT`,
`R12_VRAM`, probe availability and `R12_CENSUS_DONE`. No material is looked up, loaded or tracked.
`R12_ABI` records the optional native pin/method identity. `R12_PROBE.root_present` distinguishes
the public debug list from the SHA-pinned registry fallback; a truncated/unstable traversal is
explicit and the evidence reader rejects it. Source record `Size` is in bytes, not KiB.
It requests the opt-in runtime allocation snapshot (`rtx.profiler.memory.requestSnapshot`,
NoSave); a runtime without patch 0021 refuses it harmlessly. Start the diagnostic runtime with
`RTX_PROFILER_MEMORY_ENABLE=1` for allocation rows in its log. See
[build_vram_probe.ps1](build_vram_probe.ps1.md) for native instrument setup and limitations.

Inputs: game metadata, the native probe and Remix APIs. Output: current-session console lines;
no files/settings are written. Missing native support still reports Remix categories. The optional
require searches only the QA module name and never a material. No exit code (Lua); the driver
records normal exit/errors. Do not install the native instrument in the field game.
