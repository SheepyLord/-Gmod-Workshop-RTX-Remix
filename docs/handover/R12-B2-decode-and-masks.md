# R12-B2: straight-alpha decoding and name-confirmed mask evidence

Follow-up to [R12-B](R12-B-game-pbr-matching.md) (item 37), from Claude's review of `fd496bf` / fixes
`43d40a4` on 2026-11-03. Same branches and worktrees: `out/worktrees/r12-pbr` (`r12-pbr`) and
`out/worktrees/r12-fixes` (`codex/r12-pbr`). Same rules: [R12-plan.md](R12-plan.md). ADR: amend
[0095](../decisions/0095-texture-features-and-imported-pbr-overrides.md) with a follow-up section (it is
not merged to `main` yet).

## What the review found

1. **WIC's Fant scaler premultiplies alpha when it shrinks an image.** `GamePBR::Decode` (`game_pbr.h`)
   scales the 32bppBGRA frame with `IWICBitmapScaler` (Fant), then converts to 32bppRGBA. An exact replica
   (the main checkout's `out/r12/wic_alpha_test.cpp`, built with the repo's MSVC) on the 阿芙2.0 copy's
   `法贴\T_AlfDefault_Body01_B_MRA.png` (alpha 0 on 97.7 % of its pixels, RGB mean 167.6 there):

   | Decode | alpha 0 | RGB mean under alpha 0 | RGB mean, all pixels |
   |---|---:|---:|---:|
   | 2048 (source size, scaler passes through) | 97.7 % | 167.6 | 166.1 |
   | 128 (Fant) | 97.1 % | **0.0** | **3.1** |

   - Matching: production gives 衣饰.png 0.27 against Body01_B (from its normal). A Python replica of
     `Describe`/`Similarity` (the main checkout's `out/r12/match_experiment.py`) gives **0.78** against the MRA's real colour,
     with margin 0.67: the match is lost only to the decode.
   - Conversion (R11-A onward): every map `Convert` decodes below its source size (a packed map larger
     than its normal, any map over the 2048 limit) loses its colour wherever alpha is 0.
2. **Hair needs the family's mask maps, and names must gate them.** 头发.png does not correlate with
   `Hair01_A_N` (-0.03) but does with `Hair01_A_AnisoMaskPS` (0.52) and `Hair01_A_PromMask` (0.29). If
   every `<family>_*` map may vote, the gun's 熔岩.png pairs with `Pupil01_A` through
   `Pupil01_A_Caustic` (0.31, margin 0.14), which is wrong.
3. **One ambiguous family aborts a whole folder.** `Families()` calls `Named()`, whose `Find` throws
   "ambiguous companion texture"; every base of that folder then goes unmatched (12 corpus rows).

## What to do

1. Decode without premultiplying: decode at source size to straight 32bppRGBA and shrink in code with an
   area average on straight RGBA (or scale colour and alpha through separate alpha-free paths). Keep every
   existing bound (`ValidImage`, compressed bytes, the pixel budget). Add a native regression: a generated
   PNG with alpha 0 over coloured pixels, decoded smaller, keeps its colour (it must fail on `43d40a4`).
   If any conversion output can change, bump the content key and marker and `GeneratorVersion`
   (`r12-game-v7`, 7) so outputs made with the old decode are rebuilt.
2. Auxiliary evidence, gated by name: a family's other images sharing its stem (LBMask*, AnisoMask*,
   PromMask, Specular, DynAO, ExpMask, ...; its normal, packed and emission maps are already core) may
   supply spatial evidence **only** when the base's name and the family's name fall in the same vocabulary
   group (头发 with hair). Core evidence and the thresholds stay as they are. Auxiliary decodes use only
   the budget left after core maps and bases and never make a folder fail. Measure, do not assume, a
   one-pass 3x3 blur of the edge map (the replica says it helps hair and skin a little).
3. `Families()`: skip and log an ambiguous or unreadable family instead of failing the folder.

## Acceptance

- Corpus (the same 121 PMX and 259 canonical references; re-run the probe with production code): still
  **0 disagreements** with names hidden; agree/abstain deltas per layout. List every acceptance (names
  visible) that R12-B's `out/r12-b/corpus-final.tsv` lacks, and look at each pair (a contact sheet of the
  base beside its evidence map). If any is wrong, tighten until none is.
- 阿芙2.0 (copy: `out/r12-b/source/Alf2`): 衣饰 to Body01_B and 头发 to Hair01_A accepted, with the
  evidence logged; the gun's 熔岩 and 眉毛 still abstain. Report all 16 bases.
- Conversion: show (numbers or an image) that Body01_B's packed map keeps its real channels when decoded
  below source size.
- PoC: a short automatic run with the Alf2 copy, in which hair and 衣饰 get game maps (`automatic` or
  `cached`). Take a screenshot, quit normally with zero Lua errors, restore the PoC exactly and release
  the lock. R12-C may hold the lock: wait for it. End a running field game when you need the GPU and say
  which one (the user's standing instruction).
- Rebuild the fixes DLL and import it once (`tools\inputs.py import fixes --file`). Refresh the GPL source
  copy (`autopbr.patch`, `source-files.json`, `Source.md`). `tools\test.ps1 -Config Release` passes.
  Commit on `codex/r12-pbr` and `r12-pbr`, with this brief committed as is. Never push, merge or publish.
- Docs:
  - ADR 0095: a "Follow-up (R12-B2)" section.
  - RESEARCH: the WIC fact, with numbers.
  - TESTING.
  - CHANGELOG under `### R12`.
  - A "Follow-up: R12-B2" section in [R12-B-report.md](R12-B-report.md).
