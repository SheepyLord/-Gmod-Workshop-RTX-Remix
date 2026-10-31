"""DDS encoding with the NVTT exporter bundled in the RTX Remix Toolkit.

The arguments and ``.<x>.rtex.dds`` suffixes are the Toolkit's own
(``omni.flux.validator.plugin.check.usd.texture.convert_to_dds`` and
``asset_importer`` constants), so the files match what Remix ingestion makes.
"""

from __future__ import annotations

import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import config

ARGS = {
    "albedo": ["--format", "bc7", "--mip-gamma-correct"],
    "normal": ["--format", "bc5", "--no-mip-gamma-correct"],
    "roughness": ["--format", "bc4", "--no-mip-gamma-correct"],
    "metallic": ["--format", "bc4", "--no-mip-gamma-correct"],
    "height": ["--format", "bc4", "--no-mip-gamma-correct", "--mip-filter", "max"],
    "emissive": ["--format", "bc7", "--mip-gamma-correct"],
    # The Toolkit has no converter setting for anisotropy; it is linear data like roughness.
    "anisotropy": ["--format", "bc4", "--no-mip-gamma-correct"],
}
SUFFIX = {"albedo": "a", "normal": "n", "roughness": "r", "metallic": "m", "height": "h", "emissive": "e",
          "anisotropy": "an"}


def dds_name(key: str, kind: str) -> str:
    return f"{key}.{SUFFIX[kind]}.rtex.dds"


def encode(jobs: list[tuple[Path, Path, str]], workers: int = 4, log=print) -> None:
    """jobs: (source png, destination dds, kind)."""
    nvtt = config.nvtt_path()

    def run(job):
        src, dst, kind = job
        dst.parent.mkdir(parents=True, exist_ok=True)
        tmp = dst.with_name(dst.name + ".tmp.dds")
        cmd = [str(nvtt), str(src), "--output", str(tmp), *ARGS[kind]]
        result = subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
        if result.returncode != 0 or not tmp.exists():
            raise RuntimeError(f"nvtt_export failed for {src.name}: {result.stdout[-400:]} {result.stderr[-400:]}")
        tmp.replace(dst)
        return dst

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for dst in pool.map(run, jobs):
            log(f"  wrote {dst.name}")
