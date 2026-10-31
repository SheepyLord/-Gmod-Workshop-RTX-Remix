# 0048: Reject transparent cutouts before committing ray hits

- Status: Accepted 2026-10-30
- Decided by: the user's request 3

## Context

The software fallback forced ordered rays opaque, evaluated alpha after committing the closest
hit, then restarted the ray beyond a rejected surface. On tightly stacked or coincident model
layers that offset could also pass the valid face behind the transparent layer. Ganyu's nose
patch contained the back hair's blue albedo: this was incorrect geometry selection before
lighting. Opacity micromaps concealed the problem after baking by skipping the transparent
candidate in hardware. Without them the artifact could persist.

## Decision

Evaluate pure alpha-tested opaque candidates within the original traversal and reject transparent
hits before commitment. Ray queries commit accepted candidates and retain coincident valid
surfaces; matching any-hit shaders provide the same behavior for trace-ray GBuffer, PSR and
indirect paths, including existing NRC/SHARC/WBOIT variants. Legacy alpha operations, cutout
thresholds, replacement opacity and explicit alpha overrides remain authoritative. Raytraced
render-target routing is excluded from this rejection, and the first-hit debug view retains its
intended raw behavior. Other blending, transmission and portal resolution use their existing paths.

Cached acceleration geometry must also refresh material-dependent flags. Shared dynamic BLAS
geometry is opaque only when every linked instance is opaque, and preserves any required
no-duplicate-any-hit flag. Incompatible build flags force a rebuild even without vertex changes.

## Consequences

The fix applies automatically without material-name rules, geometry hiding, lighting bias,
larger ray budgets or changes to user.conf. The targeted facial shadow workarounds investigated
during diagnosis are not shipped. Micromaps retain their optimization role rather than being
required for correct layered cutouts. Validation uses all three supplied cached model packages
in separate cold processes with micromaps disabled, then exercises normal micromaps and ray modes.
