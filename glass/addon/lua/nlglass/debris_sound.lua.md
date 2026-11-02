# debris_sound.lua

Client-only native contact/split/water sound consumer. `Drain(api)` reads the fixed native event
buffer only at an idle worker boundary. Positional stock glass sounds are culled beyond 1536 units,
limited to four per rendered frame and 24 per second (burst 24), and separated by 0.12 seconds per
piece. Impact speed and mass select soft/hard sounds and bounded volume; splitting plays a quiet
sheet-break sound. The archived `rtx_glass_debris_sounds` setting and local reset control it.
`Clear()` resets counters and bounded per-piece rate state. No files, network or Source physics.
No process exit codes. Native capability absence keeps the older fallback silent.
