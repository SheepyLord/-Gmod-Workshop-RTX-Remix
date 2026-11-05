# RTX Water: native core, wave simulation and build tools

The addon is documented in [docs/RTX_WATER.md](../../docs/RTX_WATER.md) and its wave model in
[docs/rtx_water/wave_simulation.md](../../docs/rtx_water/wave_simulation.md). This folder holds
the parts that are built rather than shipped as they are:

- `rtxwater.cpp`, `wavesim.h`, `wavesim.cpp`: the native core, `gmcl_rtxwater_win64.dll`. The
  repository's premake workspace builds it (`premake_project.lua`); `build.bat` builds it alone.
- `lua_input.h`: what `RTXWaterNative` takes from Lua, which any server's client Lua reaches:
  `SetSurface` skips a polygon that is not an even count of at least six finite numbers, and
  `SetMaterial` keeps the current material when a texture path would leave the game folder.
- `test/`: offline wave scenarios (`build_test.bat`, `wavetest.cpp`, `view.py`), the Lua input
  check (`lua_input_test.cpp`, standard C++ only) and scripted in-game tests on gm_poolrooms'
  canal (`test/ingame/`).
- `tools/`: `build_water.py` builds the Remix mod, tag textures and `cl_data.lua` from
  `presets.json` into `garrysmod/`; `fit_wave_kernel.py` fits the simulation's kernel.

`build/`, `test/build/` and `work/` are local outputs and are not in git.
