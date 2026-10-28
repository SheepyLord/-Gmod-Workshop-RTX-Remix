#pragma once
#include <windows.h>
// M5 probe: after main starts, loads bin\win64\engine.dll and bin\win64\stdshader_dx6.dll the way the
// engine does, lists garrysmod\addons through bin\win64\filesystem_stdio.dll the way GMod does, and
// records what it got, with the command line, as JSON in `output`.
int session_probe(const wchar_t* output, const wchar_t* bin);
