# QoL report: complete interface translations

2026-10-30. Implemented on `codex/translation-review`, from `main` at `7d79c12`.
The user expanded the audit to every bundled add-on interface. The implementation is recorded in
[ADR 0038](../decisions/0038-complete-bundled-interface-translations.md).

## Result

The requested Simplified Chinese, Traditional Chinese, Japanese, Korean, French and Russian catalogs
have complete key coverage. Existing Arabic and Spanish Motion Importer catalogs also pass validation.
There are **47,918 non-English catalog entries** across these components:

| Catalog | English keys | Translation coverage |
|---|---:|---|
| Companion tab, guide and notices | 169 | six languages |
| Newly localized bundled interfaces | 472 | six languages |
| Remix runtime | 3,298 | six languages |
| Bodygroup Tool | 104 | six languages |
| Destruction | 204 | six languages |
| Material Editor | 1,141 | six languages |
| Material parameter help | 83 | six languages |
| Motion Importer | 364 | six languages plus Arabic and Spanish |
| Model Hotloader | 2,030 | six languages |

Added Korean to Destruction and distinct Traditional Chinese catalogs and selectors to Bodygroup Tool,
Material Editor, its parameter help, Destruction and Motion Importer. Localized water, glass, portal,
light, sky, progress, context-menu and debug interfaces that previously had no translation path.
Tool IDs, convars, preset keys, filenames and user-provided model/bone/bodygroup names stay literal.

Wording fixes include the eclipse-progress label, the Korean waxing-moon typo, French sky-control
instructions, Russian sky descriptions, radiance-cache terminology, and 13 count-dependent messages.
English labels now describe glass strength, collision cost and airborne droplets clearly. Motion-wheel
state notices are localized in all its languages. The guide reflects frame generation being off by
default and names the corrected migration button.

Material Editor's reverse lookup was leaving generic labels in English when one locale used different
words for the same term. Colour, Texture path and Strength now agree, and Edit buttons carry explicit
context. Long spawn-menu slider/combo labels use a full-width line; checkboxes wrap. The user explicitly
accepted resizing the **Remix** settings window to reveal long labels, so those full labels are retained.

## Implementation

- `companion/i18n/addons`: reviewable PO sources for the newly localized interfaces, separate from the
  companion namespace. The packager embeds both and ships the GPL-derived catalog sources and license.
- `tools/companion_i18n.py`: strict release checks for missing, empty, fuzzy, duplicate, stale and
  unreviewed English entries; format checks and an explicit draft fallback option.
- `tools/check_addon_i18n.py` and LuaJIT harnesses: native catalog coverage, placeholders, language
  routing, context-sensitive labels, metadata language changes and localized client notices.
- Indexed package inputs retain their licenses and original line endings. Changes to GPL add-on code
  remain in that package part; the derived catalog data carries GPL-2.0 with editable source copies.
- Runtime patches 0005 and 0006: translated weather status values, clear cache names, strict catalog
  embedding, and static migration-button labels with separately formatted counts. The previous
  concatenated “Migrate 83 Developer Settings…” text bypassed lookup. Both migration directions are
  covered, and their behavior is unchanged. No migration button was clicked during testing.

## Validation

- `tools/test.ps1 -Config Release`: all checks passed, including **17/17 CTests** and **248 Python
  tests** (seven expected skips). Final CTests passed again with `--parallel 2`; final Python checks
  passed through `tools/test.ps1 -SkipNative`. The localization subset has 13 passing tests.
- `tools/check_addon_i18n.py`: **0 problems**, including real language-selection and label-switching
  assertions. Catalog exceptions record the exact intended English text, not just a reusable key.
- Runtime `build_runtime.ps1 -Verify`: the worktree matches the base and all six patches, pinned
  submodules and clones. Runtime catalog regressions: **5 passed**. The embedder validated every
  printf conversion and glyph in all **3,298 × 6** translations. The final UI-only incremental build
  used `meson compile -j 2`; shader sources had not changed. Imported DLL SHA-256:
  `7077609e831899082c861c511e75aa3f65ccbb4624bb1212deb07f224c6c133e`.
- Package builds passed `nlctl` validation. The final tested package is
  `0.0.0-dev.20261030111451+a239d15c`, 917 payload files, content digest
  `34dd032a342b7d7a` (prefix). Added files are the translation sources and license.
- PoC `ui-final`: **6,850 text elements** inspected across English and the six requested languages,
  **0 builder errors**, **0 Lua errors**, map loaded, runtime active, normal console quit, exit 0.
  The six apparent `Hair` matches are stored bodygroup filter identifiers, displayed verbatim by
  `cl_90_settings.lua:307`; translating them would change which model part the filter matches.
- All six runtime fonts were inspected in the foreground. The subsequent `migration-final` run loaded
  the rebuilt runtime, logged **French, 3,298 translated texts**, and logged **no untranslated UI text**.
  It completed its screenshot, reported zero Lua errors and quit normally with exit 0.

Evidence is retained under `out/qol-translations-20261030` in the main checkout; the original working
records are in `out/worktrees/translation-review/out/translation-audit`. PoC `config.json` and
`config.cfg` were restored to their saved hashes. Shared video registry values matched the snapshot,
so no registry write was needed. The field install and its running game were left alone. No Remix
`user.conf` was edited.

## Test constraints and remaining project issues

Normal RTX starts crashed during native setup with both the published package and the new package,
before the UI test ran. One startup logged 75.5/85.2 GiB of system commit in use. The successful UI
checks used `gm_flatgrass` and process-only overrides for low graphics, importance-sampled indirect
lighting and disabled ray tracing. They validate interface behavior and fonts, not default-setting
rendering stability under concurrent game load. A later RTX-on attempt with about 25 GiB of system
commit headroom still failed before the UI script. Its minidump identifies a null read in the unchanged
Steam `studiorender.dll` at offset `0x5d353` (the PoC and field binary hashes match). The cause is
unresolved; only exception/module metadata was inspected. The dump is kept locally in the evidence
folder and was not uploaded.

The nested worktree's 264-character staging path was rejected as a reparse point. A shorter, checked
staging root under the main checkout's `out/localization-build` completed packaging without relaxing
path rules. This existing path-length limitation remains. Runtime crash-report prompts can block
startup; the user declined the upload prompt. The flag that grants automatic upload consent was never
used. Use Python 3.12 with Pillow for screenshots and the test-console transport for protected commands.

No public release, tag, visibility change, field installation or Workshop item deletion is part of
this batch. Original add-on checkouts and the runtime fork's original checkout were left unchanged;
runtime changes are isolated in `out/worktrees/runtime-translations` and exported as patches.
Delivery uses the project's normal main merge/push and hidden-item publish hooks after validation.
