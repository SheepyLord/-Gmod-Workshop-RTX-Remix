# R9: the user's glass report of 2026-11-02 (plan)

The user's request, after loader 0.12.1 was tagged (`v0.12.1`) and its tag build failed on CI:

- Move `v0.12.1` once the build is green and delete every branch but `main`. The build had been red since
  R7, and the cloud session working on it was not making progress: fix the failing build.
- Then fix six glass problems:
  1. "Glass fractures' break down is always square and uniform, and it could not be broken down into
     very small pieces. Make the breaking of glass fracture realistic."
  2. "There is a highly visible latency when the bullet (the window take damage) and the window start to
     break."
  3. "Glass fracture has no sound effect when interacting with the world, when broke or collision."
  4. "Glass fracture has no buoyancy and does not interact with explosions."
  5. "The velocity transfer is not stable enough, the glass can fly out in reverse."
  6. "Add a button in the menu to clean up the broken glass."
- A pasted Lua error from the field: `[nlglass] lua/includes/util.lua:320: attempt to index local
  'object' (a function value)` from `IsValid` in `debris_melee.lua:73`, through
  `universal_bullet_penetration.lua`'s bullet callback.

Standing permissions (the user, 2026-11-01): close, launch and update the PoC and the field game without
asking; decide with Codex instead of asking; push `main` and update the Workshop when done.

## Done by Claude before the glass work

- **CI.** Two intermittent failures since R7. The cloud session fixed the glass one (`538cf7a`: dropped
  catch-up steps left Source mirrors behind). The exit observer one was a clock race: `a0573f8` (see
  RESEARCH, "R8 CI: the exit observer and the coarse clock").
- **The melee error.** `ae2e2c3`: only entities reach `IsValid`, and observations run protected.

## The glass work

One brief, [R9-G](R9-G-glass.md), for Codex. The six items share `glass/**` (the fracture, the native world,
the debris manager and the menu), so one worktree and branch: `r9-glass` in `out/worktrees/r9-glass`.
Claude reviews, runs the in-game QA on the PoC, imports the rebuilt module, merges, publishes and checks
the field.
