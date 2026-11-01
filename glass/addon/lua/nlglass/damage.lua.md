# damage.lua

Every damage cause normalized to a pane-local impact.

Server-only include after Geometry/Config. FromDamage, FromCollision, FromBody and Fallback take records and engine objects. Normalize returns point/direction/energy/kind/seed plus attacker/inflictor and advances only the record seed. The real HitObject PhysObj supplies collision mass. No physics, network or file mutations occur here.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
