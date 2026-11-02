# debris_blast.lua

Server-only, read-only blast observation. Wraps `util.BlastDamage` and `util.BlastDamageInfo` while
preserving their original arguments/returns; refresh restores only wrappers it still owns.
Observes `env_explosion`/`env_physexplosion` Explode inputs and `BaseGrenade.Explode`. PoC evidence
confirms that native barrels and RPGs reach the input observer even without damage victims. No
entity polling, whole-map scan or idle Think hook.

`NLGlass.Blasts.Emit(origin,radius,damage,source)` validates and coalesces observations within 32
units/0.1 s, upgrades unsent duplicates, and sends at most 32 events/s (burst 16, pending 32).
Radius caps at 2048 units and kick speed at 1800 units/s. Two deferred turns preserve engine-owned
OnBreak order; epoch changes cancel work. Damage fallback uses the inflictor, not grenade thrower
reported position. Counters and an optional observation callback support QA. No Source mutations,
files or process exit codes. Unrecognized custom native explosions still require a known signal.
