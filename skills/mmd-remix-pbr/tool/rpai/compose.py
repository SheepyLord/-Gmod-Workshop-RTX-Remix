"""Turn one albedo texture into Remix-ready PBR maps.

1. Albedo: the original image from the PMX folder (never the game's VTF), AI
   upscaled when it is smaller than ``max_size``. A low-frequency colour fix
   puts the source's colours back under the AI detail, as PBRify's
   "Color Fix" chain does, so painted anime colours do not drift.
2. PBRify generates DirectX tangent-space normals, roughness and height from
   the albedo at the final size.
3. The texture-space class map scales each generated map per texel: base
   roughness and metallic come from the class, the AI roughness keeps only its
   local variation, normal strength fades to flat on faces and eyes. Classes
   with an ``emissive`` weight (iris, eye white, highlight) get an emissive
   map: the albedo's own colour times that weight. Classes with ``delight``
   (skin) have the shading painted into the albedo softened (``delight()``).
4. Normals are re-encoded as Remix's hemispherical octahedral format.

Steps 1-2 are cached in ``work/<model>/raw``, so changing class parameters
re-composes in seconds instead of re-running the upscaler (minutes per sheet).
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

from . import config
from .classify import CLASS_ID, class_params

Image.MAX_IMAGE_PIXELS = None  # 8K MMD sheets are normal


@dataclass
class Albedo:
    rgba: np.ndarray  # (H, W, 4) uint8
    replace: bool  # larger than the game's texture, so worth publishing as the albedo
    source_size: tuple[int, int]
    has_alpha: bool


def load_rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        image.load()
        return np.asarray(image.convert("RGBA"))


def _resize(array: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    mode = "RGBA" if array.shape[-1] == 4 else "RGB"
    return np.asarray(Image.fromarray(array, mode).resize(size, Image.LANCZOS))


def _color_fix(upscaled: np.ndarray, source: np.ndarray, sigma: float) -> np.ndarray:
    """Replace the upscale's low frequencies with the (resized) source's."""
    reference = np.asarray(Image.fromarray(source).resize(upscaled.shape[1::-1], Image.BICUBIC), np.float32) / 255
    out = np.empty_like(upscaled)
    for c in range(3):
        detail = upscaled[..., c] - ndimage.gaussian_filter(upscaled[..., c], sigma)
        out[..., c] = ndimage.gaussian_filter(reference[..., c], sigma) + detail
    return np.clip(out, 0, 1)


def pick_upscaler(name: str, long_side: int) -> Path:
    if name == "auto":
        # DAT is the better model but ~40x slower than SPAN; above 1024 px the
        # remaining scale is at most 4x of an already detailed sheet.
        name = "v4" if long_side <= 1024 else "span"
    return config.UPSCALERS[name]


def _needs_upscale(long_side: int, settings: config.Settings) -> bool:
    # Only worth it for at least 2x; a 3000 px sheet gains little at 4096.
    return long_side * 2 <= settings.max_size


def output_size(source_size: tuple[int, int], settings: config.Settings) -> tuple[int, int]:
    """(width, height) of the albedo and every generated map for a source of this size."""
    w, h = source_size
    long_side = max(w, h)
    if _needs_upscale(long_side, settings):
        factor = min(4.0, settings.max_size / long_side)
        return round(w * factor), round(h * factor)
    if long_side > settings.max_size:
        scale = settings.max_size / long_side
        return round(w * scale), round(h * scale)
    return w, h


def prepare_albedo(source: Path, game_size: tuple[int, int], settings: config.Settings, runner, log=print) -> Albedo:
    rgba = load_rgba(source)
    h, w = rgba.shape[:2]
    has_alpha = bool((rgba[..., 3] < 255).any())
    long_side = max(w, h)
    if _needs_upscale(long_side, settings):
        target = output_size((w, h), settings)
        model = pick_upscaler(settings.upscaler, long_side)
        log(f"  upscaling {w}x{h} -> {target[0]}x{target[1]} with {model.name}")
        rgb = rgba[..., :3].astype(np.float32) / 255
        up8 = (runner.run(model, rgb) * 255 + 0.5).astype(np.uint8)
        if up8.shape[1::-1] != target:
            up8 = _resize(up8, target)
        fixed = _color_fix(up8.astype(np.float32) / 255, rgba[..., :3], sigma=max(2.0, target[0] / 512))
        up8 = (fixed * 255 + 0.5).astype(np.uint8)
        if has_alpha:
            alpha = np.repeat(rgba[..., 3:4].astype(np.float32) / 255, 3, axis=2)
            alpha_up = runner.run(model, alpha).mean(axis=2)
            a8 = (alpha_up * 255 + 0.5).astype(np.uint8)
            if a8.shape[1::-1] != target:
                a8 = np.asarray(Image.fromarray(a8, "L").resize(target, Image.LANCZOS))
        else:
            a8 = np.full(up8.shape[:2], 255, np.uint8)
        out = np.dstack([up8, a8])
        return Albedo(out, _sharper(target, game_size), (w, h), has_alpha)
    target = output_size((w, h), settings)
    if target != (w, h):
        log(f"  downscaling {w}x{h} -> {target[0]}x{target[1]}")
        rgba = _resize(rgba, target)
    # A source sharper than the game's copy (Model Hotloader may have shrunk
    # it) is still worth publishing even without an AI upscale.
    return Albedo(rgba, _sharper(target, game_size), (w, h), has_alpha)


def _sharper(size: tuple[int, int], game_size: tuple[int, int]) -> bool:
    return size[0] > game_size[0] or size[1] > game_size[1]


def octahedral(normal_dx: np.ndarray) -> np.ndarray:
    """DirectX tangent-space normals -> Remix hemispherical octahedral (RG8, B=0).

    Same maths as the Toolkit's OctahedralConverter (hemisphereDirectionToSignedOctahedral).
    """
    n = normal_dx.astype(np.float32)
    n[..., 2] = np.abs(n[..., 2])  # Remix supports outward normals only
    n /= np.maximum(np.abs(n).sum(axis=2, keepdims=True), 1e-8)
    oct_x = n[..., 0] + n[..., 1]
    oct_y = n[..., 0] - n[..., 1]
    out = np.zeros(n.shape[:2] + (3,), np.uint8)
    out[..., 0] = np.floor((oct_x * 0.5 + 0.5) * 255 + 0.5).clip(0, 255)
    out[..., 1] = np.floor((oct_y * 0.5 + 0.5) * 255 + 0.5).clip(0, 255)
    return out


def _lut(field_name: str, presets: dict) -> np.ndarray:
    lut = np.zeros(256, np.float32)
    for name, cid in CLASS_ID.items():
        lut[cid] = class_params(name, presets).get(field_name, 0.0)
    return lut


def _srgb_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0.0031308), 1 / 2.4) - 0.055)


RAW_VERSION = 1  # bump when the AI stage (models, colour fix, alpha handling) changes
GUTTER_VERSION = 1  # bump when the island padding below changes; part of every texture's signature


def gutter_fill(covered: np.ndarray | None) -> tuple[np.ndarray, np.ndarray, np.ndarray] | None:
    """The gutter band around the UV islands, and the nearest covered texel of each band texel.

    PBRify reads an island's border (paint against the empty sheet) as a relief
    step: Guinevere's stockings got a ridge tilted up to 78 degrees along the
    paint edge and 3-8 degrees just inside the island, and the legs' front and
    back halves meet there, so a crease ran down the inner and outer side of each
    leg. Padding the AI input with the island's own colour removes the step;
    padding the finished maps keeps bilinear filtering and mip levels from
    blending gutter values into the border. The band stops at 1/128 of the sheet
    (32 texels at 4096, enough for mip level 4) so a byte-identical sheet that
    another model maps differently keeps its own paint and maps further out.
    """
    if covered is None or covered.all() or not covered.any():
        return None
    reach = max(8, max(covered.shape) // 128)
    distance, (rows, cols) = ndimage.distance_transform_edt(~covered, return_indices=True)
    band = (distance > 0) & (distance <= reach)
    return band, rows[band], cols[band]


def pad_gutters(array: np.ndarray, fill: tuple[np.ndarray, np.ndarray, np.ndarray] | None) -> np.ndarray:
    """Copy the nearest island texel into every gutter band texel (any trailing channels)."""
    if fill is None:
        return array
    band, rows, cols = fill
    out = array.copy()
    out[band] = array[rows, cols]
    return out


def _coverage_tag(covered: np.ndarray | None) -> str:
    """Names the AI outputs made from a padded input, so a changed UV layout regenerates them."""
    if covered is None or covered.all() or not covered.any():
        return ""
    digest = hashlib.sha1(np.packbits(covered).tobytes() + str(covered.shape).encode()).hexdigest()[:8]
    return f"_g{GUTTER_VERSION}{digest}"


@dataclass
class RawMaps:
    """AI (or authored) maps before any class tuning, cached so re-tuning skips inference."""

    albedo: Albedo
    normal: np.ndarray  # (H, W, 3) float32, DirectX tangent space in [-1, 1]
    rough: np.ndarray  # (H, W) float32 in [0, 1]
    height: np.ndarray | None
    metallic: np.ndarray | None = None
    authored: frozenset = frozenset()  # kinds taken from the model's own texture set


# Texture sets exported from Substance/Unreal sit beside their base colour,
# e.g. Firefly's 高跟鞋_BaseColor.png with _Normal/_Roughness/_Metallic/_Height.
# An artist's map beats an AI guess, so those kinds skip generation and tuning.
BASE_SUFFIXES = ("_basecolor", "_base_color", "_albedo", "_diffuse", "_color")
COMPANIONS = {
    "normal": ("_normal", "_normalmap", "_nrm"),
    "roughness": ("_roughness", "_rough"),
    "metallic": ("_metallic", "_metalness", "_metal"),
    "height": ("_height", "_displacement", "_disp"),
}
IMAGE_EXTENSIONS = (".png", ".tga", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff")


def find_authored(source: Path) -> dict[str, Path]:
    lower = source.stem.lower()
    base = next((source.stem[: -len(s)] for s in BASE_SUFFIXES if lower.endswith(s)), None)
    if base is None:
        return {}
    found = {}
    for kind, suffixes in COMPANIONS.items():
        for suffix in suffixes:
            match = next((p for p in (source.with_name(base + suffix + ext) for ext in IMAGE_EXTENSIONS)
                          if p.exists()), None)
            if match:
                found[kind] = match
                break
    return found


def _load_gray(path: Path, size: tuple[int, int]) -> np.ndarray:
    with Image.open(path) as image:
        gray = image.convert("L")
        if gray.size != size:
            gray = gray.resize(size, Image.BILINEAR)
        return np.asarray(gray, np.float32) / 255


def _curl(n: np.ndarray) -> float:
    """Mean |curl| of the slopes of DirectX unit normals; the slopes of a height field have none."""
    z = np.maximum(n[..., 2], 0.1)
    p = ndimage.gaussian_filter(-n[..., 0] / z, 1.0)
    q = ndimage.gaussian_filter(-n[..., 1] / z, 1.0)
    curl = np.abs(np.gradient(p, axis=0) - np.gradient(q, axis=1))
    tilt = np.hypot(n[..., 0], n[..., 1])
    curl = curl[(tilt > 0.02) & (tilt < 0.9)]  # flat texels carry no evidence, near-90-degree ones are bake faults
    return float(np.minimum(curl, np.percentile(curl, 99)).mean()) if curl.size > 100 else 0.0


def authored_normal(path: Path, height: Path | None, size: tuple[int, int], log=print) -> np.ndarray:
    """Load an authored tangent-space normal map as DirectX-convention unit vectors.

    The Y convention is measured, not assumed, when a height map exists: an
    OpenGL map's green follows the height gradient down the rows, a DirectX
    map's opposes it (Firefly's heels: +0.16, OpenGL). Without one it is
    measured from integrability: the slopes of a height field have no curl, and
    green read with the wrong sign gives them plenty. Robin's ZZZ maps had 3.0x
    and 2.4x more curl read as OpenGL, so DirectX; integrating both readings
    showed raised stars for DirectX and streaked saddles for OpenGL. Below a
    1.5x margin Substance's default (OpenGL) is assumed.

    Game rips can keep the normal in red and green only (Robin's ``_N`` maps
    hold a mask in blue, mean 125/255): when blue is no z, z is rebuilt.
    """
    with Image.open(path) as image:
        rgb = image.convert("RGB")
        native = np.asarray(rgb, np.float32) / 255 * 2 - 1
        if rgb.size != size:
            rgb = rgb.resize(size, Image.BILINEAR)
        n = np.asarray(rgb, np.float32) / 255 * 2 - 1
    xy = native[..., 0] ** 2 + native[..., 1] ** 2
    rebuilt = np.sqrt(np.clip(1 - xy, 0, 1))
    if np.median(np.abs(native[..., 2] - rebuilt)) > 0.3 and (xy <= 1.05).mean() > 0.95:
        native[..., 2] = rebuilt
        n[..., 2] = np.sqrt(np.clip(1 - n[..., 0] ** 2 - n[..., 1] ** 2, 0, 1))
        log("  authored normal map: blue is not z (normal in red and green only); z rebuilt")
    valid = n[..., 2] > 0.2  # exporters often leave unused texels black
    convention, evidence = "OpenGL", "assumed"
    if height is not None and valid.any():
        slope = np.gradient(_load_gray(height, size), axis=0)
        strong = valid & (np.abs(slope) > np.percentile(np.abs(slope[valid]), 80))
        if strong.sum() > 100:
            corr = float(np.corrcoef(n[..., 1][strong], slope[strong])[0, 1])
            convention, evidence = ("OpenGL" if corr >= 0 else "DirectX"), f"height correlation {corr:+.2f}"
    elif valid.any():
        as_gl, as_dx = _curl(native * np.array([1, -1, 1], np.float32)), _curl(native)
        if min(as_gl, as_dx) > 0 and max(as_gl, as_dx) >= 1.5 * min(as_gl, as_dx):
            convention = "OpenGL" if as_gl < as_dx else "DirectX"
            evidence = f"curl {max(as_gl, as_dx) / min(as_gl, as_dx):.1f}x lower than the other reading"
    if convention == "OpenGL":
        n[..., 1] = -n[..., 1]
    n[~valid] = (0.0, 0.0, 1.0)
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)
    log(f"  authored normal map: {convention} ({evidence})")
    return n


# Bump when relief_normals (or authored_normal, which reads regular maps for it) changes; part of the
# signature of sheets that use it. 4: red/green-only maps and the measured Y convention (Robin).
RELIEF_VERSION = 4


def _relief_height(s: np.ndarray, direction: tuple[float, float], lam: float, keep: float | None) -> np.ndarray:
    """Least-energy height whose derivative along `direction` is `s` (regularised Fourier inverse)."""
    h, w = s.shape
    ky = np.fft.fftfreq(h)[:, None] * 2 * np.pi
    kx = np.fft.fftfreq(w)[None, :] * 2 * np.pi
    dx, dy = np.asarray(direction, np.float64) / np.hypot(*direction)
    kd = kx * dx + ky * dy
    k2 = kx ** 2 + ky ** 2
    spectrum = np.conj(1j * kd) * np.fft.fft2(s) / (kd ** 2 + lam * k2 + 1e-9)
    spectrum[0, 0] = 0
    if keep:
        spectrum *= 1 - np.exp(-k2 * keep ** 2 / 2)  # shapes broader than `keep` texels are the mesh's own
    return np.real(np.fft.ifft2(spectrum))


def relief_normals(path: Path, size: tuple[int, int], log=print, covered: np.ndarray | None = None) -> np.ndarray:
    """DirectX unit normals at `size` from a normal map named in the settings (``normal_map``).

    A regular map is read like an authored one (OpenGL assumed). Some MMD packs ship a map whose red
    and green channels are identical: Guinaifen's ``Body normal.png`` has R == G (correlation 1.0) on
    a lavender base, so it holds one slope channel, about (nx + ny) / 2 of the original map, the
    height's derivative along one diagonal. The diagonal is the one whose weakly regularised height
    needs the least energy, which picks the true one: on Guinaifen (std 106 vs 135) it alone made the
    navel a pit and both kneecaps equal bumps; the other directions inverted the navel or made the
    knees lopsided. The choice must be made without the high-pass below, which evens the energies
    out (23.7 vs 22.4, the wrong pick). The final height is regularised harder and drops shapes
    broader than 96 texels at 2048: the mesh carries them, and the missing perpendicular slope only
    shows there, as streaks.

    Cleaning, set from in-game shots and shaded previews at equal contrast: a 2-texel blur removes the
    8-bit steps (amplified, they read as grainy skin), and a soft knee on the slope (linear below
    0.05, compressed above) tames bake faults. The map has faceted patches at the shoulders that
    became a dark false fold in the armpit at strength 6 (p99 tilt 15.5, max 41 degrees; with the
    knee 8.5 and 12) while the clavicles, navel, ribs and toes keep their shape.

    UV borders (``covered``, texels a UV triangle touches at `size`): the map carries its own bake
    padding, whose steps are not this model's island borders (they sit a few texels outside and in
    places cross in), and integrated they drew ridges along the sides of Guinaifen's torso and legs,
    where the front and back halves meet. So the slope outside the islands is replaced by the island
    edge's own, fading into the empty sheet from 8 to 32 texels out. The two halves are also rebuilt
    separately and disagree where they meet on the mesh, so the relief fades to flat over the last
    12 texels (at 2048) inside every island and the mesh's smooth normals carry the seam.
    """
    with Image.open(path) as image:
        rgb = np.asarray(image.convert("RGB"), np.float32)
    red, green = rgb[..., 0], rgb[..., 1]
    if np.abs(red - green).mean() > 0.5:
        return authored_normal(path, None, size, log)
    scale = max(rgb.shape[:2]) / 2048
    s = red - np.median(red)
    edges = covered is not None and covered.any() and not covered.all()
    if edges:
        island = np.asarray(Image.fromarray(covered.astype(np.uint8) * 255).resize(rgb.shape[1::-1], Image.NEAREST)) > 127
        distance, (rows, cols) = ndimage.distance_transform_edt(~island, return_indices=True)
        taper = np.clip(1 - (distance - 8 * scale) / (24 * scale), 0, 1)
        s = np.where(island, s, s[rows, cols] * taper)
    s = ndimage.gaussian_filter(s, 2.0 * scale)  # 8-bit steps are not relief
    # Flattened from an OpenGL map, s follows the slope along (-1, 1); from a DirectX map, (-1, -1).
    diagonals = {"OpenGL": (-1.0, 1.0), "DirectX": (-1.0, -1.0)}
    convention = min(diagonals, key=lambda name: _relief_height(s, diagonals[name], 0.02, None).std())
    height = _relief_height(s, diagonals[convention], 0.3, 96 * scale) * np.sqrt(2) / 127.5  # map's slope units
    gy, gx = np.gradient(height)
    knee = 1 / (1 + np.hypot(gx, gy) / 0.05)
    n = np.dstack([-gx * knee, -gy * knee, np.ones_like(gx)]).astype(np.float32)  # DirectX: +y runs down
    if n.shape[1::-1] != tuple(size):
        n = np.dstack([np.asarray(Image.fromarray(n[..., c]).resize(size, Image.BILINEAR)) for c in range(3)])
    if edges:
        t = np.clip(ndimage.distance_transform_edt(covered) / (12 * max(size) / 2048), 0, 1)
        n[..., :2] *= (t * t * (3 - 2 * t))[..., None]
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)
    log(f"  normal map {path.name}: red = green (one slope channel), height recovered along the {convention} diagonal")
    return n


def raw_signature(source: Path, settings: config.Settings) -> str:
    """Identity of the AI stage's output: source file, size cap, effective upscaler, authored maps."""
    with Image.open(source) as image:
        long_side = max(image.size)
    upscaler = pick_upscaler(settings.upscaler, long_side).name if _needs_upscale(long_side, settings) else "none"
    stat = source.stat()
    authored = [(kind, str(p), p.stat().st_size, int(p.stat().st_mtime)) for kind, p in sorted(find_authored(source).items())]
    payload = [RAW_VERSION, str(source), stat.st_size, int(stat.st_mtime), settings.max_size, upscaler]
    if authored:
        payload.append(authored)  # absent for ordinary textures, so their cache keys are unchanged
    return hashlib.sha1(json.dumps(payload).encode()).hexdigest()[:12]


def _to8(array: np.ndarray) -> np.ndarray:
    return (np.clip(array, 0, 1) * 255 + 0.5).astype(np.uint8)


def load_or_make_raw(source: Path, game_size: tuple[int, int], settings: config.Settings, runner,
                     folder: Path, key: str, log=print, covered: np.ndarray | None = None,
                     normal_map: Path | None = None) -> RawMaps:
    """Run the AI models, or reuse their cached 8-bit outputs.

    Fresh results are quantised exactly as the cache stores them before use,
    so a cached run composes byte-identical maps (and DDS names) to a fresh one.
    ``covered`` (texels a UV triangle touches, at the output size) pads the
    gutters of the normal, roughness and height models' input; see gutter_fill.
    ``normal_map`` (a per-texture setting) replaces the AI normals with the model's own
    relief (relief_normals); the class normal strength still scales it.
    """
    folder.mkdir(parents=True, exist_ok=True)
    signature = raw_signature(source, settings)
    ai = signature + _coverage_tag(covered)  # the upscaled albedo does not depend on the UV layout
    path = {"albedo": folder / f"{key}_{signature}_albedo.png"}
    path.update({kind: folder / f"{key}_{ai}_{kind}.png" for kind in ("normal", "rough", "height")})
    current = {p.name for p in path.values()}
    for stale in folder.glob(f"{key}_*.png"):
        if stale.name not in current:
            stale.unlink(missing_ok=True)

    with Image.open(source) as image:
        long_side = max(image.size)
    resized = _needs_upscale(long_side, settings) or long_side > settings.max_size
    if path["albedo"].exists() or not resized:
        # Only a resized albedo is cached; an unchanged one is the source itself.
        rgba = load_rgba(path["albedo"] if resized else source)
        size = rgba.shape[1::-1]
        albedo = Albedo(rgba, _sharper(size, game_size), size, bool((rgba[..., 3] < 255).any()))
    else:
        albedo = prepare_albedo(source, game_size, settings, runner, log)
        Image.fromarray(albedo.rgba, "RGBA").save(path["albedo"], compress_level=1)

    authored = find_authored(source)
    size = albedo.rgba.shape[1::-1]
    if covered is not None and covered.shape != albedo.rgba.shape[:2]:
        raise ValueError(f"UV coverage {covered.shape[::-1]} does not match the albedo {size}")
    padded = None

    def ai_input() -> np.ndarray:
        nonlocal padded
        if padded is None:
            padded = pad_gutters(albedo.rgba[..., :3], gutter_fill(covered)).astype(np.float32) / 255
        return padded

    if authored:
        log(f"  authored maps found: {', '.join(sorted(authored))}")
    if "normal" in authored and "roughness" in authored:
        normal8 = rough8 = None
    elif path["normal"].exists() and path["rough"].exists():
        normal8 = np.asarray(Image.open(path["normal"]).convert("RGB"))
        rough8 = np.asarray(Image.open(path["rough"]).convert("L"))
        log("  reusing cached AI outputs")
    else:
        rgb = ai_input()
        log("  generating normal and roughness")
        normal8 = _to8(runner.run(config.NORMAL_MODEL, rgb))
        rough8 = _to8(runner.run(config.ROUGHNESS_MODEL, rgb).mean(axis=2))
        Image.fromarray(normal8, "RGB").save(path["normal"], compress_level=1)
        Image.fromarray(rough8, "L").save(path["rough"], compress_level=1)
    if "normal" in authored:
        normal = authored_normal(authored["normal"], authored.get("height"), size, log)
    elif normal_map is not None:
        normal = relief_normals(normal_map, size, log, covered)
    else:
        normal = normal8.astype(np.float32) / 255 * 2 - 1
    rough = _load_gray(authored["roughness"], size) if "roughness" in authored else rough8.astype(np.float32) / 255
    metallic = _load_gray(authored["metallic"], size) if "metallic" in authored else None
    height = None
    if settings.height:
        if "height" in authored:
            height = _load_gray(authored["height"], size)
        else:
            if path["height"].exists():
                height8 = np.asarray(Image.open(path["height"]).convert("L"))
            else:
                log("  generating height")
                height8 = _to8(runner.run(config.HEIGHT_MODEL, ai_input()).mean(axis=2))
                Image.fromarray(height8, "L").save(path["height"], compress_level=1)
            height = height8.astype(np.float32) / 255
    return RawMaps(albedo, normal, rough, height, metallic, frozenset(authored))


def delight(rgba: np.ndarray, amount: np.ndarray, covered: np.ndarray | None = None) -> np.ndarray:
    """Soften the broad shading painted into anime skin by ``amount`` (0-1 per texel).

    Toon skin sheets paint pink creases, joint blush and soft shadows for a
    shader that has none of its own; path tracing shades the same places again,
    and Guinevere's knees read as red rashes. Only the low frequencies of the
    paint's departure from the base skin colour are reduced, so outlines, nails
    and fine paint survive, and colours far from the base (lips, nipples,
    genitals: 0.9+ in linear RGB against 0.4-0.6 for painted shading) keep
    their paint. The base colour and the blur use covered texels of the
    affected classes only, so gutters and other materials do not leak in.
    """
    h, w = amount.shape
    lin = _srgb_to_linear(rgba[..., :3].astype(np.float32) / 255)
    mask = amount > 0
    if covered is not None and (mask & covered).any():
        mask &= covered
    opaque = rgba[..., 3] >= 250
    # Overlay and decal sheets (tattoos, blush) are design, not shading. Body
    # sheets may still have a few translucent texels (Guinevere's: 0.7%).
    if not mask.any() or (mask & ~opaque).sum() > 0.05 * mask.sum():
        return rgba
    mask &= opaque
    base = np.median(lin[mask][:: max(1, int(mask.sum()) // 200_000)], axis=0)
    dev = lin - base
    # Judged per texel: on Hyacine's and Firefly's sheets nipples and genitals
    # are painted inline and narrower than the blur, so a blurred test let half
    # of their colour go. Such texels are also left out of the shading estimate,
    # or their colour would lift a pale halo around them.
    t = np.clip((np.linalg.norm(dev, axis=2) - 0.45) / 0.25, 0, 1)
    shading = mask * (1 - t * t * (3 - 2 * t))
    sigma = max(h, w) / 256  # 16 texels at 4096: wider than outlines, narrower than painted shading
    support = np.maximum(ndimage.gaussian_filter(shading, sigma), 1e-3)
    low = np.stack([ndimage.gaussian_filter(dev[..., c] * shading, sigma) / support for c in range(3)], -1)
    rgb = _linear_to_srgb(np.clip(lin - (amount * shading)[..., None] * low, 0, 1))
    return np.dstack([(rgb * 255 + 0.5).astype(np.uint8), rgba[..., 3]])


def lift_reflectance(rgba: np.ndarray, ids: np.ndarray, target: np.ndarray, covered: np.ndarray | None = None) -> np.ndarray:
    """Scale each class with an ``f0`` target so its median linear luminance on the mesh meets it.

    A metal's albedo is its reflectance. Anime sheets paint gold as a mid-tone (Robin's champagne
    gold: median linear luminance 0.28-0.38, Guinevere's yellow gold 0.31) where polished gold
    reflects about 0.74, so path-traced gold came out as dull bronze. One factor per class and
    sheet (at most 3x) keeps the painted hue, outlines and shading; channels clip at 1.
    """
    out = rgba.copy()
    lin = _srgb_to_linear(rgba[..., :3].astype(np.float32) / 255)
    luminance = lin @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    for cid in np.nonzero(target > 0)[0]:
        sel = ids == cid
        ref = sel & covered if covered is not None and (sel & covered).any() else sel
        if not ref.any():
            continue
        factor = float(np.clip(target[cid] / max(float(np.median(luminance[ref])), 1e-4), 1.0, 3.0))
        out[..., :3][sel] = (_linear_to_srgb(np.clip(lin[sel] * factor, 0, 1)) * 255 + 0.5).astype(np.uint8)
    return out


def compose_maps(raw: RawMaps, ids: np.ndarray, settings: config.Settings,
                 covered: np.ndarray | None = None) -> tuple[dict[str, np.ndarray], float]:
    """Apply the texture-space class parameters to the raw AI maps.

    Returns the maps and the emissive scale (0 without emission): the emissive
    map holds albedo x class weight / scale, and the scale becomes the
    material's emissive_intensity, so its 8 bits carry colour rather than level.
    ``covered`` (texels a UV triangle touches) keeps the gutters out of the class
    roughness means, and the gutter band of every map repeats the island edges
    (gutter_fill) instead of the sheet's unused paint.
    """
    h, w = ids.shape
    sigma = max(1.0, max(h, w) / 2048)
    fill = gutter_fill(covered)

    def param(name: str) -> np.ndarray:
        return ndimage.gaussian_filter(_lut(name, settings.presets)[ids], sigma)

    normal = raw.normal.copy()
    if "normal" not in raw.authored:  # authored relief is used as made
        strength = param("normal")
        normal[..., 0] *= strength
        normal[..., 1] *= strength
        normal[..., 2] = np.maximum(normal[..., 2], 1e-3)
        normal /= np.linalg.norm(normal, axis=2, keepdims=True)

    if "roughness" in raw.authored:
        rough = np.clip(raw.rough, 0.02, 1.0)
    else:
        # Keep the AI map's variation around each class's own mean; the class
        # decides the overall level (the AI cannot know cloth from metal paint).
        # The mean is taken where the class is on the mesh: the empty sheet
        # around Guinevere's stockings (76% of it) had pulled theirs from 0.43
        # to 0.28, so the nylon rendered at 0.42 where the class said 0.30.
        on_mesh = covered if covered is not None and covered.any() else np.ones(ids.shape, bool)
        counts = np.bincount(ids[on_mesh], minlength=256).astype(np.float64)
        sums = np.bincount(ids[on_mesh], weights=raw.rough[on_mesh], minlength=256)
        class_mean = np.where(counts > 0, sums / np.maximum(counts, 1), 0.5).astype(np.float32)
        rough = np.clip(param("rough") + param("rough_ai") * (raw.rough - class_mean[ids]), 0.02, 1.0)

    metal = raw.metallic if raw.metallic is not None else np.clip(param("metal"), 0, 1)

    maps = {"normal": octahedral(pad_gutters(normal, fill)), "roughness": _to8(pad_gutters(rough, fill))}
    if metal.max() > 0.02:
        maps["metallic"] = _to8(pad_gutters(metal, fill))
    # Remix anisotropy (-1..1, stored as 0..1) stretches the specular lobe along
    # one texture axis; only sheets with an "aniso" class get the map.
    aniso = param("aniso")
    if np.abs(aniso).max() > 0.01:
        maps["anisotropy"] = _to8(pad_gutters((aniso + 1) / 2, fill))
    if raw.height is not None:
        # 1.0 is the surface in Remix's displacement; faded classes stay flat.
        maps["height"] = _to8(pad_gutters(1.0 - param("height") * (1.0 - raw.height), fill))

    albedo = raw.albedo.rgba
    amount = _lut("delight", settings.presets)[ids]
    if amount.max() > 0:
        albedo = delight(albedo, amount, covered)
    f0 = _lut("f0", settings.presets)
    if f0.max() > 0:
        albedo = lift_reflectance(albedo, ids, f0, covered)
    if raw.albedo.replace or albedo is not raw.albedo.rgba:
        maps["albedo"] = albedo

    # Emission is not blurred like the other parameters: a soft class border
    # would put a faint glow on the skin around the eye parts.
    weight = _lut("emissive", settings.presets)[ids]
    scale = float(weight.max())
    if scale > 0:
        rgb = albedo[..., :3]
        if covered is not None and covered.any() and not covered.all():
            # Gutter texels repeat the nearest covered texel. Guinevere's iris
            # island sits in skin-coloured paint, which mip levels would
            # otherwise spread as a pale glowing rim around the dark limbal ring.
            nearest = ndimage.distance_transform_edt(~covered, return_distances=False, return_indices=True)
            rgb, weight = rgb[nearest[0], nearest[1]], weight[nearest[0], nearest[1]]
        linear = _srgb_to_linear(rgb.astype(np.float32) / 255)
        maps["emissive"] = _to8(_linear_to_srgb(linear * (weight / scale)[..., None]))
    return maps, scale


def save_maps(maps: dict[str, np.ndarray], folder: Path, key: str) -> dict[str, Path]:
    folder.mkdir(parents=True, exist_ok=True)
    paths = {}
    for kind, array in maps.items():
        path = folder / f"{key}_{kind}.png"
        mode = {2: "L", 3: "RGB", 4: "RGBA"}[array.ndim if array.ndim == 2 else array.shape[2]]
        Image.fromarray(array, mode).save(path, compress_level=1)
        paths[kind] = path
    return paths
