# R7: the user's report of 2026-11-01 (plan)

The user's request (2026-11-01), after G1 was published; tasks may go to Codex:

1. **(High)** Transparent materials render black (likely their cast shadow) instead of their colour.
   Example: in the field session, the `npc_citizen` `[128 | -1]`, whose `眼罩` (blindfold) mesh is not
   rendered correctly. The user (mid-investigation): it is unrelated to Evernight or to the PBR packs;
   inspect the MMD model and the texture in the active session.
2. **(Moderate)** A crash report: when a crash (such as running out of memory) ends the game, show the
   error message and the reason for the exit to the user, if known.
3. **(Moderate)** Scattered glass reacts to follow-up damage (falling, shooting, explosions); players and
   Source physics objects (such as ragdolls) push or damage it, and glass never affects them in return,
   like the Model Hotloader's MMD physics.
4. **(Low)** Diagnostics: a memory warning at `64.0 GiB / 90.6 GiB` makes no sense; show the package
   `gmod-rtx-remix` in full and, for other add-ons, only how many are enabled.

"Leave frame cost while lots of glass falls for now": no task works on G1's falling-pieces cost, and
none may make it worse (field run 10: 25.31 ms mean, 113 ms p99 while 2,000 pieces fall).

## 1. Transparent materials (R7-A, Claude)

What the field session's data shows (read only; `garrysmod/data/mmd_hotloader` of the field install):

- The model is **Columbina** (Model Hotloader asset `27570558...6997`, approved as a citizen rig). Its
  material 15 `眼罩` uses `tex\眼罩.png` (sha256 `2c7b2c85...6432`, 1024x1024 RGBA): a lattice whose bars
  have alpha 166 (70 % of visible texels) and whose diamond panes have alpha 66 (29 %); visible colour
  white-pink (234, 221, 220); the fully transparent texels (55 %) are black. In the hotloader's own
  preview it is a white lattice with clear holes.
- The hotloader's material (`materials-v5.gma`, `yan_zhao_16.vmt`) is `VertexLitGeneric` with
  `$alphatest 1`, `$alphatestreference .5`, `$allowalphatocoverage 1`, `$translucent 0`, `$nocull 1`,
  `$vertexcolor 1`, phong and rim light, exactly like every other material of the model; this is the only
  texture with partial alpha. Uploaded as BGRA8888, its Remix hash is `0xFB1616F217669E2E`, in no texture
  category of the package's `classic_remix_defaults.conf` or the field's `rtx.conf`.
- So with an alpha test at 0.5 the bars (0.65) should draw and the panes (0.26) be cut. Under RTX the mask
  does not show and the face is darkened where it is: its shadow without the surface.

Next: reproduce on the PoC with the same VTF on a plain prop, varying one material state at a time
(`$allowalphatocoverage`, `$alphatest` reference, `$vertexcolor`, `$nocull`, `$translucent`), and with the
model itself; find where primary and shadow visibility disagree (runtime alpha test, vertex colour alpha,
alpha to coverage, opacity micromaps); fix it where the cause is (runtime patch, hotloader material
generation, or configuration), then a brief for Codex if the fix is large.

## Tasks

| Task | Brief | Scope | Branch |
|---|---|---|---|
| R7-A | this file | Transparent materials: investigation and fix | Claude, `r7-int` |
| R7-B | [R7-B-crash-diagnostics.md](R7-B-crash-diagnostics.md) | Points 2 and 4: an exit report after a crash, the memory warning rule, the add-on list | Codex, `r7-crash-diag` |
| R7-C | [R7-C-glass-interaction.md](R7-C-glass-interaction.md) | Point 3: broken glass pushed and broken by players, NPCs, props, ragdolls, bullets, blasts and falls; one way | Codex, `r7-glass-interact` |

R7-B and R7-C touch disjoint paths. Shared documents (CHANGELOG, ROADMAP, RESEARCH, TESTING,
COMPONENTS) get additive edits only. Claude reviews, integrates on `r7-int`, runs the game QA on the PoC
and publishes.

## Acceptance (PoC)

1. Columbina's mask (and a plain prop with the same texture and material) shows its white lattice with
   clear holes under RTX, and its shadow matches what is drawn.
2. A forced crash, a simulated out-of-memory exit and a device-loss exit each show one message naming the
   reason after the game closes; a normal quit shows nothing; automated sessions are not blocked.
3. A player walking through a pile pushes pieces, a dropped ragdoll and a thrown prop push and break
   them, bullets and blasts push and break them, a large piece falling from a window breaks on landing;
   nothing pushes back; the 50-pane scene is not slower than run 10.
4. The memory warning stays quiet at 64.0 / 90.6 GiB and warns when a map load would not fit; the
   diagnostics list `gmod-rtx-remix` in full and counts the other add-ons.
