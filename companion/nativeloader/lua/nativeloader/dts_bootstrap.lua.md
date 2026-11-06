# dts_bootstrap.lua

R20-C packaged Dynamic Toolgun Screen autorun adapter. `workshop.json` substitutes this for the
part's original autorun and attaches that original byte-for-byte as
`dynamic_toolgun_screen/nl_original_init.lua`. Its thirteen language catalogs and implementation
remain unchanged. A previously loaded standalone's `DTScreen.Loaded` skips repeat client startup;
server registration also happens once, including delivery of the private original initializer.
Works in both ordinary and verified multiplayer include environments. No disk/settings writes,
new network messages or process exit code. Missing original initializer is a normal Lua error.
