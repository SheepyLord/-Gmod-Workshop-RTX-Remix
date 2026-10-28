# M7 plan: the field install

- Author and implementer: Claude, 2026-10-28, under the user's instruction to plan, build and test
  M5-M7 without further approvals. AGENTS.md rule 1: the field install changes only because the user
  asked for this milestone in this conversation, and only after a snapshot of what will be touched.
- Branch: `m7-field` in the main checkout, from `main` with M5 and M6 merged.

## Goal (roadmap M7)

On the user's Steam-managed install `H:\SteamLibrary\steamapps\common\GarrysMod`: RTX on and RTX off
both work next to what the user already has there (their DXVK `d3d9.dll` for non-RTX play,
GModPatchTool's `bin\win64\vulkan-1.dll`, the MMD Hot Loader, Jolt), and a one-command rollback puts
the install back exactly.

## Steps

1. `tools/field_snapshot.py snapshot` ([doc](../../tools/field_snapshot.py.md)): the files a session
   or the loader can change (by copy), the paths the loader creates, the folders it deploys into, and
   GMod's shared registry settings.
2. Install the bootstrap (`install-loader.ps1 -AllowSteamManaged`) and a `config.json` allowlisting
   the two M5 packages (runtime B with the classic layers and `-insecure`; the fixes package).
3. RTX on, gm_construct, launched the way `poc_session.py` launches (`bin\win64\gmod.exe` from the
   root, `-noworkshop`, local add-ons on): `d3d9.dll` must come from the runtime package (not the
   user's DXVK in `bin\win64`), `vulkan-1.dll` from System32 (not GModPatchTool's), the shader override
   and patches active; the user's MMD Hot Loader runtime and Jolt loaded as they are without the
   loader; a path-traced frame.
4. RTX off (`remix.enabled: false`): the user's DXVK `d3d9.dll` from `bin\win64` as before, no runtime,
   no patches or override, the session variables put back by the restore cfg.
5. `tools/field_snapshot.py rollback`: one command; then the listings match, the recorded files and
   registry values are back, and `verify_install.py` reports every depot file OK.

## Not done here

- Changing Steam launch options or settings (rule 5): the loader needs none.
- Leaving the loader installed: the rollback runs at the end; installing it for real is the user's
  call, with `tools\install-loader.ps1 -GameRoot <field install> -AllowSteamManaged` and a `config.json`.
