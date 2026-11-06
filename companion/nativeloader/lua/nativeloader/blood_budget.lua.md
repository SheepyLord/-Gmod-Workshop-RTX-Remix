# blood_budget.lua

Pure Lua rolling-second and live-count admission budget. `New(rate, maximum)` returns a budget;
`Take(now, lifetime)` admits one resource only within both bounds. `Prune` retires expired entries;
`Reset` starts a new map/explicit-clear epoch. Expiration is conservative for early particle deaths.
Inputs are the controller's monotonic CurTime and bounded positive lifetimes. No GMod API, I/O,
networking or exit code. Used for 640 particles/second, 512 live and 48 stains/second, 384 per epoch.
