# memory_report.py

One game session's RAM and VRAM, for R13's memory measurements
([ADR 0101](../../docs/decisions/0101-memory-profiles.md)). It only reads the telemetry the loader and
the companion already keep, so it works on the PoC and on the field install alike:

- **RAM:** the loader's memory telemetry, `native-loader\logs\memory.csv` and `memory.1.csv`, a sample
  every 10 seconds ([ADR 0063](../../docs/decisions/0063-local-session-evidence-and-memory-telemetry.md)):
  the game's private (committed) bytes and working set, system commit, and the GPU's local usage and
  budget.
- **VRAM:** the companion's telemetry, `garrysmod\data\native-loader\vram.csv` and
  `vram.previous.csv`, a sample every 30 seconds: the driver's allocation and budget, DXVK's used and
  allocated memory, game textures, replacement textures, render targets, acceleration structures,
  opacity micromaps and buffers.
- **Census** (optional): an address-space census of a running game with `VirtualQueryEx`. It gives
  committed memory by type (private, mapped, image) and private memory by protection (read-write,
  write-combined, ...) and by allocation size. The process is opened with
  `PROCESS_QUERY_INFORMATION` only, so no memory is read.

```powershell
python tools\qa\memory_report.py --root H:\SteamLibrary\steamapps\common\GarrysMod_PoC --since 2026-11-03T10:00:00Z `
    --phase idle=2026-11-03T10:05:00Z/2026-11-03T10:06:00Z --phase spawned=2026-11-03T10:08:00Z `
    --census-pid 12345 --out out\r13\minimum-run.json
```

| Argument | Meaning |
|---|---|
| `--root` | The game root, the folder that holds `gmod.exe` |
| `--since`, `--until` | The session's window, UTC (`2026-11-03T10:00:00Z`); `--until` defaults to the last sample |
| `--phase NAME=START[/END]` | A named window inside the session, UTC; repeatable. Without an end it runs to the last sample |
| `--census-pid PID` | Also census this running process |
| `--out FILE` | Also write the report there |

Output: JSON on stdout (and `--out`). `phases.session` and each named phase list the sample counts and,
for every measure with samples, `peak_gb` and `last_gb` (decimal gigabytes). Samples outside a
window, unreadable times and empty counters are left out.

Side effects: none besides `--out`. Exit codes: 0 report written; 1 no RAM or VRAM sample in the
window, a census that cannot open the process, or an unreadable file; 2 bad arguments.

Tests: [test_memory_report.py](../tests/test_memory_report.py.md).
