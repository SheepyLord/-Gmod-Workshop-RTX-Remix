# R20-T: the toolgun screen is nearly black at night

Worktree `out/worktrees/r20-toolgun`, branch `r20-toolgun`, from `main` (`9abffb7`, R20 merged and
published). Implementer: Codex (gpt-6.1-sol). Read first: `docs/handover/R20-plan.md` (the rules for
every task; the PoC lock), `docs/handover/R20-report.md`, `docs/handover/R20-Q-report.md` (the PoC QA,
with the toolgun view that was readable in fixed daylight), and the field QA report on branch
`r20-field`: `git show r20-field:docs/handover/R20-F-report.md` (evidence under
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r20-field\out\r20f\`, especially
`02-published-ui/shot-04-live_toolgun_first.png`, `shot-05-live_toolgun_second.png` and `console.log`).

## The problem

In the user's field game (published R20 package, loader 0.14.0, 3840x2160, DLSS and DLSS-G on, the
sky's clock at about 20:15-21:10, night), the Dynamic Toolgun Screen on the toolgun is nearly black:
the title bar, the large tool name and the readouts are barely visible, while the toolgun's frame and
the world around it are lit normally. Dynamic Toolgun Screen 1.3.1 (now bundled), Pocket PC layout,
`dts_backlight=1`, `dts_bg_dim=0`, `dts_resolution=512`, render target `dtscreen_screen512`. The
companion's `nativeloader_toolgun.lua` redraw ran (`[nativeloader] Toolgun screen` reports 464
captures and 232 draws), which is meant to draw the screen's texture unlit in the HUD pass after
upscaling, so a dark result suggests either the render target's content is dark or the redraw is not
what is seen. R20-Q's PoC check in fixed daylight was readable. The user's profile already had time
passing before R20, so this may predate the round; find out.

## What to do

1. Reproduce in the PoC (under the lock, as before; restore exactly): the merged package from `main`,
   loader 0.15.0, the sky at noon and at night (`nativeloader_sky_follow_map 0`,
   `nativeloader_sky_hour` 12 and 21, time stopped), DLSS on. Capture the screen view each time.
2. Find the cause. Ideas to check, not conclusions: what the render target holds (draw it unlit in a
   HUD corner, or copy it out); whether the companion's redraw is visible on top; whether the
   offscreen raster changes in runtime patch 0034 or the session's sky, fog or exposure state reach
   the screen's render-target draws or the HUD redraw; the same views with the v0.14.0 package
   (runtime before patch 0034), and with the standalone Dynamic Toolgun Screen alone.
3. Fix it so the screen reads like a lit display by day and by night, in RTX sessions and with RTX off,
   without changing how the screen looks by day. Keep the fix in the owning files (the companion's
   toolgun redraw, the bundled screen part's adapter, or the guard) with tests. If the cause is in
   the runtime, stop and report instead of changing it.
4. Evidence: before and after captures at noon and at night under `out\r20t\`, with the cause stated
   (file:line). `docs/handover/R20-T-report.md`; CHANGELOG `### R20` (additive); RESEARCH if you dug
   something up. `tools\test.ps1 -Config Release` passes before your last commit. Commit as the
   repository's git identity (SheepyLord, noreply) with the trailer
   `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`. Never push, merge, tag or publish;
   never touch the field install; never write `user.conf`. Keep PoC snapshots lean and delete your
   large copies once a restoration is verified (keep screenshots, logs and receipts): disk space on
   H: is limited.
