# build_vram_pressure.ps1

Builds `vram_pressure.exe` from [`vram_pressure.cpp`](vram_pressure.cpp) (R13-B,
[ADR 0100](../../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)): a QA tool that
holds video memory in its own process, meant to make Windows lower the memory budget of a game running
beside it.

**Measured (R13-B, RTX 5090):** it does not. With 25.8 GB held beside a foreground PoC session, WDDM
lowered the game's budget only to the game's own usage (26.15 GB with 26.14 GB used) and paged the
tool's memory instead (the tool's own budget fell to 6.9 GB). Use the runtime's test budget,
`DXVK_TEXTURE_PRESSURE_TEST_BUDGET_MIB` (patch 0026), to test replacement textures under pressure; the
tool remains useful to see how the driver shares memory between processes.

```powershell
tools\qa\build_vram_pressure.ps1 [-Out out\r13-b\gpu-probe]
vram_pressure.exe <GiB to hold> <seconds>
```

The build uses MSVC with `d3d11.lib`/`dxgi.lib`; output and compiler scratch go to `-Out` (default
`out/r13-b/gpu-probe`); the caller's environment is restored. Exit 0, or nonzero on a compile failure.

The tool picks the adapter with the most dedicated memory, creates 256 MiB render targets until it holds
the requested amount, clears each twice a second so they stay resident, and after `seconds` releases
them. It prints one JSON line at the start, after allocating, every five seconds and at the release:
the UTC time, the bytes held and its own DXGI local budget and usage. Exit 0; 1 without an adapter or
device; 2 on bad arguments. It writes no files. End a running field game before using it: the field game
is a test session (the user, 2026-11-02), and the pressure would reach it too.
