# debris_preview.lua

Transient client meshes for descriptors whose Jolt bodies are queued. `Add(rows,context)` groups up
to 24 descriptors per mesh, `Remove(row)` marks a descriptor consumed, `Offset(group)` returns its
ballistic translation/velocity and `Draw(geometry,retire)` uploads dirty chunks and draws them in
the receiving frame. Uses the pane's material, exact polygons and a shared chunk trajectory; the
native handoff starts at that pose. Preview age caps at 0.5 seconds during a slow world import.
`Clear(retire)` cancels all previews. No network, files, Source bodies or gameplay mutations.
Client errors propagate to the caller; there is no process exit code.

Previews use only front/back faces and omit edge extrusion until native construction. Eight
bounded ballistic kick records per chunk make queued glass react immediately to explosions.
The native handoff retains its own exact per-body blast history, avoiding a double kick.
