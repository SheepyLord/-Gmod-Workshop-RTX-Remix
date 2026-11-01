# 0068: Publish scene-adaptive eye emission without regenerating maps

- Status: Accepted 2026-10-31 for C16-B; the provisional numeric default is superseded by
  [0069](0069-tuned-adaptive-eye-emission.md) (2026-10-31, tuned in game)
- Decided by: the user's C16-B brief and approved C16 plan; publish-option implementation by Codex

## Context

The [C16 plan](../handover/C16-plan.md) adds an optional opaque-material
`float inputs:emissive_adaptive_intensity`. Fixed eye emission conflicts with auto exposure: dark
scenes lift emission relative to lit skin, while bright scenes lose the eye-white lift. Existing
packs must keep their textures and fixed fallback so older runtimes retain their current behaviour.
rpai already normalises class emission into one shared map and re-levels it at publish. The brief
permits either a class field or a publish option. [Research](../RESEARCH.md#c16-b-publishing-scene-adaptive-eye-emission-2026-10-31)
records the code and pack evidence.

## Decision

Add the publish option and top-level settings field `emissive_adaptive_intensity`, a non-negative,
finite ratio `R` to the fallback USD intensity per unit adapted scene luminance. For maps whose
`generated.json` coverage includes `sclera`, `eye` or `highlight`, write `A = F * R` beside the
unchanged fixed intensity `F`. `R = 0` writes an explicit opt-out. Other emitters, maps without
emission and cached entries without class coverage get no adaptive input. Final USD values must
fit the runtime's 0..65504 range. Class weights, texture composition and generation signatures
remain unchanged.

The provisional default is `R = 1 / 0.18`. At reference exposure 1, the package's target adapted
luminance 0.18 gives `L_mid = 0.18`, ignoring the small exposure noise term. If the normalised
map is `M = C * w / S` and fallback is `F = S * I`, then `M * A * L_mid = C * w * I`, matching
today's sclera weight 0.025 times the publish multiplier. A fallback 0.6 yields adaptive 3.33333333;
fallback 0.04 yields 0.222222222. Claude will tune this reference in the game; no in-game acceptance
is claimed by C16-B.

For already published packs, `set_adaptive_emission.py` edits staged `.usda` files by byte range.
It supports a literal `--value` or a per-fallback `--multiplier`, selects emissive-map shaders in
rpai's material blocks, preflights all layers, and offers a dry run. It preserves every other byte
and touches the existing `mod.usda` timestamp only after changes. Without class masks it treats
every emissive-map shader as eligible, so the operator reviews the material list on a staged copy.
`package_characters.py` copies and verifies complete layers byte for byte.

## Consequences

Both emission controls can be tuned at publish with cached maps. Each material keeps its own
normalisation and fallback, including multi-character packs with different strongest class weights.
Older runtimes ignore the new input; supporting runtimes select fixed emission when the input is
zero or the runtime feature is off. Runtime scale, clamps and auto-exposure-off luminance can
change the relationship and need integration measurements.

The option is a ratio, whereas the identically named USD input is a literal intensity. CLI help,
skill documentation and migration examples state this distinction. The migration tool edits
rpai's plain text prim format; it is not a general USD composer or binary-USD editor.

## Alternatives considered

A new per-class texture field would require regeneration and would not independently control
adaptation of classes sharing a material's one input. A literal publish-wide USD value would lose
the shared map's normalisation, particularly March 7th's 0.04 versus the other packs' 0.6. Rewriting
complete existing layers would lose comments, formatting and user edits outside the target value.
