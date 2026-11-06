# ADR 0118: Bundle the user's screen and owned blood patterns

Status: accepted (R20-C, the user's item 48). Date: 2026-11-06.

The combined RTX package gains `toolgun-screen` and `blood-overhaul-rtx`. The screen keeps Dynamic
Toolgun Screen 1.3.1, its thirteen language catalogs and its existing settings. Its tool panel moves
beside the companion's sharp-screen panel in RTX Remix / Rendering; the duplicate Utilities panel is
suppressed. Blood settings have one panel in RTX Remix / Blood, translated by the companion.

The blood project mixes files with different redistribution rights. Import only its eighteen newly
generated patterns, their natural/neutral VTFs, PBR DDSs and corresponding hash entries, and the
user's colour schemes and Lua. Credit Crunchy's 2022 Blood Overhaul (2683396098) for the base/style
and disclose AI image generation. Do not import Crunchy's original files, `bo_blood*`, `bo_yblood*`,
flesh, alien flesh, stains, their derived PBR maps, or the old flying droplet (derived from blood8).
Make new droplet and mist textures procedurally. Keep the original generation prompts as text;
reference images are excluded. A preparation tool records the selected and excluded paths/hashes.

Use distinct deployed add-on folders, keeping legacy standalone folders intact. Blood's private Lua
namespace and an early, exact-path include guard keep the four legacy Blood Overhaul RTX modules
from installing a second mixer or replacing the owned shape list. Screen modules receive an
idempotent include guard; hook/command identifiers stay unchanged. Neither guard affects other
add-ons. Test both virtual-path precedence orders with the standalone copies present.

No stock blood material or PCF is replaced. The package therefore works without Crunchy's add-on;
subscribing to it keeps its own content, and does not grant redistribution rights. The original
project and the field install are read-only inputs. Binaries enter Git only through `inputs.py
import`, after final asset preparation, compressed in LFS. The two standalone parts do not require
Remix; the combined package retains its existing RTX-only activation policy.
