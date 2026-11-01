# config.py

Paths and defaults.

Runtime data (venv, model weights, work files) lives in ``RPAI_HOME``
(default ``%USERPROFILE%\.rpai``) rather than beside the code: PyTorch's
DLLs fail to load from long paths (WinError 206), and work files are large.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

`Settings.emissive_adaptive_intensity` is a publish-time ratio to the fallback USD intensity per
unit scene luminance. Its default `25` is 4.5x the old eye emission at exposure 1, tuned in game on Robin
([ADR 0069](../../../../docs/decisions/0069-tuned-adaptive-eye-emission.md)); `0` disables adaptation. The top-level JSON setting and CLI flag share the same name and merge in
the usual order (extra settings, model preset, CLI). `emission_multiplier` rejects negative or
non-finite values. No class/texture-generation parameters change; cached maps remain usable.

## Side effects

None: paths and defaults (`RPAI_HOME`, default `%USERPROFILE%\.rpai`).

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
