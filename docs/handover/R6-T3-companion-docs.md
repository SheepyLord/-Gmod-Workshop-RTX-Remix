# R6 T3: companion telemetry and tier line, troubleshooting guide, skill guidance

Read [R6-plan.md](R6-plan.md) first: its rules, decisions and interfaces bind this task. Background in
[R5-stability-proposal.md](R5-stability-proposal.md) proposals 5 (part 2) and 11, and sections 1.7, 2
and 4. Branch `r6-t3-companion`, worktree `out\worktrees\r6-t3-companion`. No ADR needed unless you
make a design decision; then ask in your report rather than numbering one.

## 1. Remix VRAM by category (proposal 5, part 2)

When the RTX fixes module exposes `RemixResource.GetVramStats` (check its Lua bindings in
`packages/fixes` and in the fixes' source, `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed`, read
only), the companion appends a line every 30 s to `garrysmod\data\native-loader\vram.csv` (interface
I6): time, the driver's budget and use, DXVK's totals and each category the call returns (the field list
is in the runtime's `public/include/remix/remix_c.h:1025-1053`). Keep it bounded (about two hours,
rotate). A client setting turns it off (default on; name it like the companion's other settings).
Without the function: do nothing, silently.

## 2. The performance tier in the RTX Remix tab

Show the loader's tier (interface I2, `status.json` `activation.performance_tier`, which the companion
already reads status from; T1 writes it) as one line in the RTX Remix tab: the tier, why (the adapter
and its memory), and how to change it (`native-loader\config.json` `remix.performance_tier`; a start is
needed). When the field is absent (an older loader) show nothing. Companion strings go through its
gettext catalogs (`companion/i18n`, all seven languages; agent-written translations marked as such).

## 3. Troubleshooting guide (proposal 11)

A page in the companion's guide (ADR 0022) and a matching `docs/` page for players with 8 GB GPUs or
16 GB of RAM: a system-managed page file on a drive with at least 30 GB free; close browsers and OBS
recording; watch Task Manager's "Committed"; frame generation off; keep the game's texture detail at
its highest (lowering it changes Remix's texture hashes); what the tiers do and how to override them;
where the evidence folders are (`native-loader\logs\sessions\`, T2) and what to send after a crash
(section 1.7's list, minus anything the loader now keeps automatically). Link it from the RTX Remix tab.

## 4. Docs and skill

- `docs/TESTING.md`: how testers read memory (`rtx_vram_stats` from the fixes module, `memory.csv`,
  `vram.csv`, `dxvk.hud = memory` in the root `dxvk.conf`).
- `skills/mmd-remix-pbr/SKILL.md` (and its references if they hold the publish steps): characters meant
  for players with 8 GB GPUs are published with `--max-size 2048`; explain the cost of 4096 px maps.

## Tests, limits

- Extend the companion's LuaJIT harness tests (`tools/tests/test_companion_*.py` style) for the vram
  sampler (with and without the function, rotation) and the tier line (present, absent); run
  `companion_i18n.py check` and the addon i18n checks.
- Do not touch `loader/`, `packages/`, `runtime/`. No version bump. You may not launch the game.
