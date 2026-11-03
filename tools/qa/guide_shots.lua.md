# guide_shots.lua

Client Lua for `tools\poc_session.py run --lua tools\qa\guide_shots.lua --lua-shots 120`. It opens the
spawn menu on the RTX Remix tab and the first pages of the RTX Remix guide, printing `NL_SHOT <label>`
for each so the driver takes a screenshot; `tools\guide_annotate.py` then draws numbered arrows on them.
Needs a session with the companion mounted. Side effects: none on disk. Ends by printing `NL_SHOT_DONE`.
