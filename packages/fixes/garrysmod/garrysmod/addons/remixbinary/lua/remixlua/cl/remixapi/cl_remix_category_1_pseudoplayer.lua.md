# cl_remix_category_1_pseudoplayer.lua

Registers only private pseudoplayer/pseudoweapon material names with RemixCategoryManager.
Body materials receive model and body-anchor bits; weapons receive the model bit. Original shared
player/arm/ragdoll materials are never scanned or categorized. Existing auto-category switches and
manual commands remain; a periodic proxy-only lookup supports older weapon proxies. Registration waits for the first real draw hash, avoiding premature filesystem lookups for Lua
materials. Native hash tracking and pending categorization stay owned by the shared manager. Writes transient runtime
categories only, with no config-file changes. Sidecar excluded from the deployed Lua addon.

With automatic player categorization enabled, original player/hand/ragdoll material hashes are
migrated out of the player category in memory, including saved-file tags absent from the native
tracker's bookkeeping. Non-player category bits are preserved. No saved config is modified.
