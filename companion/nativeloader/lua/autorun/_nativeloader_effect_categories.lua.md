# _nativeloader_effect_categories.lua

R20-D's automatic Source particle/decal observer ([ADR 0121](../../../../docs/decisions/0121-source-effect-categories-for-the-session.md)).
Runs at client autorun only when NativeLoaderRenderGuard proves the local RTX session. It is
idempotent in that Lua realm. Server and RTX-off starts return without changing APIs.

Inputs: CLuaEmitter:Add, CLuaParticle:SetMaterial, util.DecalEx, render.SetMaterial and
sprite/beam calls; the native RemixMaterial draw cache; material shader/flags and base texture.
The Think hook processes at most twelve discoveries and twelve hash lookups per frame. Material
lookups require a previously drawn hash, so undrawn character libraries are never loaded.

Outputs: only the NoSave `rtx.gmod.particleTexturesForSession`, `decalTexturesForSession` and
`legacyEffectTexturesForSession` options. The runtime joins the first two with saved categories;
the last preserves effect color/alpha on arbitrary blended meshes without reorienting them.
Hash sets are sorted and deduplicated, republished only on change, at most four times per second.
Lookup retries, two-second refresh, 4,096-entry cap, 120-second expiry and write-failure backoff
bound the work. Shared white/error/framebuffer textures are excluded.

The observer keeps native arguments, objects, errors and return values and changes no material.
Named util.Decal variants are discovered through their drawn metadata: it never calls the random
util.DecalMaterial resolver to guess which variant the engine selected.
It reads no VMT files and writes no files, user.conf, rtx.conf, persistent options, network or
Steam settings. NativeLoaderEffectCategories.Status() prints diagnostics; there is no process
exit code or new player setting. The guard's existing shader/resource limits apply unchanged.

Verification: [effect_categories_harness.lua](../../../tests/effect_categories_harness.lua.md),
through [test_effect_categories.py](../../../tests/test_effect_categories.py.md). Covers all
three classifications, normal world exclusion, shared textures, malformed/late/changed hashes,
API forwarding, bounded work, retry backoff, absent native API and inert server/RTX-off starts.
