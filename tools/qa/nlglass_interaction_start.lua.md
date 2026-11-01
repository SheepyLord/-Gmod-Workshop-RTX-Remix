# nlglass_interaction_start.lua

MIT client starter for `nlglass_qa interact`: waits two seconds so the existing PoC screenshot
automation can start watching `NL_SHOT`. Use only on gm_construct with the QA add-on, reviewed
R7-C glass Lua and rebuilt native module installed by Claude. Inputs: current listen-server session;
output: starts the host-only QA sequence. Side effects are documented in the QA add-on's
[sidecar](nlglass_qa/lua/autorun/nlglass_qa.lua.md). No file writes, package changes or process exit code.
