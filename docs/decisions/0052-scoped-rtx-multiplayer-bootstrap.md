# 0052: Verified RTX-owner scripts in multiplayer

- Status: Accepted
- Decided by: the user's multiplayer request, explicitly limited to the RTX payload and excluding other community add-ons

## Context

The shipped runtime requested `-insecure`, and normal client Lua loading can be blocked by a remote
server's `sv_allowcslua 0`. The user requested multiplayer rendering without that launch flag and
authorized loading the project's own RTX scripts in that situation: "this should be kept on the
addons in our RTX addon only and should not expand to other community addons."

The existing native allowlist and deployment journal provide an exact owner and committed file
hashes. The menu realm can load a native module before the remote client realm exists. Its lookup
uses the `gmsv_` prefix, established by native lookup inspection after a `gmcl_` prototype failed.
The existing renderer also needs seven in-memory fixes; omitting them caused a prototype crash.
See [RESEARCH.md](../RESEARCH.md#scoped-rtx-multiplayer-loading-loader-090).

## Decision

Loader 0.9.0 ships a menu-realm helper named `gmsv_nlrtxclient_win64.dll`. It only activates from
its exact deployed path, with enabled config, a committed journal without a pending transaction,
its own recorded SHA-256 and the package's actual runtime active. It polls for a ready client realm
and initializes that realm once; normal single-player loading remains with the engine.

The forced-source catalog accepts exactly the `gmod-rtx-remix` runtime owner. Local and dev sources
must match their respective configured native allowlists. Workshop loading is restricted to the
configured distribution item 3829070317 under `workshop/content/4000`. Only that owner's committed
add-on Lua is captured, and all captured bytes must match recorded size/SHA-256. Unsafe paths,
links, duplicate/case-colliding keys, NUL source and size overflows fail closed. Other packages,
even with identical virtual paths, cannot supply source. Generic `rtx_agent` and Hotloader debug
source evaluation are excluded. Native callbacks read exact catalog keys and expose no generic
filesystem-read or source-execution API.

An embedded initializer uses scoped include/require/file helpers for catalog-owned dependencies.
Unrelated calls fall back to the original engine APIs and their original permissions. Global
helpers and `sv_allowcslua` stay unchanged. Shared/client libraries initialize before client entity
definitions; only newly registered, explicitly tracked owner initialization hooks are replayed.
The temporary native API global is removed before owner scripts execute. Completion/error status
is local and does not change server state.

A shared adapter inside those owned environments drops net messages when the remote server has
not pooled their channel. Its Start/write/byte-count/send/abort state stays local to the scoped
adapter, with missing names recorded in completion status. Registered channels delegate to the
engine with original arguments, return values and errors; global net is unchanged. This lets
rendering initialize against a server without the bundled tools. Server-dependent tool features
still require matching server add-ons.

The initializer also sets `NATIVELOADER_VERIFIED_MULTIPLAYER` only inside each owned environment.
The GPL cl_rtx.lua uses it to skip its initial/final hardware-model cache flush when initialized
after the world is active. The normal early path retains both flushes and convar restoration
retries. This prevents invalidating hardware LOD data already used by queued static-prop rendering.

The shipment stops requesting `-insecure`. General patch sets keep the existing
`patch_sets.require_insecure: true` default. A separate default-enabled
`patch_sets.allow_rtx_render_patches` exception accepts only the exact seven existing recipes
owned by `gmod-rtx-remix`: two engine HDR fixes, three shader API fixes, one material-system buffer
guard and one data-cache vertex-format filename fix. SHA-256 fingerprints bind the complete
ordered groups' owner, module, patch names, find bytes, offsets and replacements. Changed, extra,
missing or reordered patches cannot inherit this exception. Setting the key to false opts out
without disabling the general gate. Other native allowlists, path rules and loader/runtime off
switches retain their existing meaning. This narrowly extends [ADR 0010](0010-rtx-session-extras.md)'s
insecure-patch rule for these renderer recipes; it does not broaden general patch permission.

RTXDebug permits local rendering queries and Remix rendering configuration in multiplayer. Unsafe
Lua evaluation, memory writes, detours and gameplay/replicated cheat mutations still require
single-player, `sv_cheats 1` and `-insecure` together. The multiplayer catalog does not expose those
development entry points.

## Consequences

The updated 0.9.0 loader bundle is required along with the payload: a Workshop update alone cannot
replace an installed `winmm.dll`. Packages containing the helper declare `requires_loader >=0.9.0`
so older loaders refuse them; standalone fixes without it retain their older >=0.2.0 minimum.
A module or script mismatch disables this forced-loading path;
it never falls back to unverified local source. New renderer recipes require deliberate review and
fingerprint updates. The public Garry's Mod Lua SDK headers remain byte-identical to the recorded
upstream revision with their BSD-3-Clause licence; no GPL implementation is copied into loader code.

No anti-cheat identity is spoofed and no universal VAC/server-policy compatibility is claimed.
The successful controlled dedicated-server session below is separate from the offline policy
checks; final full-suite and package/publication validation remains pending.

## Validation

Current targeted results: **16 catalog cases**, **7 config cases**, and **6 Lua tests covering
14 scenarios**, all passing. They exercise owner/source/hash boundaries, exact rendering recipe
classification and mutations, config opt-out and general defaults, real initializer execution,
engine fallbacks, scoped dependency/network loading, initialization order, hook ownership, private
markers, normal/late cache-flush behavior and realm guards. Two body cases also preserve source
bone snapshots, destination validity checks and non-accumulating offsets.

Prototype 7 joined a genuine 64-bit dedicated server with VAC secure mode active, no client
`-insecure`, `sv_allowcslua 0` and cheats off. The payload completed 44 autoruns without errors,
unrelated local Lua remained blocked, and reconnect plus a gm_construct/gm_flatgrass round trip
passed. RTXDebug rendering SetConfig/restore passed with config-file hashes unchanged; Lua.Eval
and attempts to enable client Lua were denied. Evidence is under `out/multiplayer-evidence/probe7*`;
the prior cache-flush crash analysis is in `out/debug-crash-analysis/findings.md`.
See [TESTING.md](../TESTING.md#multiplayer-bootstrap-and-rtxdebug) for the live acceptance matrix.

## Alternatives considered

- Forcing `sv_allowcslua` or replacing global Lua APIs would expand community permissions beyond the
  user's authorization.
- A generic native evaluator or filesystem reader would escape the committed owner catalog.
- Retaining a package-wide `-insecure` requirement would prevent the requested launch behavior.
- Allowing arbitrary rendering patches by owner or module name alone would let changed manifests
  inherit permissions; exact reviewed recipe groups keep the exception bounded.
