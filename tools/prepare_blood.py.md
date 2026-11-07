# prepare_blood.py

After preparing the resources, run `prepare_blood_particles.py` for the two analytic sprites'
authored opacity DDS/material entries; these retain their tint under path tracing. Only its final
two DDSs and updated text layer are imported. The VTFs produced here remain unchanged.

Read-only resource selection for R21-A's Blood Overhaul RTX part (ADR 0124). Run from the worktree root:

```powershell
python -I tools/prepare_blood.py --project H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx --out out/r21a/prepared
```

Reads the project's `work/manifest.json`, `dist/addon`, `dist/remix_mod/blood_overhaul_rtx`, original
MD5 inventory, colour schemes and generation prompts. Selects all runtime VMT/VTF materials except
the unused old flying droplet, and all 177 source DDSs/182 hash overrides. Selected source files keep
their bytes. Includes stock-name blood/yblood, flesh/alienflesh, antlion and stain resources. The
eight original shapes precede eighteen generated shapes at their published world sizes; red/alien
VMTs retain source bytes, green/worker VMTs follow R20-C. Validates complete shapes/hashes and exact
DDS dependency closure. The private layer uses lazy loading. Makes the unchanged analytic 128px
droplet and 64px mist VTFs without reading an existing image; the later tool appends their PBR.

Outputs a new folder strictly under this worktree's `out/`: `nlblood` (add-on),
`nl_blood_overhaul_rtx` (Remix mod), `provenance.json` (selected/excluded source hashes and reasons)
and the original prompts text (reference images excluded). Schema 2 audits every source-project file,
selected or excluded, with SHA-256 and reason; MD5 comparisons distinguish Crunchy's unchanged files
from the user's edits, derived resources and owned patterns. Generated outputs have separate hashes;
the sprite tool refreshes these after appending its materials. The author, date and SheepyLord's
reported permission/request are explicit; no unspecified permission terms or general licence are inferred.
Legacy Lua is replaced by the private controller/data. Archives, source/reference images, backups,
previews and development files stay out. Refuses an existing output. Writes no
game/source files, does not import to LFS or publish. Import the final inventory with `inputs.py`;
the provenance and prompts belong in the part's `licenses/` folder. New particle/controller Lua is
maintained in the companion and attached to the part by `workshop.json`.

No third-party Python dependencies. Exit 0: prepared; 1: validation/I/O failure; 2: arguments.
Tests: `tools/tests/test_r20_blood.py` (pure source-selection and Lua behaviour).
