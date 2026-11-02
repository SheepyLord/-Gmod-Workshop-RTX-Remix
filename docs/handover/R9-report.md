# R9: the user's glass report of 2026-11-02 (report)

[Plan](R9-plan.md), Codex's [R9-G report](R9-G-report.md), [ADR 0087](../decisions/0087-glass-shards-and-environment.md).

## CI, the release and the branches

- **CI** on `main` had been red since R7, from two intermittent failures. Both are fixed at the cause:
  - `nl_glass_tests`: the cloud session's `538cf7a`. Dropped catch-up steps left Source mirrors
    behind; the game hit this too.
  - `nl_exit_observer_integration`: a clock race, fixed by `a0573f8` (see RESEARCH, "R8 CI: the exit
    observer and the coarse clock"). The observer refused a session start that preceded the game's
    creation time; the start is read from a coarse clock, the creation time from a finer one. A
    refusal now names its reason and costs start-up no wait.
  - `main` was green on `ae2e2c3` (run 41366571419).
- **`v0.12.1`** was moved to `ae2e2c3` (force-pushed, as the user asked). Its tag build passed (run
  41367450082) and published "Native loader v0.12.1", marked latest, with
  `gmod-native-loader-0.12.1+ae2e2c30.zip` and its symbols.
- **Branches.** Only `main` remains, on GitHub and locally. The remote `claude/brave-davinci-k3y6ym` was
  merged; the cloud session's `claude/sweet-cori-iqcvoh` was superseded by `a0573f8`. All 68 branch
  tips are recorded in `out/branch-backup/2026-11-02/branches.txt`. The two unmerged ones are in
  `unmerged.bundle`: `r4-companion` (one R4 harness commit) and `sweet-cori-iqcvoh`. The 63 worktrees
  under `out/worktrees` and `.claude/worktrees` are detached with their files kept (283.5 GB);
  `r7-alpha` holds the runtime source with patch 0018.
- **Field.** Loader `0.12.1+2b543006` (the release's loader code) is installed, the 0.12.1 build it
  replaced is in `out/field-backup/2026-11-02-r9-observer`. Two starts: `exit observer ready`,
  `window ghosting off`, normal quits, and package `0.0.0-dev.20261102001953+4ce30d5a` (the melee fix).

## The melee error

`ae2e2c3`. A bullet penetration add-on traces with a function filter. The melee observer passed it to
`IsValid`, which indexes its argument; the error surfaced through that add-on's `util.TraceLine` call.
Only entities reach `IsValid` now, and each observation runs under `pcall`. The test harness's `IsValid`
throws as GMod's does: the old file fails the new check.

## Glass (R9-G)

Codex implemented the six items on `r9-glass` ([report](R9-G-report.md)). Claude's review found
tempered glass breaking into long slivers and seams: random cut directions often ran along a cell's
long side. `8536fb0` cuts across the longest extent of six seeded directions, so tempered glass dices
into compact, irregular granules. The rebuilt module (SHA-256 `327ddf26...`) is imported in `e5fa347`.

PoC QA, gm_construct, RTX on, package `0.0.0-r9.claude1` with that module (`out/qa-poc/r9`):

| Check | Result |
|---|---|
| Look (01) | Annealed: a bullet hole with radial cracks left in the frame, and very small crushed pieces. Tempered: the whole pane shown as granules in the frame of the hit, then a spray of small irregular pieces; an irregular pile settles |
| Latency (03) | Four spawned breaks, pistol and SMG: hole built 3.8-7.4 ms after the client receives the hit, hole and first pieces drawn in that same frame; last physics body 77-124 ms later |
| Velocity (04) | Five cases (props at 250, 700 and 3,600 units/s, a running player, a bullet): 0.6-3.1 % slightly negative samples, at worst 20 units/s backwards (tumbling and contacts); nothing launched backwards |
| Explosions (07) | `util.BlastDamage`, `env_explosion`, a grenade, a barrel and an RPG, none damaging anything else: each reached the pile, woke it and split pieces |
| Water (07) | 25 pieces dropped into gm_construct's pool: mean vertical speed -134.5 units/s in the air, -24.4 and -33.1 units/s after entry |
| Sounds (07) | All nine stock glass sounds exist in vanilla GMod; impacts, landings and splits played within the limits |
| Clear buttons (07) | Own: 25 pieces to 0. Everyone: present for the listen host |
| Performance (05, 06) | 50 panes: falling 14.88 / 11.96 ms mean (p99 62.6 / 40.9 ms) against settled 8.80 / 8.49 ms: +6.1 and +3.5 ms. Target: at most +8.5 ms, p99 at most 67 ms |

Notes:

- About 0.6 s after a break, a soft dark patch shows where the pane was; it is gone by the time the
  glass settles. This is probably Remix's denoiser history, or the stock `GlassImpact` effect.
- Session 02 crashed at engine start-up (`0xC0000005`), before any Lua or glass code ran. This is the
  intermittent Remix start-up crash from R8 that the user deferred. The rerun (07) passed.
- Not run: two clients, map windows on other maps.
