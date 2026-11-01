# 0067: Scene-adaptive opaque emission

- Status: Accepted 2026-10-31 (C-16; defaults await the project manager's PoC tuning)
- Decided by: the user's eye-white brightness request and Claude's [C-16 plan](../handover/C16-plan.md); runtime implementation by Codex

## Context

A fixed emissive intensity becomes conspicuous under dark-scene auto exposure and disappears
beside lit skin in bright scenes. MMD eye whites need a scene-referred light floor that follows
the same geometric-mean Yf used to compute exposure. Existing materials and older runtimes must
keep their fixed-intensity fallback. See [the implementation facts](../RESEARCH.md#c-16-scene-adaptive-emission).

## Decision

Add the optional opaque USD/MDL input `emissive_adaptive_intensity`, range 0..65504, default 0.
With emission enabled, a positive input, and `rtx.adaptiveEmission.enable = true`, evaluate:

```text
emissiveBlendOverrideInfluence * emissiveColor * emissive_adaptive_intensity
  * rtx.adaptiveEmission.scale * clamp(L_adapt, minLuminance, maxLuminance)
```

Otherwise retain the existing fixed `emissive_intensity` path, including its global intensity
setting. The adaptive path uses its own scale. Preserve the existing Source-eye override's color,
iris mask and blend behavior; replace its intensity through the same helper. Already evaluated
G-buffer, polymorphic and decal interactions retain their stored radiance, without scaling twice.

The exposure resolve writes its actual geometric-mean `adaptedYf` and smoothed exposure into one
eight-byte GPU buffer, including when exposure is capped. A three-slot host-coherent readback ring
delivers completed samples through the shared `RaytraceArgs` constants. Samples become eligible
after two frames. Check resource completion before mapping or reusing a slot; never wait for the
GPU. If it is late, keep the newest completed sample and report its age. No material pass needs a
new descriptor, and the DLSS exposure texture keeps its original format and dimensions.

The material record remains 64 bytes. Its subsurface index needs 21 bits, leaving its high byte
free; the DLSS control mask's alpha byte is always 255. Store the half-float input across those two
bytes, XORing the second byte with 255 so input zero preserves the old record byte-for-byte.
Shader accessors mask the subsurface index and restore DLSS alpha to 255. Visibility-only decoding
clears the optional intensity along with fixed emission. CPU material hashes include the input.

| Option | Default | Meaning |
|---|---:|---|
| `rtx.adaptiveEmission.enable` | `true` | Honor positive material inputs |
| `rtx.adaptiveEmission.scale` | `1.0` | Nonnegative multiplier for adaptive emission |
| `rtx.adaptiveEmission.minLuminance` | `0.0` | Allow emission to fade in dark scenes |
| `rtx.adaptiveEmission.maxLuminance` | `64.0` | Bound exceptional scene luminance |
| `rtx.adaptiveEmission.fallbackLuminance` | `0.18` | Neutral mid-gray when auto exposure is off or no completed sample exists |

Clamp fallback values too. Treat a negative minimum as zero and an inverted maximum as the
minimum. Nonfinite option values use their defaults; negative scale becomes zero. Turning auto
exposure off discards pending sample validity, so re-enabling starts with fallback until a fresh
sample completes. Authored options are never overwritten with per-frame state.

Log `[RTX Adaptive Emission]` on the first rendered frame, camera cuts and five-minute intervals:
frame, source, sample frame/age, raw adapted Yf, its paired exposure, effective clamped luminance,
scale and feature enablement. A fallback record labels its source and uses nominal exposure 1.

The runtime part contains no `AperturePBR_Opacity.mdl`. The combined package's copy is in the fixes
part's breakable-glass assets; declare the input there with the same default and hard range. MDL
previews continue using fixed intensity because their renderer does not expose Remix adaptation.

## Consequences

At settled exposure below its cap, displayed emission is approximately constant apart from the
existing cone-noise floor. At the cap it fades with scene luminance. A positive minimum, the upper
clamp, readback delay and the exposure integrator can affect transitions; this feature does not
promise constant brightness immediately after a cut. The added material work is a small scalar
decode/select/multiply, without a new substantial shader path or variant axis.

No authored input means unchanged emission. Older runtimes ignore the new USD input and retain
the fixed fallback. The new packed records are internal to this runtime, rebuilt from CPU materials
at startup. No user configuration, loader trust policy or game file changes are needed.

## Alternatives considered

- Binding adapted-luminance textures into all opaque-evaluation passes adds descriptors and
  pipeline plumbing to ray query, tracing, subsurface and related variants. Shared constants are
  simpler here; two frames are small beside the existing 0.15/0.75-second exposure time constants.
- Deriving luminance by dividing the exposure target by exposure loses the actual scene statistic
  at the exposure cap and follows a different temporally smoothed quantity.
- Growing the polymorphic record wastes space while two constant/unused bytes are available.
- A local screen-space skin reference or ignoring socket occlusion changes visibility/denoising
  behavior beyond this task. The [C-16 plan](../handover/C16-plan.md) leaves those as follow-ups.
