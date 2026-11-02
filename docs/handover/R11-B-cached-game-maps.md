# R11-B: imported game maps that survive a missing source folder (brief)

Read [AGENTS.md](../../AGENTS.md), [R11-report.md](R11-report.md), [R11-A-report.md](R11-A-report.md),
[ADR 0091](../decisions/0091-automatic-pbr-fallbacks.md) and [ADR 0092](../decisions/0092-generated-fallback-mods-rank-last.md).
You (Codex) built R11-A's imported game PBR; this follows it up.

**Where you work.** This repository: branch `r11-cache` in `out/worktrees/r11-cache` (from `main` at
`49117ec`). The RTX fixes: the existing worktree `out/worktrees/r11-fixes`, branch `codex/r11-autopbr` (at
`1679a99`, the shipped DLL's source, with its prepared build environment); add your commits there.
**Owns:** that fixes branch (ToPBR native and Lua), `packages/fixes` (the rebuilt DLL and the changed files
only, imported one by one with `tools\inputs.py import fixes --file`; refresh the GPL source copy in
`packages/fixes/licenses/oversized-skinning/autopbr`), tests, an ADR 0093 (or an addition to the R11
records if smaller), CHANGELOG (an `### R11` line), RESEARCH/TESTING facts. **Does not touch:** `runtime/**`,
`loader/**`, `glass/**`, `companion/**` unless a setting text must change, other parts, the field install,
the Workshop, `origin` of either repository.

## The user's request (2026-11-02)

After R11, Claude reported that the field library's five Wuthering Waves and Silver Palace characters keep
their old look because the `Desktop\test_models` folder they were imported from is gone (25 of the 45
recorded sources still exist), and asked "Keep game maps working after a character's source folder is
gone?". The user: "Yes, do it here".

## What Claude found

- `cl_rtx_topbr_conversion.lua` (the "Imported game PBR" loop at its end) queues a hotloader material only
  when its library entry has a non-empty `source` and the material a `base`; native `QueueGameMaterial(name,
  source, base)` then reads the PMX (UV protection) and the sibling maps, writes content-keyed DDS (keys
  contain source bytes, generator version and recipe) and registers the material for the live hash each
  session. With the source gone nothing is generated or published, although the DDS files from earlier
  sessions are still in `rtx-remix/mods/~gmod_topbr/textures`.
- The hotloader names its textures by content (`mmd/t/<16 hex>`), and the live Remix hash of the same
  content stays the same.

## What to build

1. When a game material is generated successfully, record what was published for it (the live hash, the
   hotloader texture identity, the DDS files and the material's values) in a small persistent registry
   beside ToPBR's output, written atomically.
2. When a hotloader material's source is missing or unreadable (or its library entry has no source but the
   registry knows its texture), republish the recorded material for the current live hash, provided the
   texture identity matches and every DDS still validates. Never guess for a texture the registry does not
   know. Queue such materials from Lua without a source.
3. Everything else stays as R11-A built it: the setting turns these off too; authored replacements still
   win (the guard and runtime patch 0020); faces/eyes stay untouched; a present source always regenerates
   (a changed recipe or source takes over the record); bounded work; entries whose files are gone are
   dropped. A record keeps working after a generator update (without its source it cannot be regenerated,
   and dropping it would lose the character's maps again), unless the record's version is below a minimum
   that a future fix raises for records known to be wrong. Clearing ToPBR's cache keeps the registry for
   the same reason (record what you decide).
4. Tests: the registry's write/read, identity mismatch, missing/invalid DDS, setting off, authored-hash
   exclusion; the Lua queue without a source.
5. PoC QA: import a game character from a **copy** of its folder under this worktree's `out\` (for example
   copy `E:\G\Upload\Alf` there; never touch `E:\G\Upload` itself), let it convert, quit, rename the copy so
   the source is gone, start again: the same number of materials publishes and the character looks the
   same as with the source (screenshots, on/off); with the setting off, nothing. Restore the PoC afterwards.

## Rules for this run

- The PoC lock is `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock` (create it exclusively;
  delete it when the PoC is back on its Workshop-only config). Close a running PoC game if needed (prefer a
  console `quit`). A field game may be running (the user or another tool started it): never end, focus or
  send input to it. Never write the field install, Steam's files or a Remix `user.conf`. `-multirun` always.
- No questions to the user. Commit on `r11-cache` and `codex/r11-autopbr` with
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`; never push, merge or publish. One DLL import at
  the end (Git LFS storage is never freed). `tools\test.ps1 -Config Release` passes.
- Write `docs/handover/R11-B-report.md`: what you built, the evidence, the DLL's size and SHA-256.
