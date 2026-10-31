# rtx_pseudoplayer.lua

Client-only first-person body proxy. The RTX tab's rtx_pseudoplayer toggle controls its lifetime;
rtx_pseudoplayer_offset_z translates its rendered bones in world Z, with the existing X/local-angle
options retained. The real player, camera, collision, other players and ragdolls are never moved.
One independent client entity copies the player's pose, replacing the previous parent/child pair.
Its custom draw hook is protected; weapon proxies remain independently owned by cl_rtx_misc.lua. Death, spectating, other view entities and third-person views hide it.

Before drawing, it sets up the real player's bones and snapshots their matrices, original
translations and names. BuildBonePositions reads only that snapshot, avoiding source-player bone
setup inside the proxy's bone callback. Model mismatches skip the draw; the callback clamps to the
source/destination bone counts and skips invalid, unused or unavailable destination bones. Repeated
callbacks apply the offset from each saved origin, so the X/Z offset does not accumulate. Model
changes discard the old snapshot. This also protects multiplayer's initial/model-change frames;
the source player's bones are never modified.

The renderer always uses private copied textures, including when the legacy unique_hashes setting
is zero. It caches copies per material/skin and writes generated PNGs to garrysmod/data/rtx_player_proxy.
One pixel's blue channel is inverted while preserving alpha, so white textures are distinct too.
The proxy uses public shader names and a diffuse fallback for Source-only eye shaders.
Compiled internal flag fields are omitted when cloning the material; authored alpha/cull flags
are retained without duplicate-variable warnings. Only private materials receive player-body categories; rendering resets its overrides after
a draw failure. No user.conf edits or global player-bone changes. This source sidecar is excluded
from the deployed addon by package_fixes.py.
