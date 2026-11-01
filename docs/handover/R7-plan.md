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

What the PoC showed (`out/qa-poc/r7/` in the main checkout; the user then added: "it is not sure whether
alphatest is required if we are in Remix; could we use translucent or a better Remix-managed alpha, since
everything in this project runs in Remix; find the best way to implement alpha"):

- GMod RTX draws models with Source's fixed-function shaders (`VertexLitGeneric_DX7`, `UnlitGeneric_DX6`).
  Plates with a 16-band alpha ramp (`04-ramp`, `alpha_probe.lua`): lit alpha-tested materials cut at about
  0.7 whatever `$alphatestreference` says (Source's DX7 path sends a fixed `D3DRS_ALPHAREF`); unlit ones near
  0.5; blended materials are opaque only above `rtx.stochasticAlphaBlendOpacityThreshold` (0.79 in the
  package's classic defaults) and a stochastic dither below it.
- Under Remix the hotloader draws Columbina's mask blended (its soft-alpha path). The runtime skips a blended
  opacity between its transparency threshold and the stochastic threshold in primary rays (left to the
  stochastic composite) while visibility rays still attenuate by `1 - opacity`: no mask, a lattice shadow
  (`03-columbina`). With a temporary root `rtx.conf` threshold of 0.5 the mask renders as white bars with
  see-through holes (`05-columbina-thr05`).
- Lowering the threshold for everything would also make other blended surfaces between 0.5 and 0.79 opaque
  (map glass, props) and depart from the classic settings. The best fix gives Model Hotloader materials MMD's
  own rule in Remix: a runtime texture category whose alpha test cuts at 0.5 and whose blended opacity at or
  above 0.5 is solid in every ray type, filled by the companion with the hotloader's texture hashes at
  runtime. Task R7-A ([brief](R7-A-mmd-alpha.md)).

## Tasks

| Task | Brief | Scope | Branch |
|---|---|---|---|
| R7-A | [R7-A-mmd-alpha.md](R7-A-mmd-alpha.md) (investigation above, by Claude) | Point 1: MMD alpha under Remix, a runtime texture category and the companion filling it | Codex, `r7-alpha` |
| R7-B | [R7-B-crash-diagnostics.md](R7-B-crash-diagnostics.md) | Points 2 and 4: an exit report after a crash, the memory warning rule, the add-on list | Codex, `r7-crash-diag` |
| R7-C | [R7-C-glass-interaction.md](R7-C-glass-interaction.md) | Point 3: broken glass pushed and broken by players, NPCs, props, ragdolls, bullets, blasts and falls; one way | Codex, `r7-glass-interact` |

R7-A, R7-B and R7-C touch disjoint paths. Shared documents (CHANGELOG, ROADMAP, RESEARCH, TESTING,
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
