# R14 plan: noclip and glass, and a redesigned guide

Started 2026-11-03 by the scheduled task `r14-after-r13`, after R13 was done. Branch `r14`, worktree
`out/worktrees/r14`. Claude does the work; Codex may be given only translation and text-validation tasks
(the user's words).

## The user's items (verbatim, 2026-11-03)

> 41. No-cliping and fly through glass make fractures on the glass, which is not an expected behaviour.
>
> 5: Redesign and greatly enhance and Refine the help document and the wording in the help section to make it natural, logical and detailed. More labeled, guided screenshots (like arrows in the screenshot) are needed to navigate user around the setting and functions of RTX-Remix. Only assign translation and text validation tasks to Codex for this session.

## Plan

1. **Item 41.** `glass/addon/lua/nlglass/server.lua`: a player in `MOVETYPE_NOCLIP` is ignored by `S.Body`
   (touch and physics contact) and by the `SetupMove` sweep, so it never fractures glass.
2. **Item 5.** `companion/.../nativeloader_guide.lua`: restructure the guide into task-ordered pages
   (first steps, where each setting lives, the Remix menu, sky and lights, characters, glass, memory,
   troubleshooting), natural wording, step lists, and annotated screenshots (numbered arrows and labels
   drawn by a reproducible script from real in-game captures).
3. Translations and text validation (Codex only): the new guide strings in the six catalogs, and a
   read-only check of the English wording.
4. Docs duties, `tools\test.ps1 -Config Release`, report, merge, push, field check.

## Continued in the main session (2026-11-03)

The scheduled session merged a first pass (`1cd57a7`): the noclip fix and a guide with five annotated
pictures. Its report lists what it left open: four panels without pictures, no check in a running game,
no wording check, and no Codex translation pass. Then the user asked, verbatim:

> Please proceed to R14 here, launch sub agent if needed.

Claude continues R14 on `r14-int` (worktree `out/worktrees/r14-int`, from `1cd57a7`):

| Task | What | Who |
|---|---|---|
| R14-G | Item 41: noclip, flying and spectating never fracture glass; proven in a running PoC game, with a control that still breaks a pane | Claude (main) |
| R14-H | Item 5: the guide and the help wording redesigned, with sharp labeled screenshots of every place a player goes ([brief](R14-H-guide.md)) | Claude subagent, `out/worktrees/r14-guide` / `r14-guide` |
| R14-T | Item 5: the translations of the new text into the six languages and a text-validation pass of the English and the translations | Codex (only these, as the user said) |

Two other sessions run at the same time, started by the user from R13's follow-ups: the runtime's
option-system crash (runtime patch 0029) and streaming rpai and ToPBR maps instead of preloading.
R14 does not touch the runtime, rpai or ToPBR. The PoC lock (`out\r10\poc.lock`) serializes PoC use.
