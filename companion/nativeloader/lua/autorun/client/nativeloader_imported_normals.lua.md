# nativeloader_imported_normals.lua

Optional world-render normals for Model Hotloader characters and static props. The archived
ConVar nativeloader_imported_model_normals defaults off and is exposed beside both spawn controls.
Every quarter second it gathers active material hashes, including late captures and overrides,
and writes only the runtime's additive NoSave importedModelSmoothNormalTextures option.
Startup, disabling or removing models clears stale owned tags. Authored files and saved category lists remain
unchanged. Remix generates area-weighted geometry normals; normal maps remain active. Texture
tags affect every draw sharing those captured textures, including another instance or preview.
No disk/network operations, game launch, or exit status. Missing APIs are skipped and rejected
updates are retried. GPU validation is intentionally waived for requests 17–20.
