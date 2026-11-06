# blood_core.lua

Client controller for the eighteen owned Blood Overhaul RTX patterns. Keeps the existing archived
`bloodoverhaul_*` controls and twelve colour schemes, custom RGB, size, variety and droplet tint.
Materials are lazy: only used patterns load and only these retint after a setting changes.
Red, yellow/antlion, green/zombie and worker colours have separate materials, so changing a stock
colour never retints another family. The realistic scheme retains distinct stock species colours.

Wraps `util.DecalEx` once via the early bootstrap, replacing only incoming `decals/blood1..8` and
`yblood1..6` (including subrect names). With enable off it forwards every argument exactly. No stock
VMT/PCF is replaced and no Crunchy-derived texture is referenced. Uses plain world/model decal
materials and live material tint, which survives Remix's replacement albedo. The existing
`bloodoverhaul_apply`, `_test`, `_reset` commands remain. Test explicitly paints two unbudgeted
sample splats at the crosshair; normal impacts have their own hard stain budget.

Reads client settings and included shape/scheme tables; writes only in-memory material variables.
No networking, game files, native options or exit code. Errors are ordinary GMod Lua errors.
