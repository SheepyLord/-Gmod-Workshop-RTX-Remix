# set_adaptive_emission.py

Add or update `float inputs:emissive_adaptive_intensity` in an existing published rpai mod, without
regenerating or reading textures. Uses only Python's standard library and the bundled rpai helpers.

## Usage

```powershell
# Work on a staged copy. Preview first; omit --dry-run to apply.
python skills/mmd-remix-pbr/scripts/set_adaptive_emission.py --mod out/pbr_robin --value 15 --dry-run

# rpai's tuned ratio on each material's own fallback, so different atlas normalisations stay.
python skills/mmd-remix-pbr/scripts/set_adaptive_emission.py --mod out/pbr_robin --multiplier 25

# Explicitly opt out on supporting runtimes; older runtimes already use the unchanged fallback.
python skills/mmd-remix-pbr/scripts/set_adaptive_emission.py --mod out/pbr_robin --value 0
```

Pass exactly one mode:

- `--value V`: the literal USD input for every selected shader; finite 0..65504.
- `--multiplier R`: set each adaptive input to its existing `float inputs:emissive_intensity * R`.
  Requires one explicit finite, non-negative fallback per selected shader. `R` must be finite and
  non-negative, and every result must fit 0..65504. This matches rpai's publish option. A fallback
  of 0.6 becomes 15 at rpai's default ratio 25 ([ADR 0069](../../../docs/decisions/0069-tuned-adaptive-eye-emission.md)); 0.04 becomes 1.

## Inputs and outputs

`--mod` is an existing mod folder. Recursively reads its `.usda` files only, selecting `Shader`
prims inside `mat_<16-hex-digit-hash>` materials with a nonempty `asset inputs:emissive_mask_texture`.
Reports relative layer paths and changed material names, followed by counts. Updates an existing
scalar's number in place, or inserts a line after the unchanged fixed intensity (before the shader
close if the fallback is implicit and `--value` is used). Running the same command twice is a no-op.

The editor supports rpai's plain `over` blocks and equivalent `def Material`/`def Shader` blocks.
It masks comments, strings and assets when matching scopes, preserving UTF-8 BOM, newlines, spacing,
comments and every byte outside the inserted line or replaced number. It does not compose USD,
follow sublayers, resolve inheritance or edit binary `.usd`/`.usdc` files or prims with header
metadata. Duplicate/non-float adaptive inputs or unbalanced braces fail during preflight. Materials
without an emissive map are untouched, including any adaptive input they already contain.

Unlike rpai publish, this migration script has no class masks: **every emissive-map shader in the
selected pack** is eligible. Use it for reviewed character packs; inspect the dry-run material list.
Do not use one literal value for differently normalised sheets unless that change is intended.

## Side effects

Only changed layers under `--mod` are atomically replaced, with temporary files beside them. All
layers are validated before writing any; a later I/O failure can still leave earlier edits applied.
If anything changes and `mod.usda` exists, its timestamp is touched so Remix can reload; its bytes
stay identical. A repeated no-op does not touch timestamps. `--dry-run` writes no mod data or
temporary files and touches nothing. Paths resolving outside the selected mod are refused.
No textures, game, Steam files, `user.conf`, network or rpai work cache are used or modified.

## Exit codes

0 on success, including no changes; 1 for an I/O or unsupported/malformed layer error (printed on
stderr); 2 for invalid CLI arguments. See [standards](../references/standards.md) for the default's
derivation and in-game tuning and [runtime notes](../references/runtime-notes.md) for compatibility.
