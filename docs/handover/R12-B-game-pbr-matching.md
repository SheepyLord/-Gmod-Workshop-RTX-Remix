# R12-B: imported game PBR by texture features, and manual overrides by texture (brief)

Read [AGENTS.md](../../AGENTS.md), [R12-plan.md](R12-plan.md) (items 37 and 39, the rules for every task),
[R11-A-report.md](R11-A-report.md), [R11-B-report.md](R11-B-report.md), ADRs
[0091](../decisions/0091-automatic-pbr-fallbacks.md), [0092](../decisions/0092-generated-fallback-mods-rank-last.md)
and [0093](../decisions/0093-cached-imported-game-materials.md). You built R11-A and R11-B.

**Where you work.** This repository: branch `r12-pbr` in `out/worktrees/r12-pbr` (from `main`). The RTX
fixes (GPL): a new worktree `out/worktrees/r12-fixes` on a new branch `codex/r12-pbr` from
`codex/r11-autopbr` (`633fd5e`, the shipped DLL's source); reuse your R11-B build setup
(`out/worktrees/r11-cache/out/r11-b`) as the template. **Owns:** that fixes branch (ToPBR native and Lua,
including a new interface panel), `packages/fixes` (rebuilt DLL and changed files, imported one by one;
refresh the GPL source copy), tests, ADR 0095, the R12-B report, additive shared-doc lines. **Does not
touch:** `runtime/**`, `loader/**`, `companion/**`, `packages/model-hotloader/**`, other parts.

## 37: pair maps by what the textures show, helped by names

R11-A pairs only `<stem>_D` bases with same-stem siblings. Make `Discover` also find the right packed-map
family for a renamed base, the way a person would: by the textures' features (UV layout: which areas are
covered, island outlines and edges, aspect and size), with names as support (a matching stem, shared
tokens, or a small built-in vocabulary such as 衣服/cloth/body, 头发/hair, 丝袜/socks/stockings, 皮肤/skin,
头饰/hat/head, 熔岩/lava/reactor, 眼睛/eye/pupil, 脸/face). The example is
`E:\G\Upload\Alf\1_PMX\白银之城—阿芙2.0_by_神帝宇_fe972123c0e320e139d391cf37bad8d5\白银之城—阿芙2.0` (13
renamed bases, maps in `法贴\`).

- Fail closed: pair only with a clear score and a clear margin over the runner-up, one family per base,
  never across mismatched layouts; log every decision (base, family, score, margin, reason). A wrong
  normal map is worse than none. Faces and eyes keep R11-A's protection.
- Measure it: a tool that runs the production `Discover` over model folders and prints its pairings.
  Over the `E:\G\Upload` game folders (Wuthering Waves, Endfield, Silver Palace), use the name pairings as
  ground truth, hide the names, and report how often the feature matcher agrees, disagrees or abstains;
  then show what it pairs for 阿芙2.0 (with debug images of base and chosen map side by side).
- Bounded work as before (file counts, sizes, decode cost); results feed R11-B's registry unchanged.

## 39: manual overrides by texture

Let the player override the automatic imported PBR of a character's material: pick the maps (from the
candidate families found in the character's source folder, or individual files from that folder), choose
none (no game maps for it), or go back to automatic. Store the override by the live texture identity
(`mmd/t/<16 hex>`), so it applies to every material and character that shows the same texture; it outranks
the automatic result and the cached record, survives a missing source like R11-B's records (record what
an override needs to be restored), and authored replacement mods still outrank it (guard and patch 0020).
Put the interface where a player finds it: the RTX menu's "Imported game PBR" area and/or a panel for the
character being looked at, listing its materials with thumbnails, their current state (automatic family,
cached, override, none) and the choices. Translatable strings follow the add-on's existing i18n.

## Also: one R11-B fix

`QueueGameMaterial` (fixes `to_pbr.cpp`) calls `FindMaterial` before checking that the material was drawn,
for every material of every asset the Lua loop visits, which may load textures of characters nobody
spawned (R12-C measures VRAM). Check the frame hashes first and resolve the identity only for drawn
materials; R12-C will compare before/after.

## Evidence

Native regressions (feature matcher, abstention, override precedence/persistence/restore, the queue order),
the Lua harness, `tools\test.ps1 -Config Release`, and a PoC check: 阿芙2.0 imported from a copy, with maps
on/off screenshots; one override applied to a texture shared by two materials or characters, then removed.
Report: `docs/handover/R12-B-report.md` (with the DLL's size and SHA-256).
