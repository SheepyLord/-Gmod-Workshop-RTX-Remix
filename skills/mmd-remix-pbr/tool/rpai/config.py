"""Paths and defaults.

Runtime data (venv, model weights, work files) lives in ``RPAI_HOME``
(default ``%USERPROFILE%\\.rpai``) rather than beside the code: PyTorch's
DLLs fail to load from long paths (WinError 206), and work files are large.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field, replace
from pathlib import Path

HOME = Path(os.environ.get("RPAI_HOME", Path.home() / ".rpai"))
MODELS = HOME / "models"
WORK = HOME / "work"

REMIX_TOOLKIT = Path(os.environ.get("RPAI_REMIX_TOOLKIT", r"C:\Program Files\NVIDIA Corporation\RTX Remix"))
NVTT_CANDIDATES = [
    REMIX_TOOLKIT / "exts" / "omni.flux.resources" / "deps" / "tools" / "nvtt" / "nvtt_export.exe",
    REMIX_TOOLKIT / "exts" / "lightspeed.trex.app.resources" / "deps" / "tools" / "nvtt" / "nvtt_export.exe",
]

# PBRify_Remix (Kim2091, CC0). NVIDIA's ComfyUI Remix workflow chains these:
# upscale first, then the 1x normal / roughness / height generators.
UPSCALERS = {
    "v4": MODELS / "pbrify" / "4x-PBRify-UpscalerV4.safetensors",
    "span": MODELS / "pbrify" / "4x-PBRify_UpscalerSPANV4.pth",
}
NORMAL_MODEL = MODELS / "pbrify" / "1x-PBRify_NormalV3.pth"
ROUGHNESS_MODEL = MODELS / "pbrify" / "1x-PBRify_RoughnessV2.pth"
HEIGHT_MODEL = MODELS / "pbrify" / "1x-PBRify_Height.pth"


@dataclass
class Settings:
    mod_name: str = "ai_pbr"
    max_size: int = 4096  # long side of generated maps; Model Hotloader caps game textures at 4096
    upscaler: str = "v4"
    height: bool = False  # PBRify's height model needs delit input; off unless asked for
    displacement: float = 0.0  # Remix displace_in; only used with height maps
    # Multiplies every class's emissive weight at publish time, so emission can
    # be re-levelled in game without regenerating any map.
    emissive_intensity: float = 1.0
    tile: int = 512
    presets: dict = field(default_factory=dict)  # class name -> overrides of classify.CLASSES
    # Per texture (source file name or sha16 key): {"max_size": N or "source"}, "normal_map",
    # "albedo_source" (a recoloured copy used and published as the albedo; README).
    # Model Hotloader caps game textures at 4096; Firefly's fishnet stockings
    # sheet is 11059x8847 and its mesh lines blur at 4096, so it opts out.
    textures: dict = field(default_factory=dict)
    # Colour-keyed reclassification inside a texture; see uvmask.apply_regions.
    regions: list = field(default_factory=list)

    @classmethod
    def load(cls, paths: list[Path]) -> "Settings":
        settings = cls()
        for path in paths:
            settings.merge_file(Path(path))
        return settings

    def merge_file(self, path: Path) -> None:
        """Merge a settings file; its ``include`` list (relative paths) is merged first."""
        data = json.loads(path.read_text(encoding="utf-8"))
        for included in data.get("include", []):
            self.merge_file((path.parent / included).resolve())
        for key, value in data.items():
            if key in ("presets", "textures"):
                for name, params in value.items():
                    getattr(self, key).setdefault(name, {}).update(params)
            elif key == "regions":
                self.regions.extend(value)
            elif key in self.__dataclass_fields__:
                setattr(self, key, value)

    def for_texture(self, key: str, name: str, source_size: tuple[int, int]) -> "Settings":
        """These settings with one texture's own overrides applied: its size cap and class presets.

        ``"textures": {"Body.png": {"presets": {"skin": {...}}}}`` changes a class on that sheet
        only; Guinaifen's skin class also covers her neck on the cloth atlas, which must not get the
        body sheet's relief strength or scattering.
        """
        override = self.textures.get(name) or self.textures.get(key) or {}
        max_size = override.get("max_size", self.max_size)
        if max_size == "source":
            max_size = max(source_size)
        changes = {}
        if max_size != self.max_size:
            changes["max_size"] = int(max_size)
        if override.get("presets"):
            merged = {cls: dict(params) for cls, params in self.presets.items()}
            for cls, params in override["presets"].items():
                merged.setdefault(cls, {}).update(params)
            changes["presets"] = merged
        return replace(self, **changes) if changes else self


TOOL = Path(__file__).resolve().parents[1]


def model_presets(key: str) -> Path:
    """Per-model settings (class pins, style) merged automatically when present."""
    return TOOL / "presets" / "models" / f"{key}.json"


def nvtt_path() -> Path:
    for candidate in NVTT_CANDIDATES:
        if candidate.exists():
            return candidate
    raise FileNotFoundError(
        "nvtt_export.exe not found. It ships with the RTX Remix Toolkit; set RPAI_REMIX_TOOLKIT to its folder."
    )


def model_key(asset_id: str, english_name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", english_name.lower()).strip("_")[:32]
    return f"{slug or 'model'}_{asset_id[:8]}"
