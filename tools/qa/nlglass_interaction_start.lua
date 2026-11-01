-- MIT. Start R7-C's host-only interaction steps after screenshot capture is ready.
timer.Simple(2, function() RunConsoleCommand("nlglass_qa", "interact") end)
