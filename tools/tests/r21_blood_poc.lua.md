# r21_blood_poc.lua

Client acceptance probe sent through `poc_session.py --lua` in a locked R21-A PoC session. The
runner installs the server portion of `r20_blood_poc.lua` as a temporary local fixture first, plus
`r21a_grid`, which positions the player near the sample grid without spawning a target.
The fixture's `r21a_native` broadcasts server-side Blood/YellowBlood decals through the engine.
Never packaged. Needs gm_construct, client console Lua, RTX, the complete candidate package,
`r20c_spawn`/`r20c_fire`/`r20c_resume`, and screenshot acknowledgements from `--lua-shots`.

Shows the eight original shapes in four families and all twelve schemes; records winning VMT
SHA-256s, shaders, base textures, tints and Remix texture hashes. Checks master-off restoration
against both the disabled baseline and winning VMT texture/tint values (including shared original
model materials). Lua-created blood convars use synchronous SetString, since RunConsoleCommand
queues changes; engine HUD convars use console commands because SetString cannot modify them.
Grid decals trace the actual brush/displacement surface, rather than assuming a fixed floor Z.
They are stamped after the queued clear command has run; otherwise the next frame erases them.
Stamps C++ Blood/YellowBlood decals, shoots citizens, Combine,
zombies, antlions and a ragdoll with actual weapons, then stresses the existing impact budgets.
When the private Physics Blood fixture is mounted, also draws its own drops, pools and stain
overlays and records counts/render-guard errors; no third-party source is copied into this probe.
Screenshots use `NL_SHOT`; JSON lines start `R21A_`, final marker is `NL_SHOT_DONE`.
Large records use numbered `R21A_CHUNK` lines below Source's 4,095-character print limit. The
native broadcast frame allows five seconds for delivery and first-use lazy PBR texture loading;
the palette-change frame waits two seconds.
Lua assertions fail on missing patterns, restoration differences or budget overrun. The server fixture also
prints `R20C_BULLET`/`R20C_TARGET` lines for actual hit evidence.

Reads packaged materials and local convars, changes only test-session convars, temporary camera/HUD
hooks and engine decals/particles. Restores captured client settings on completion; the locked
runner must restore field settings before normal quit, PoC snapshots and video registry settings.
No source-project, field, Workshop, Steam settings or runtime-global option writes. Server console
commands and native decal broadcasts stay inside the private test game.
