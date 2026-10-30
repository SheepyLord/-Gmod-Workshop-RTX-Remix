# 0043: Separate first-person arms, local body shadows and shared world models

- Status: accepted
- Date: 2026-10-30
- Decision maker: the user, reporting missing first-person arms when primary-space player models
  are enabled and requesting player-shadow and vertical-offset controls in the RTX spawn tab.

## Context

The runtime explicitly returned from createViewModelInstances when enableInPrimarySpace was true.
The shipped classic defaults also tagged 549 player texture hashes and three body hashes. The Lua
auto-categorizer added original player materials whenever unique_hashes was off (the classic
setting), affecting arms, other players and ragdolls that shared those textures. The shadow entity
created two bonemerged body models and changed the real player's root bone; its default offset mode
ignored Z.

## Decision

ViewModel.enable and the viewmodel camera control first-person rendering independently of the
primary-space body setting. Remove that early return; retain normal viewmodel correction, masks,
portal copies and the explicit viewmodel off switch. This is a C++ change with no shader/ABI change.

Only private first-person proxy textures receive automatic player-model categories. The default
layer contains no captured shared-player hash list; the defaults exporter also strips that list.
The shipped primary-space body default returns to false; the captured true workaround is no
longer needed for world models. Authored user.conf/rtx.conf overrides are untouched. The Lua proxy always makes a distinct private
texture, even with the legacy unique_hashes=0 setting. Inverting one sampled pixel's blue channel
guarantees a change for white textures too; preserve its alpha and cache per material/skin.
Use public shader families and a diffuse fallback for Source eye shaders in the proxy.

Use one independent client body with a copied world-space player pose and private material
overrides. The generic model fixer preserves its custom draw hook. Translate
only its finished render bone matrices for the requested world-Z lift. Do not move the real player,
camera, collision or shared skeleton. Keep body groups, skin and player color synchronized. Separate
weapon proxy ownership, hide during death/spectating/third-person views, and restore render state
after a failed draw.

RTX Remix / Rendering / Player models provides Local player shadow (rtx_pseudoplayer) and Body
height offset (rtx_pseudoplayer_offset_z, -32 to 64 units in the UI). Enabling the shadow requests
Remix primary-player shadows through the existing API. These archived client values apply at
startup; they do not write Remix user.conf. All five new UI strings are translated into the six
supported languages.

## Consequences

World models sharing normal player textures remain ordinary world geometry. Body visibility no
longer removes arms. With automatic player categorization enabled, legacy player tags on original player, hand and
ragdoll textures are removed in memory while unrelated category bits are preserved. This also
handles existing rtx.conf/user.conf captures, not just clean defaults. The files remain unchanged;
disabling automatic categorization before restarting retains fully manual category behavior. A restart applies the new runtime and clears old
session-only categories. Proxy texture creation retains the existing PNG-cache technique and its
initial capture cost; copies are reused, rather than recreated every draw.

## Validation

Generated Lua tests execute the actual proxy, category module and menu, including zero legacy
unique_hashes, white textures, world-Z offsets in both angle modes, unchanged real-player bones,
skin/body groups, hidden states and failed-draw cleanup. Real PoC sessions compare primary-space
off/on before and after the rebuilt runtime and check shadows/height with shared-texture models.
The runtime recipe, submodules and clones are verified before the C++ incremental rebuild.
