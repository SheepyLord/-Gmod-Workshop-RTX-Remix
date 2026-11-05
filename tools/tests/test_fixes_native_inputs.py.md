# test_fixes_native_inputs.py

Compiles and runs the RTX fixes' R19 input checks from their GPL source copies in
`packages/fixes/licenses/oversized-skinning`
([ADR 0112](../../docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)):

- `autopbr/tests/lua_path_policy_test.cpp` tests `source/lua_path_policy.h`, the rules the module's
  Lua functions apply: relative game paths (roots, UNC, `\\?\`, drives, streams, `..`, shortened
  and device segments, control characters, length), local model files, option values that name a
  drive or network path, the Remix options whose value is a file or folder, and folders kept inside
  ToPBR's own.
- `rtxwater/source/rtx_water/test/lua_input_test.cpp` tests RTX Water's `lua_input.h`: surface
  polygons of an even count of at least six finite numbers, and texture paths below the game folder.
- Without a compiler, each new file of `autopbr/lua-paths.patch` and `rtxwater/rtxwater-lua-input.patch`
  equals its copy beside the patch, line endings aside.

`python -m unittest discover -s tools/tests -p test_fixes_native_inputs.py -v`. Uses MSVC through
`tools/lib/VsDevEnv.psm1` (`/std:c++17 /W4 /WX`, assertions on); compiler output goes to a scratch folder
under `out\tmp`, removed afterwards. No game or network. Without the Build Tools the two compiled checks
are reported skips. Exit 0 when all pass, 1 otherwise.
