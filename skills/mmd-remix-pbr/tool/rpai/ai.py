"""Tiled inference for PBRify (ESRGAN-family) models through spandrel.

Tiles overlap and are blended with linear feathering, so seams never show in
the generated maps. Inference runs in fp16 when the architecture supports it
and falls back to fp32 if a tile produces non-finite values. A CUDA
out-of-memory error halves the tile size and retries - the game and the Remix
Toolkit usually hold most of the GPU while this runs.
"""

from __future__ import annotations

import gc
from pathlib import Path

import numpy as np
import torch
from spandrel import ImageModelDescriptor, ModelLoader


class ModelRunner:
    def __init__(self, device: str | None = None, tile: int = 512, overlap: int = 32, log=print):
        self.device = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))
        self.tile = tile
        self.overlap = overlap
        self.log = log
        self._models: dict[Path, ImageModelDescriptor] = {}

    def load(self, path: Path) -> ImageModelDescriptor:
        path = Path(path)
        if path not in self._models:
            if not path.exists():
                raise FileNotFoundError(f"model weights missing: {path}")
            descriptor = ModelLoader(device=self.device).load_from_file(str(path))
            if not isinstance(descriptor, ImageModelDescriptor):
                raise TypeError(f"{path.name} is not an image-to-image model")
            descriptor.eval()
            self._models[path] = descriptor
            self.log(f"  loaded {path.name}: {descriptor.architecture.name}, x{descriptor.scale}, "
                     f"{descriptor.input_channels}->{descriptor.output_channels} ch")
        return self._models[path]

    def unload(self):
        self._models.clear()
        gc.collect()
        if self.device.type == "cuda":
            torch.cuda.empty_cache()

    @torch.inference_mode()
    def run(self, path: Path, image: np.ndarray) -> np.ndarray:
        """image: (H, W, 3) float32 in [0, 1]. Returns (H*s, W*s, C) float32."""
        model = self.load(path)
        tile = self.tile
        while True:
            try:
                return self._run_tiled(model, image, tile)
            except torch.cuda.OutOfMemoryError:
                if tile <= 128:
                    raise
                tile //= 2
                torch.cuda.empty_cache()
                self.log(f"  out of GPU memory; retrying with {tile}px tiles")

    def _forward(self, model: ImageModelDescriptor, patch: torch.Tensor) -> torch.Tensor:
        req = model.size_requirements
        _, _, h, w = patch.shape
        multiple = max(1, req.multiple_of)
        target_h = max(req.minimum, -(-h // multiple) * multiple)
        target_w = max(req.minimum, -(-w // multiple) * multiple)
        if req.square:
            target_h = target_w = max(target_h, target_w)
        padded = patch
        if (target_h, target_w) != (h, w):
            mode = "reflect" if target_h - h < h and target_w - w < w else "replicate"
            padded = torch.nn.functional.pad(patch, (0, target_w - w, 0, target_h - h), mode=mode)
        use_half = model.supports_half and self.device.type == "cuda" and not getattr(model, "_rpai_fp32", False)
        if use_half:
            out = model.model.half()(padded.half()).float()
            if not torch.isfinite(out).all():
                model._rpai_fp32 = True  # stay in fp32 for the rest of this model's tiles
                self.log("  fp16 produced non-finite values; using fp32 for this model")
                out = model.model.float()(padded.float())
        else:
            out = model.model.float()(padded.float())
        scale = model.scale
        return out[:, :, : h * scale, : w * scale]

    def _run_tiled(self, model: ImageModelDescriptor, image: np.ndarray, tile: int) -> np.ndarray:
        scale = model.scale
        h, w, _ = image.shape
        src = torch.from_numpy(np.ascontiguousarray(image.transpose(2, 0, 1))).unsqueeze(0).to(self.device)
        out = None
        weight = torch.zeros((1, h * scale, w * scale), dtype=torch.float32)
        overlap = min(self.overlap, tile // 4)
        for y0, y1 in _spans(h, tile, overlap):
            for x0, x1 in _spans(w, tile, overlap):
                result = self._forward(model, src[:, :, y0:y1, x0:x1])[0].cpu()
                if out is None:
                    out = torch.zeros((result.shape[0], h * scale, w * scale), dtype=torch.float32)
                mask = _feather(y1 - y0, x1 - x0, scale, overlap, y0 > 0, y1 < h, x0 > 0, x1 < w)
                out[:, y0 * scale : y1 * scale, x0 * scale : x1 * scale] += result * mask
                weight[:, y0 * scale : y1 * scale, x0 * scale : x1 * scale] += mask
        out /= weight.clamp_min(1e-6)
        return out.clamp_(0, 1).numpy().transpose(1, 2, 0)


def _spans(size: int, tile: int, overlap: int) -> list[tuple[int, int]]:
    if size <= tile:
        return [(0, size)]
    stride = tile - overlap
    starts = list(range(0, size - tile, stride)) + [size - tile]
    return [(s, s + tile) for s in starts]


def _feather(h: int, w: int, scale: int, overlap: int, top: bool, bottom: bool, left: bool, right: bool) -> torch.Tensor:
    """Weights that ramp linearly across the overlap on interior tile edges only."""
    ramp = max(1, overlap * scale)

    def axis(n: int, lo: bool, hi: bool) -> torch.Tensor:
        weights = torch.ones(n * scale)
        edge = torch.linspace(1.0 / ramp, 1.0, ramp)
        if lo:
            weights[:ramp] = torch.minimum(weights[:ramp], edge)
        if hi:
            weights[-ramp:] = torch.minimum(weights[-ramp:], edge.flip(0))
        return weights

    return (axis(h, top, bottom)[:, None] * axis(w, left, right)[None, :]).unsqueeze(0)
