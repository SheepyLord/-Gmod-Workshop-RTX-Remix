# prepare_blood.py

After preparing the owned patterns, run `prepare_blood_particles.py` for the two analytic sprites'
authored opacity DDS/material entries; these retain their tint under path tracing. Only its final
two DDSs and updated text layer are imported. The VTFs produced here remain unchanged.

Read-only provenance filter for R20-C's Blood Overhaul RTX project. Run from the worktree root:

```powershell
python -I tools/prepare_blood.py --project H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx --out out/r20c/prepared
```

Reads the project's `work/manifest.json`, `dist/addon_companion`, `dist/remix_mod/blood_overhaul_rtx`,
owned colour schemes and generation prompts. Explicitly selects eighteen named AI-generated
patterns, 36 natural/neutral VTFs, 72 DDSs and their 72 hash overrides. Rejects original/unexpected
texture references, duplicate or missing shapes/hashes, and excluded DDS dependencies. Writes new
red/alien/green/worker world/model VMTs; no stock material names are replaced. PBR uses lazy texture
loading. Makes original analytic 128px droplet and 64px mist VTFs, without reading an existing image.

Outputs a new folder strictly under this worktree's `out/`: `nlblood` (add-on),
`nl_blood_overhaul_rtx` (Remix mod), `provenance.json` (selected/excluded source hashes and reasons)
and the original prompts text (reference images excluded). Refuses an existing output. Writes no
game/source files, does not import to LFS or publish. Import the final inventory with `inputs.py`;
the provenance and prompts belong in the part's `licenses/` folder. New particle/controller Lua is
maintained in the companion and attached to the part by `workshop.json`.

No third-party Python dependencies. Exit 0: prepared; 1: validation/I/O failure; 2: arguments.
Tests: `tools/tests/test_r20_blood.py` (pure source-selection and Lua behaviour).
