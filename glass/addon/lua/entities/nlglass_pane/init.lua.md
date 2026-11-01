# init.lua

Pane server lifecycle, event adapters and property-only save/dupe support.

GMod server entity entry point. Initialize validates properties, registers state and builds frozen collision. Damage, physics and touch callbacks forward to the common server pipeline. PreEntityCopy stores a validated property modifier; duplicate/save restore starts intact with preserved geometry/kind/strength. Duplicates lose map-output ownership. May create/remove pane physics and broadcast through the server module; never creates server broken pieces or writes files directly.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
