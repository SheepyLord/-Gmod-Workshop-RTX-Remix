# nlglass_qa_start.lua

Client Lua for `poc_session.py run --lua tools\qa\nlglass_qa_start.lua --lua-shots 600`: two seconds after
it is sent it runs the console command `nlglass_qa`, which the QA add-on
[`nlglass_qa`](nlglass_qa/lua/autorun/nlglass_qa.lua.md) defines (copy that add-on into the test install's
`garrysmod/addons` first and remove it afterwards). Nothing else; exit codes: none (game Lua).
