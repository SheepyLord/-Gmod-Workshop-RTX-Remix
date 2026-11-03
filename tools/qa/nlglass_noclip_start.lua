-- R14 (the user's item 41): starts the G1 QA add-on's noclip steps (tools/qa/nlglass_qa) from client Lua,
-- two seconds after it is sent, so poc_session.py --lua-shots is already watching for NL_SHOT lines.
timer.Simple(2, function() RunConsoleCommand("nlglass_qa", "noclip") end)
