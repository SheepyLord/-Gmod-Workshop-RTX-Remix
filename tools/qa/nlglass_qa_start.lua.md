# nlglass_qa_start.lua

Client Lua for `poc_session.py run --lua tools\qa\nlglass_qa_start.lua --lua-shots 900`: two seconds after
it is sent it runs the console command `nlglass_qa field` on gm_construct and `nlglass_qa map` on any
other map (for example `--mount-workshop 3495468649 --change-map modern_house`). The QA add-on
[`nlglass_qa`](nlglass_qa/lua/autorun/nlglass_qa.lua.md) defines the command (copy that add-on into the
test install's `garrysmod/addons` first and remove it afterwards). Nothing else; exit codes: none.
