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
