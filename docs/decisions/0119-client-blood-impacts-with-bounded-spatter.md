# ADR 0119: Client blood impacts with bounded spatter

Status: accepted (R20-C, the user's item 48). Date: 2026-11-06.

Register a client `BloodImpact` override, using the engine's existing dispatch to observers. Do not
send damage messages or modify bullets. Disabled, dispatch the same effect data with
`util.Effect("BloodImpact", data, false)` to bypass Lua and run the engine effect. Mechanical blood,
unknown colours and missing resources also keep the engine effect. Never hide shared particle
materials or replace `blood_impact.pcf`.

The visual model is a wide, slower cone of back spatter opposite the incoming shot, a narrower,
faster forward spray, a small short-lived mist and several droplet sizes under gravity and drag.
Forward spray is a visual approximation: the dispatch contains no wound penetration information.
Scale is the available damage proxy; it cannot reliably identify a weapon or measure actual damage.
Viewer distance reduces detail without changing ballistic direction. Droplet collisions stamp small
owned patterns using ordinary `ParticleEmitter` and `util.DecalEx`, so R20-D can handle Remix's
general particle/decal support. Blood colours 0, 1, 2, 4, 5 and 6 and all twelve colour schemes are
supported; mechanical sparks remain mechanical.

Use hard rolling-second and simultaneous particle budgets, short particle lifetimes, and both a
rolling-second stain limit and a map-total stain limit. Engine decals cannot be retired individually
without clearing other add-ons' decals, so the map-total is deliberately conservative. The explicit
clear-decals control resets that budget; map cleanup resets it too. Amount changes quality within
the same hard bounds. Resource/budget failures suppress extra work, without creating more stock
particles to evade the budget. Settings and diagnostics document the precise limits.

Design references (behaviour studied, no images or source code copied):

- [Valve's BloodImpact callback](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/fx_blood.cpp)
  selects `blood_impact_red_01`, green, yellow and episodic variants; the Lua override runs before
  that callback.
- [Facepunch util.Effect](https://wiki.facepunch.com/gmod/util.Effect) documents the `allowOverride`
  argument; [blood colours](https://wiki.facepunch.com/gmod/Enums/BLOOD_COLOR) identifies mechanical
  sparks separately.
- [High-speed spatter measurements](https://nij.ojp.gov/library/publications/high-speed-video-analysis-forward-and-backward-spattered-blood-droplets)
  support a narrower, faster forward cone and a wider back cone. These are visual design cues, not
  a forensic simulation.
- [Forward-spatter modelling](https://nij.ojp.gov/library/publications/theoretical-and-experimental-investigation-forward-spatter-blood-gunshot)
  accounts for gravity, drag and droplet-size distributions. The effect uses a bounded approximation.

Implementation evidence from the R20-C PoC: ordinary server ragdolls dispatch `Impact`, with bullet
damage flags, source/impact positions, entity and flesh surface property, and no blood amount. The
implementation observes Impact/Impact_GMOD/RagdollImpact too, always preserving their native or
previous Lua effect. Known ragdolls add the same bounded fluid; client-only ragdolls use a bounded
ray check, source colour when available and surface-type inference otherwise. No new server hook
or message is needed. Up to 160 checks per second and 64 recent cross-name deduplication entries
bound this observation. Flesh world collision traces use HitWorld even if their entity is invalid.
