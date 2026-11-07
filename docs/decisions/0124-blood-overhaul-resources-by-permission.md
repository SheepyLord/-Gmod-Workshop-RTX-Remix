# ADR 0124: Blood Overhaul resources and their PBR ship by permission

Status: accepted (R21-A, the user's instruction). Date: 2026-11-06.

Supersedes ADR 0118's exclusions of Crunchy's resources and derivatives and its statement that no
stock blood material is replaced. On 2026-11-06 SheepyLord reported the resource author's permission
and asked for the resources to be packaged and published with this project's RTX package (Workshop
item 3829070317), whose inputs this public repository holds. The permission's terms were not
provided; this record does not infer additional terms or a separate repository grant. The Workshop
credit section remains the user's responsibility.

Include the runtime materials/textures from the user's `dist/addon`, and every PBR DDS and both
texture-hash kinds from `dist/remix_mod/blood_overhaul_rtx`. Preserve selected source bytes;
compare the original MD5 inventory to label Crunchy's unchanged files and the user's edits.
The preparation audit covers every source-project file with SHA-256 and a selection/exclusion
reason. Source/reference images, backups, archives, previews and development outputs stay out.
Legacy Lua is replaced by the private companion implementation, retaining the twelve scheme data
tables and all 26 published shape sizes. The unused old droplet stays out; R20-C's analytic sprites
and opacity materials remain unchanged. All DDS dependencies must be present, with none unreferenced.

Keep R20-C's private mixer, exact-path legacy include guard, four species families, budgets and
distinct deployment folders. Red/alien VMTs retain the user's bytes; green/worker variants follow
R20-C's alpha-decal recipe. The combined replacement layer keeps lazy texture loading, now with
186 hash entries: the original 182 plus the four analytic sprite entries.

Stock blood/yblood, flesh/alienflesh, antlion and stain materials now look like Blood Overhaul while
the package is active, including blood placed directly by C++. Apply colour schemes to the same
stock subrect and world/model flesh materials the original `cl_core.lua` recoloured. Snapshot each
material's base texture and effective tint before changing it; the master off switch restores those
values and disables the mixer/extra impacts. It does not unmount packaged VMT/VTF files, remove
their PBR or clear decals. Impact off/amount zero only restores native impact dispatch. Removing
the package restores journaled payloads under the loader's existing ownership rules.

Do not alter another add-on's Subrect parent or DecalModulate shader through the tint controller.
When another mounted add-on wins a material name, its effective VMT remains the winner; the layer
also covers Crunchy's original texture hashes with explicit opacity instead of legacy modulation.
Record the actual winners and renders in PoC coexistence evidence. Use the package without the
duplicate legacy/subscribed copy if its winning shader cannot accept colour schemes safely.

Credit Crunchy's Blood Overhaul (2683396098). The resources and PBR derived from them are bundled
following that report and request, remain the author's, and are outside this repository's MIT licence.
No general licence is granted. Keep that statement beside and inside the part. Retain AI-generation disclosure and the original prompts for
the eighteen generated patterns. Import final binaries once through `inputs.py`, then report the
indexed, compressed and package size changes. No trust, native code, Steam or runtime-global
preference changes are needed.
