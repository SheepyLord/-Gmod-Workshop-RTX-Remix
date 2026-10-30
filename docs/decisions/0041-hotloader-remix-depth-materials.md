# 0041: Hotloader depth materials follow the active shader family

- Status: Accepted 2026-10-30, implementing the user's request to fix or suppress the unknown
  `DepthWrite` errors when a Hotloader model loads.
- Scope: the bundled Model Hotloader Lua input and source-documentation packaging; no native binary,
  asset, carrier or saved-data format change.

## Cause

The native renderer reports `fixedFunctionRemix` when the game uses the fixed-function shader
family. That family does not load the programmable `stdshader_dx9.dll` containing `DepthWrite`.
The Lua renderer nevertheless created depth materials eagerly during every asset's first color
registration. The reported 83-slot asset reproduced 83 such requests and 131 unknown-shader lines
in the baseline PoC run: 83 belonged to Hotloader; 48 were separate built-in engine materials.
Color rendering continued through the material-system fallback.

## Decision

Initialize/check the native renderer before caching its backend flag. For fixed-function Remix,
register the existing valid public color material names in the unused depth slots and skip Source
shadow/SSAO depth-view draws. Remix gets its geometry and ray-traced shadows from normal scene
draws. No unsupported shader is requested and no console message is filtered.

Programmable Source retains its existing `DepthWrite` materials, real uploaded textures, alpha-test
threshold, cull behavior and pending-texture recovery. Its depth-view draws continue normally.
Material cache version 11 refreshes existing registrations without changing asset or carrier IDs.

## Validation

The offline tests execute the actual production builders and DrawCarrier with a simulated initial
unresolved backend, stale caches and delayed textures. They reject any DepthWrite request or depth
submission on Remix, verify valid public material mappings, retain Source's depth shader and both
view flags, and check color/flashlight draws, render-state restoration and bounded caching.

Real PoC acceptance uses the specific asset named in the error from the existing PoC cache. Model
data is neither copied into the repository nor published. Package changes are imported through
inputs.py, built and compared on the branch, then delivered through the normal main/Workshop hooks.

## Source documentation stays out of executable addon folders

The full-package acceptance run exposed a preceding glass-package regression: GMod enumerated
`entities/procedural_shard.lua.md` and tried to include it as an entity script. The fixes packager
now excludes Lua sidecar documents from deployment while keeping them in indexed source inputs.
Ordinary README and license files remain. A generated packaging regression test checks that the
real Lua is present, its sidecar is absent and its source documentation is preserved.
