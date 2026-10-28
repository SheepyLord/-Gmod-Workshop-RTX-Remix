# 0006: Package precedence and planning rules

- Status: Accepted 2026-10-27
- Decided by: Claude, implementing M2 within the plan the user approved; open to the user's review

## Context

Several allowlisted sources can offer packages, and they can disagree: a development copy of the
runtime next to the Workshop release, two different runtimes, two packages writing the same mod
folder. The loader needs rules that are predictable, never pick "whatever loaded first", and always
say why something was not used. They must work without the Steam API (not yet initialised when the
bootstrap runs) and must not silently fall back to running nothing when a working package exists.

## Decision

`nl::planner::make_plan` applies these rules to the candidates in precedence order: development
folders, then local archives, then Workshop items, each group in the order of `config.json`.

1. `enabled: false` in the config: nothing is active.
2. A candidate that could not be found or loaded (not installed, disabled in GMod's addon list,
   damaged archive, invalid manifest) is skipped with that reason.
3. A package whose `requires_loader` is newer than the loader is skipped.
4. A package id that is already active is **shadowed**: a development folder overrides a local
   archive, which overrides the Workshop, whatever the versions. A higher-precedence copy that is
   itself skipped does not shadow anything, so a broken dev folder falls back to the working
   Workshop copy, and the plan shows both decisions.
5. Only the first active `remix-runtime` package is active; later runtimes are skipped.
6. A package whose root files overlap an active package's root files is skipped.
7. An active runtime is loaded only if `remix.enabled` is true; otherwise it stays planned with a note.

`nlctl plan <game root>` prints these decisions without changing anything.

Workshop discovery without the Steam API: the library is the one the game root sits in
(`<library>\steamapps\common\<dir>`), else the one `libraryfolders.vdf` lists for app 4000; an item
folder must hold exactly one `.gma` or `*_legacy.bin`; GMod's `cfg\addonnomount.txt` disables items;
`appworkshop_4000.acf` supplies the installed version (`timeupdated`, `manifest`).

## Consequences

- A developer can test a runtime by allowlisting a folder, without unsubscribing from the release.
- Version numbers never override precedence. Comparing versions across sources would let a stale
  Workshop item with an inflated version beat a deliberate local choice.
- Every skipped candidate carries a human-readable reason, which `status.json` will expose to the
  Lua companion (M5).
- Shadowing by id only works if ids are stable; renaming a package id makes the two copies
  independent, and rule 5 or 6 then decides.

## Alternatives considered

- **Highest version wins**: surprising during development, and lets any allowlisted source override
  the others by bumping a number.
- **Any conflict disables all involved packages**: safe but leaves the user with nothing for a
  harmless duplicate.
- **Ask the Steam API for subscriptions**: unavailable before the engine starts, and subscription is
  not consent to run native code anyway (ADR 0003).
