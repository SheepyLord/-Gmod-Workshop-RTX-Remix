# blood_core.lua

Client controller for Blood Overhaul RTX's 26 patterns (eight original, eighteen generated). Keeps the existing archived
`bloodoverhaul_*` controls and twelve colour schemes, custom RGB, size, variety and droplet tint.
Pattern materials are lazy: only used shapes load and only these retint after a setting changes.
Red, yellow/antlion, green/zombie and worker colours have separate materials, so changing a stock
colour never retints another family. The realistic scheme retains distinct stock species colours.

Wraps `util.DecalEx` once via the early bootstrap, replacing only incoming `decals/blood1..8` and
`yblood1..6` (including subrect names). With enable off it forwards every argument exactly. No stock
PCF is replaced. The part supplies stock-name VMT/VTF resources by permission (ADR 0124). Uses world/model decal
materials and live material tint, which survives Remix's replacement albedo. Original shapes lead
the list, so variety off preserves the requested bloodN/ybloodN pattern. The existing
`bloodoverhaul_apply`, `_test`, `_reset` commands remain. Test explicitly paints two unbudgeted
sample splats at the crosshair; normal impacts have their own hard stain budget.

The existing droplet-recolour setting also redirects another Lua add-on's `CLuaEmitter:Add` calls
with these exact blood/yblood material names to the new owned droplet and current palette. Other
particle materials and disabled settings pass through. External add-ons keep their own budgets.
Recolouring uses the returned particle's standard SetMaterial method, so generic observers see the
actual replacement even when their Add wrapper surrounds the mixer.

Reads client settings and included shape/scheme tables; writes only in-memory material variables.
No networking, game files, native options or exit code. Errors are ordinary GMod Lua errors.

Also recolours the engine's blood/yblood subrect and flesh/alienflesh/antlion world/model materials
the original add-on recoloured. Stains and base DecalModulate VMTs keep their source textures/PBR.
Each changed material snapshots its base texture and effective tint first; master off restores them
and performs no further painting. Re-enabling snapshots the new baseline, including other add-ons'
changes made while disabled. InitPostEntity and a zero-delay callback cover native C++ decals before
a Lua mixer call. Skip foreign shaders/Subrect parents safely; never alter their shared variables.
Snapshots use the canonical material name, because distinct Lua userdata wrappers may refer to one
engine material (the original shapes' model VMTs are shared by engine subrects and the mixer).
Keep the original ITexture reference but rebind its saved name on restore, using the same filename
binding path as scheme painting. The four-state native PoC probe verifies their draws with master
off, in blue, and restored after blue; first-use lazy PBR loading needs settling before capture.
Palette painting deliberately rebinds the texture even when its filename matches. Live RTX probes
rejected a setter-skipping optimization: matching Lua names alone did not establish a drawable
binding. The original R20 binding recipe is retained; palette samples are freshly stamped for QA.
Off does not unmount packaged materials/PBR or clear existing decals. Impact off/amount zero only
controls extra impacts; master off disables schemes and the mixer too.
