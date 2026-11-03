# nlglass_noclip_start.lua

Client Lua for `poc_session.py run --map gm_construct --lua tools\qa\nlglass_noclip_start.lua --lua-shots 300`
(R14, the user's item 41). Two seconds after it is sent it runs the console command `nlglass_qa noclip`.
The QA add-on [`nlglass_qa`](nlglass_qa/lua/autorun/nlglass_qa.lua.md) defines the command: copy that add-on
into the test install's `garrysmod/addons` first and remove it afterwards. Nothing else; exit codes: none.
