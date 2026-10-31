# 0059: The front-cull outline rule is opt-in; outline names stay on

- Status: Accepted 2026-10-31; amends [0047](0047-ignore-incompatible-model-outlines.md)
- Decided by: the R4 review lead (companion review, finding 4), within the user's request 4, which
  permits removing or ignoring outlines (ADR 0047)

## Context

ADR 0047 drove both outline rules from one setting, `nativeloader_ignore_outlines` (default 1):

- the runtime's `rtx.gmod.ignoreOutlineMeshes` hides opaque model draws that cull their front faces
  (D3D `CULL_CW`), the usual way an inverted-hull outline shell is drawn;
- the companion's `rtx.gmod.ignoredOutlineTextures` hides the textures of outline materials, found by
  name.

GMod culls front faces for real geometry too: a flipped view model (`SWEP.ViewModelFlip`) and its
hands (`gamemodes/base/gamemode/cl_init.lua:611`), mirrored models, Seamless Portals faces. Runtime
patch 0014 exempts view models, mirrored transforms and replacement meshes with their own culling,
but the rule still decides from the cull mode alone, and every other front-culled opaque draw of a
model disappears. The same review found the name rule reaching map textures (stock `white_outline`,
`black_outline`) through Remix's cached-material registry, outside ADR 0047's scope of outline
materials of loaded models.

## Decision

Two archived client settings:

- `nativeloader_ignore_outlines` (default 1; the Model outlines checkbox) drives only the name list,
  `rtx.gmod.ignoredOutlineTextures`. It covers materials bound to model entities: a `.mdl`'s
  materials, its sub-materials and the local body proxy's private materials. The world, brush
  entities and the cached-material registry are not used. Images shared with an ordinary material of
  a loaded model stay protected, as before.
- `nativeloader_ignore_outline_shells` (default 0; console only, no new interface text) drives
  `rtx.gmod.ignoreOutlineMeshes`. The companion sends `False` while it is 0, because the runtime's own
  default for that NoSave option is `True`.

## Consequences

Front-culled real geometry renders by default. An inverted shell whose material has no outline name
(no `outline` in it, not the MMD family's hei/touming) is no longer hidden unless the player turns
the shell rule on (`nativeloader_ignore_outline_shells 1`); Ganyu's hei skin is still covered by the
name rule. The runtime option, its NoSave flag and its default are unchanged; only the value the
companion sends changes. The LuaJIT harness checks both defaults, that the rules toggle
independently, and that map textures named `*_outline` stay visible
([test_model_layers.py](../../tools/tests/test_model_layers.py.md)).

## Alternatives considered

- One switch for both rules (ADR 0047): it hides real mirrored geometry by default.
- Removing the cull rule: some shells carry no recognizable name; the opt-in keeps that remedy.
- Changing the runtime's default to `False`: a runtime rebuild for what the companion already sets
  every session, and a different behaviour for the runtime used without the companion.
