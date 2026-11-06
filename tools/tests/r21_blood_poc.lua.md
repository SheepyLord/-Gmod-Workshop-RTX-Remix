# r21_blood_poc.lua

Client acceptance probe sent through `poc_session.py --lua` in a locked R21-A PoC session. The
runner installs the server portion of `r20_blood_poc.lua` as a temporary local fixture first.
Never packaged. Needs gm_construct, client console Lua, RTX, the complete candidate package,
`r20c_spawn`/`r20c_fire`/`r20c_resume`, and screenshot acknowledgements from `--lua-shots`.

Shows the eight original shapes in four families and all twelve schemes; records winning VMT
SHA-256s, shaders, base textures, tints and Remix texture hashes. Checks master-off restoration
against the disabled baseline, stamps C++ Blood/YellowBlood decals, shoots citizens, Combine,
zombies, antlions and a ragdoll with actual weapons, then stresses the existing impact budgets.
Screenshots use `NL_SHOT`; JSON lines start `R21A_`, final marker is `NL_SHOT_DONE`. Lua assertions
fail on missing patterns, restoration differences or budget overrun. The server fixture also
prints `R20C_BULLET`/`R20C_TARGET` lines for actual hit evidence.

Reads packaged materials and local convars, changes only test-session convars, temporary camera/HUD
hooks and engine decals/particles. Restores captured client settings on completion; the locked
runner must restore field settings before normal quit, PoC snapshots and video registry settings.
No network, source-project, field, Workshop, Steam settings or runtime-global option writes.
