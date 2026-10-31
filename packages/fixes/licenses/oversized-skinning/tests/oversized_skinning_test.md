# Oversized skinning regression

Compile oversized_skinning_test.cpp as a standalone C++17 executable. It loads
the production policy and borrowed-palette snapshot helper without a game, GPU
or Windows SDK. Assertions cover 32,767/32,768/40,509 vertices, invalid counts,
hardware versus software groups, flex exclusion, palette/blend restoration,
complete strip-local slot coverage (a stale cache cannot fill missing slots),
user-forced small groups versus unchanged default/diagnostic-filter behavior, same-group nesting,
the unsupported static-fallback guard, exception cleanup and incomplete-capture failure. Exit zero and a PASS line
indicate success. Keep the executable and compiler outputs under the aggregate
repository's ignored out directory.

Runtime acceptance must exercise the same large non-flex HW group with
r_forcehwskin both zero and one, then render ordinary models and arms to catch
blend/palette leakage. The automatic path must not change the convar, must skip
an eligible draw if its required state cannot be captured, and must leave all
noneligible model groups and existing forced-flex behavior alone.
