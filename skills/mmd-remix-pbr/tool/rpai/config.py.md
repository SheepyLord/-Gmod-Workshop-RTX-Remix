# config.py

Paths and defaults.

Runtime data (venv, model weights, work files) lives in ``RPAI_HOME``
(default ``%USERPROFILE%\.rpai``) rather than beside the code: PyTorch's
DLLs fail to load from long paths (WinError 206), and work files are large.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

None: paths and defaults (`RPAI_HOME`, default `%USERPROFILE%\.rpai`).

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
