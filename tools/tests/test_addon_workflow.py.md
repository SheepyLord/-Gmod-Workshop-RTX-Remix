# test_addon_workflow.py

Runs two LuaJIT behavior checks without starting Garry's Mod. Use tools/test.ps1 or
`python -m unittest discover -s tools/tests -p test_addon_workflow.py` from the repository root.
The AME case loads its actual naming helper and navigation methods, excluding unrelated GLua
rendering. The imported-normals case loads the complete shipped module. Tests cover current-row
handoff, original names/path identity, missing metadata, shared hashes, late capture, toggles,
removed models, previews, props and API retries. The Motion importer tab is tested by
[test_motion_tab.py](test_motion_tab.py.md).
Only temporary test source is written under out/tmp; LuaJIT is optional on CI. Exit zero on success.
