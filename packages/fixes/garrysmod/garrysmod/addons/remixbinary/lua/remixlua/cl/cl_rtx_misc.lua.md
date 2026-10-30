# cl_rtx_misc.lua

Owns client proxy creation/removal and the generic model draw fixer. The fixer leaves procedural
shards, the player proxy and entities marked RTXCustomDraw alone, preserving their material
and bone rendering. Ordinary entities retain the existing lighting/submaterial fixes. Proxy
switches are archived client convars; this script never writes Remix user.conf. Source sidecar
excluded from deployed Lua scripts by package_fixes.py.
