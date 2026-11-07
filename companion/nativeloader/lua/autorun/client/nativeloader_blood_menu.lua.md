# nativeloader_blood_menu.lua

The BO table marks menu registration once, including when the verified multiplayer catalog sees
identical companion/part virtual files under both owners.

R20-C Blood and impacts panel in RTX Remix / Blood. Uses the companion's six gettext catalogs;
without the complete companion a separately built blood part has an English fallback and creates
the tab/category itself. The early bootstrap must have found the blood part.

Controls the preserved `bloodoverhaul_*` settings, twelve schemes, RGB pickers, size, variation and
droplet recolouring; adds `nativeloader_blood_impacts` and amount (0–2). Describes budgets, stock
fallback, the 26 patterns, permission/AI provenance and the persistence of packaged textures/PBR
when master off restores Lua changes. No separate Crunchy subscription is needed. Buttons test two splats, explicitly clear
all decals/reset the stain epoch, and reset settings. The legacy menu module is skipped, so only this
panel registers, even with the standalone copy. No settings are written by opening it.

Inputs: included BO table and client ConVars. Outputs: Derma controls, explicit user console
commands. No disk/network writes or exit code. The screen's own translated controls stay with it.
