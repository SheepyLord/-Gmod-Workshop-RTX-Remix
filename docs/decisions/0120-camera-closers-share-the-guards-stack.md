# 0120: Every camera closer consumes the guard's matching scope

- Status: Accepted 2026-11-06
- Decided by: Codex under the user's autonomous R20-D brief (items 44 and 51)
- Amends: [0056](0056-guard-and-startup-fallbacks.md)'s tracked-scope bookkeeping

## Context

The stock duplicator icon opens and closes 32 cameras per entity per outline pass with
`cam.Start(view)` / `cam.End()`. The guard observed only `End2D` and `End3D`. Its 32-scope
limit then suppressed later starts while the unwrapped native `End` still ran and underflowed.
Facepunch documents [End](https://wiki.facepunch.com/gmod/cam.End) as an alias of End3D,
and [Start](https://wiki.facepunch.com/gmod/cam.Start) accepts End2D or End3D as a closer.

## Decision

Wrap every ordinary camera closer (`End`, `End2D`, `End3D`) once, sharing one tracked camera
family with `Start`, `Start2D` and `Start3D`. Capture the original closer for cleanup, rather
than a previously installed wrapper. All other observed push/pop pairs use the same single
closer installation rule. Render targets, clipping and model matrices have no additional
Lua closer aliases in the stock API.

`Start3D2D` has a separate family on that same stack: it also pushes a model matrix, so its
only complete closer is `End3D2D`. Reject cross-family closers without changing either native
stack. Virtual pushes retain their family and balance through the same aliases as real pushes.
The existing ancestor ownership checks, off switch and error cleanup still apply.

## Consequences

Sequential icon cameras no longer accumulate phantom entries. A Lua add-on using any accepted
ordinary camera closer gets balanced tracking. Incorrect composite-camera closers are contained
before they consume an unrelated matrix. CPU regression coverage exercises 257 sequential pairs,
every ordinary start/closer combination, nesting, virtual scopes and cleanup after a real error.
Native alias identity and the actual dupe icon are also checked in the locked PoC acceptance run.
