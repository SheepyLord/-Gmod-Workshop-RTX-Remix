# procedural_glass_tool.lua

Original MIT implementation retaining the glass tool command name.

GMod toolgun loads this file. Left click converts prop_physics to a flat convex glass envelope or resets an existing pane; right click creates a rectangular pane. Client settings choose width/height/thickness/kind/strength. Server validates bounds, sandbox limits and CPPI permissions, creates frozen collision before removing the old prop, assigns ownership, cleanup and undo. No files, package materials or native/private debris API are accessed.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
