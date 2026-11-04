# R15 plan: 目影 in imported models, alpha on hair, and the release candidate

The user's items (2026-11-04), verbatim:

> 43. Develop a more robust way to hide 目影 in IMPORTED MODELS automatically.
>
> 44. Further improve the handling of materials with alpha (related to Alphatest). For example,
> E:\G\Upload\laevatain_rc\Endfield-Laevatain明日方舟终末地-莱万汀 (I removed Alphatest to make it look
> correct) has wrong Alpha on hair. You are allowed to switch away from Alphatest if needed.
>
> Make the most recent loader release after this. This will be the release candidate.

Claude works in the main session on `r15` (worktree `out/worktrees/r15`, from `main` `786d9a9`). R14's
rule for this session still holds: Codex only for translation and text validation.

## What is there now

**目影.** Nothing hides a painted eye shadow:
- the eye-white rules only exclude it (`companion/nativeloader/lua/nativeloader/eye_white_names.lua`);
- outline suppression hides only outline shells by name (`nativeloader_model_layers.lua`).

The field library (read only, 2026-11-04) shows how varied these parts are:
- **Untextured black at alpha 0.2-0.5:** Endfield and Wuthering Waves rips' 目影 and 发影, Laevatain's
  `Moyin` (the pinyin of 目影) and `Hair+`, JEPT's `EyeShadow`, `面具影`.
- **A plain black or grey image at alpha 0.2-0.5:** Star Rail models' 目影 with `黑.jpg` or `灰.jpg`.
- **A region of the face or eye atlas:** `颜.png`, `脸.png`, `T_*_face_d.png`; and まぶた影, the
  eyelid shadow of LycoReco and Blue Archive models.
- **Untextured grey (0.75) at alpha 0.3:** ホタル's 目影.

Names alone miss `Moyin`; colour alone misses the atlas ones.

**Alpha.** Every imported part's public VMT alpha-tests at 0.5, with alpha-to-coverage
(`packages/model-hotloader/.../native_render.lua`):
- Parts with partly transparent texels also draw a blended "soft" copy (`mmdhl_soft_alpha`, default 1),
  which Remix blends in the opaque pass.
- In the runtime, hotloader textures are in the MMD alpha category ([ADR 0081](../decisions/0081-mmd-alpha-texture-category.md)):
  opacity at or above `rtx.mmdAlphaCutoff` (0.5) becomes 1, and lower opacity keeps the blend or
  stochastic behaviour.

Laevatain's hair texture (`tex/T_actor_laevat_hair_01_D.png`, 2048²) is 90 % opaque, 3.5 % clear and
6.5 % in between. The user made it look right by removing `$alphatest` from the hair's material.

## Tasks

| Task | What | Who |
|---|---|---|
| R15-E | Item 43: detect painted eye shadows (and the same overlays for hair) by name and by their properties, and hide them in RTX sessions only, at render level: no bodygroup, save, dupe or file changes. A setting to turn it off, a status command, LuaJIT tests over the field library's real cases, a PoC proof | Claude |
| R15-A | Item 44: find what makes Laevatain's hair wrong under path tracing, compare the options (opaque parts whose alpha is not coverage, a different cutoff, the soft pass, blending), choose one, implement it, and A/B it in the PoC against characters whose alpha is real (lace, tulle, lenses) | Claude |
| R15-R | After both are merged and published: the loader release candidate (a `v*` tag; CI builds and releases the bundle) | Claude |

## Coordination

- The PoC lock (`out\r10\poc.lock`) serializes PoC use.
- Laevatain is copied for the experiments from R13's read-only field cache, and removed afterwards.
- Field checks start only when no other session's lab is running ([R14's lesson](R14-report.md#publication-and-the-field-check)).
