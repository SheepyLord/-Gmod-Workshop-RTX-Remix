# nativeloader_motion_tab.lua

The "Motion importer" creation tab beside External Models. It is the bundled Character Motion
Importer's in-game importer and Motion Manager, filling the whole tab in the look of External Models
([ADR 0060](../../../../../docs/decisions/0060-motion-tab-hosts-the-importer.md); it replaces the
launcher button of [ADR 0049](../../../../../docs/decisions/0049-importer-normals-material-labels-and-motion-access.md)).

- **Top bar:** two section buttons, the add-on's "Import MMD Motion" and "Motion Manager" (the
  desktop importer's Inputs and Motion Manager tabs), and on the right **Open in window**, which
  closes the spawn menu and opens the shown section's floating window (`OpenMotionImporter`,
  `OpenMotionManager`). The section shown last is remembered (cookie `nativeloader_motion_section`).
- **The sections** are built by the add-on itself, `MMDVMDNPC.BuildMotionImporter` and
  `MMDVMDNPC.BuildMotionManager` with `{ theme = "light", columns = true }`: the same builders its
  windows and `mmdvmd_import`/`mmdvmd_menu` use, so importing, building and playing are the add-on's
  own code. Each is built the first time it is shown and keeps its state while hidden.
  - Import: the inputs on the left in the desktop importer's order (body motion VMD, music, camera
    VMD, audio offset, the seven metadata fields, face/flex VMDs); on the right the bake and Cancel,
    the bake options, the progress and the log with the output paths. Without Model Hotloader's file
    access a notice says why, with Resolve (and File Access Settings when it is turned off), and the
    file and bake buttons are disabled until it comes.
  - Motion Manager: search, categories, the motion list and its actions (rename, wheel, debug,
    delete) on the left; the selected motion's details, metadata and link, audio offset and
    previews, playback settings, and build/play/stop and the build cache on the right.
- **Waiting:** the tab is filled when it is first shown. Until the add-on's builders exist (it may
  load after this file) it shows the tab's summary; an add-on copy without the builders gets buttons
  that open its windows instead. A builder that fails is reported once (`ErrorNoHalt`) and the tab
  offers those buttons too, instead of building again every frame (review R4).

Text: the tab's title, tooltip, summary and Open in window use the companion's catalogs
(`companion/i18n`); everything inside the sections is the add-on's own, in its nine catalogs. The
stable tab key and the language callbacks keep the title right when Sandbox rebuilds its spawn menu.

The tab itself writes no files and sends nothing; the add-on's sections do what its windows do
(read the files the player chooses through Model Hotloader, write the motion into `data/`, ask the
server for the motion list). No process exit code; missing Sandbox APIs skip registration.
Tested by [test_motion_tab.py](../../../../../tools/tests/test_motion_tab.py.md).
