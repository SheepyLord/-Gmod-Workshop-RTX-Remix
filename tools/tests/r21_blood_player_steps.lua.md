# r21_blood_player_steps.lua

R21 review's published-R20 versus candidate comparison using the player's actions. Never packaged.
A locked runner copies the server section before `-- CLIENT PROBE` into a temporary local add-on,
then sends this file with `poc_session.py --lua` after the map is ready. Needs gm_construct, RTX,
the package alone, `--lua-shots 600`, cheats/client Lua enabled and no duplicate blood add-ons.

Actual SMG bursts hit citizens and antlions in front of a frozen stock white cube. Captures the
target/backdrop and nearby floor after each burst. It uses the real Blood panel builder and clear
button's DoClick handler, server game.CleanUpMap, r_cleardecals and realistic/blue/realistic settings,
then repeats the actual shots after every action. A frozen stock white plate makes the small
impact stains visible beside the white backdrop. No synthetic particle dispatch or decal grid is
used. Late views check recovery after ten seconds and an actual changelevel to gm_construct.
The runner installs the whole shared fixture as an autorun; the first client run is explicitly
requested, while a temporary DATA marker resumes only the after-map phase on map restart.
JSON markers `R21_PLAYER_*` report hits,
material variables, impact counters and actual util.DecalEx material calls; screenshot labels use
`NL_SHOT`, ending with `NL_SHOT_DONE`. Delivery retries and duplicate acknowledgements are guarded.

Changes only the test game's entities, camera, HUD and settings. The owning runner restores field
settings before quit, the PoC snapshot and registry afterwards, and verifies depot bytes. No field,
source-project, Workshop, Steam settings, runtime, package input or external-message writes.
