# gma_diff.py

Compares the members of two `.gma` archives by name and by the SHA-256 of their bytes.

It was written to tell whether two Model Hotloader imports of the same PMX carry the same textures:
their generated archives (`<cache>\assets\<id>\materials-v5.gma`) name members after the asset
(`materials/mmd/<first 16 hex digits of the id>/...`). That folder is replaced by a placeholder by
default, so two imports compare by content. It also compares any two plain GMAD v1-v3 archives, such
as a build and the copy Steam downloaded (whole-file SHA-256 is quicker for that:
`Get-FileHash`).

```powershell
$a = 'H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\garrysmod\data\mmd_hotloader\assets\1c2ed2fc7120e0e54ef3e97dceadad39537a11f5b635dbcf5074a769c377d2d2\materials-v5.gma'
$b = 'H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\data\mmd_hotloader\assets\bf8aee595ec1f662fb1769a5739399814d9dbb19f4e9c8b2d09f3078a4832f11\materials-v5.gma'
python -I scripts\gma_diff.py $a $b
# names A: ['materials/mmd/1c2ed2fc7120e0e5/arm_2.vmt', ...]
# names B: ['materials/mmd/bf8aee595ec1f662/arm_2.vmt', ...]
# members 77/77; same bytes (folder stripped) 77; vtf 14, vtf same 14
```

## Options

| Option | Meaning |
|---|---|
| `a`, `b` | the two archives (read only) |
| `--no-strip` | compare member names exactly |
| `--all` | list every differing member (default: the first 20 of each kind) |

## Output

The first three member names of each archive, a summary line (`members A/B; same bytes N; vtf V,
vtf same S`), then `differs:`, `only in A:` and `only in B:` lines.

## Side effects

None: it only reads. It streams the archives (several GB are fine). It does not read the LZMA-wrapped
Workshop `*_legacy.bin` form. Standard library only; runs with `python -I`.

## Exit codes

0 the same members with the same bytes; 1 they differ; 2 bad command line, unreadable file or not a
plain GMA.

## Verified (2026-10-31)

- The classic import of Guinaifen (`1c2ed2fc`) against the user's re-import (`bf8aee59`): 77 of 77
  members and 14 of 14 VTF textures identical, the Guinaifen session's result. So the PBR's texture
  hashes do not depend on which import is spawned.
- The classic import against the field copy Model Hotloader installed from the Workshop package and
  rebuilt locally: also identical.
- The Robin archive Steam downloaded against the build: 81 of 81 identical.

## Provenance

Written for this user by Claude in the second Guinaifen session (2026-10-29); tidied for this skill
(2026-10-31: streaming, GMAD v1-v2 headers, a placeholder for the asset folder only (the first
version cut the first three path parts, which could merge unrelated names), member lists, exit
codes). Not third-party code.
