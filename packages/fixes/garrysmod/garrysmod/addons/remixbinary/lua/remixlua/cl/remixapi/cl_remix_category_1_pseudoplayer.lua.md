# cl_remix_category_1_pseudoplayer.lua

Registers only private pseudoplayer/pseudoweapon material names with RemixCategoryManager.
Body materials receive model and body-anchor bits; weapons receive the model bit. Original shared
player/arm/ragdoll materials never receive player categories: they are looked up only to take legacy
player tags off them (below). Existing auto-category switches and
manual commands remain; a periodic proxy-only lookup supports older weapon proxies. Registration waits for the first real draw hash, avoiding premature filesystem lookups for Lua
materials. Native hash tracking and pending categorization stay owned by the shared manager. Writes transient runtime
categories only, with no config-file changes. Sidecar excluded from the deployed Lua addon.

With automatic player categorization enabled, original player/hand/ragdoll material hashes are
migrated out of the player category in memory, including saved-file tags absent from the native
tracker's bookkeeping. Non-player category bits are preserved. No saved config is modified.

The once-a-second timer reads the materials of each model once (the local player, its hands, every
player, ragdolls). A shared material whose hashes are all cleared is done and is not looked up again;
one without hashes yet (not drawn) is looked up after 1 s, then less often, doubling to every 5 s
(review R4: every shared material ever seen was looked up every second for the whole session).
