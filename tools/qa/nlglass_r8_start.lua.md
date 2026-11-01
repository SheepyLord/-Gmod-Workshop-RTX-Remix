# nlglass_r8_start.lua

Client Lua for Claude's PoC QA. Waits two seconds, then runs host-only `nlglass_qa r8` from the
QA add-on. Pair with the existing `poc_session.py --lua-shots 240` workflow; the first screenshot
waits 61 seconds to test an old sleeping pile. See the [QA sidecar](nlglass_qa/lua/autorun/nlglass_qa.lua.md).
Requires the matching R8-G module and Lua, gm_construct and a listen server. Never shipped.
The QA changes session entities, host inventory/position/input and temporary client glass settings;
the sequence restores saved collision/master/lifetime values on completion. If interrupted, use
the saved values printed/documented by the QA or reset them manually. No file writes or exit code.
