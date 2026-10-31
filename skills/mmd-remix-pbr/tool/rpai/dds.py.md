# dds.py

DDS encoding with the NVTT exporter bundled in the RTX Remix Toolkit.

The arguments and ``.<x>.rtex.dds`` suffixes are the Toolkit's own
(``omni.flux.validator.plugin.check.usd.texture.convert_to_dds`` and
``asset_importer`` constants), so the files match what Remix ingestion makes.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Runs the RTX Remix Toolkit's NVTT exporter (a subprocess) and writes the `.dds` files it is given.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
