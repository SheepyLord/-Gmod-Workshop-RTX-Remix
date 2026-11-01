"""Write the Remix replacement mod.

Layout under ``rtx-remix/mods/<mod>/``::

    mod.usda                 root layer; one sublayer per model
    models/<model>.usda      ``over "mat_<HASH>"`` shader inputs
    textures/<model>/*.dds   content-named, never overwritten in place

The runtime watches only the root file's modification time
(``UsdMod::Impl::haveFilesChanged``), so every publish rewrites ``mod.usda``
atomically, which triggers its async reload. A brand-new mod folder is only
discovered by the Remix menu's "Rescan Mods & Reload USD Stage" or a restart.
"""

from __future__ import annotations

import math
import os
from pathlib import Path

GAME_NAME = "Garry's Mod (x64)"

_INPUTS = {
    "albedo": ("inputs:diffuse_texture", "auto"),
    "normal": ("inputs:normalmap_texture", "raw"),
    "roughness": ("inputs:reflectionroughness_texture", "raw"),
    "metallic": ("inputs:metallic_texture", "raw"),
    "height": ("inputs:height_texture", "raw"),
    "emissive": ("inputs:emissive_mask_texture", "auto"),
    "anisotropy": ("inputs:anisotropy_texture", "raw"),
}


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    os.replace(tmp, path)


def check_adaptive_intensity(value: float) -> float:
    """Validate the runtime's finite 0..65504 material-input range."""
    if not math.isfinite(value) or not 0 <= value <= 65504:
        raise ValueError("emissive_adaptive_intensity must be finite and in 0..65504")
    return value


def material_block(texture_hash: str, maps: dict[str, str], displacement: float, emissive_intensity: float = 0.0,
                   subsurface: dict | None = None, emissive_adaptive_intensity: float | None = None) -> str:
    """maps: kind -> asset path relative to the model layer; subsurface: {"radius_scale", "radius"} or None."""
    name = texture_hash.upper().replace("0X", "")
    lines = [
        f'        over "mat_{name}"',
        "        {",
        '            over "Shader"',
        "            {",
        "                uniform asset info:mdl:sourceAsset = @AperturePBR_Opacity.mdl@",
        '                uniform token info:mdl:sourceAsset:subIdentifier = "AperturePBR_Opacity"',
        # Remix's own default; the Advanced Material Editor bridge found
        # replacement maps without sampler-feedback stamps load reliably with it.
        "                bool inputs:preload_textures = 1",
    ]
    for kind in ("albedo", "normal", "roughness", "metallic", "anisotropy", "height", "emissive"):
        if kind in maps:
            attr, space = _INPUTS[kind]
            lines.append(f'                asset {attr} = @{maps[kind]}@ (')
            lines.append(f'                    colorSpace = "{space}"')
            lines.append("                )")
    if "normal" in maps:
        lines.append("                int inputs:encoding = 0")  # octahedral
    if "height" in maps:
        lines.append(f"                float inputs:displace_in = {displacement:g}")
    if "emissive" in maps:
        # The texture replaces emissive_color_constant entirely, so the
        # constant is not written (this runtime rejects color3f values anyway).
        lines.append("                bool inputs:enable_emission = 1")
        lines.append(f"                float inputs:emissive_intensity = {emissive_intensity:g}")
        if emissive_adaptive_intensity is not None:
            adaptive = check_adaptive_intensity(emissive_adaptive_intensity)
            lines.append(f"                float inputs:emissive_adaptive_intensity = {adaptive:.9g}")
    if subsurface and "albedo" in maps:
        # Diffusion-profile scattering only renders on an opaque material with the skin colour as
        # transmittance (measured on Guinevere's forearm; README "Subsurface scattering").
        lines.append("                bool inputs:subsurface_diffusion_profile = 1")
        lines.append("                bool inputs:use_legacy_alpha_state = 0")
        lines.append("                bool inputs:blend_enabled = 0")
        lines.append(f'                asset inputs:subsurface_transmittance_texture = @{maps["albedo"]}@ (')
        lines.append('                    colorSpace = "auto"')
        lines.append("                )")
        lines.append(f"                float inputs:subsurface_radius_scale = {subsurface['radius_scale']:g}")
        if subsurface.get("radius"):
            # Colour inputs load since runtime c6b48ed1; 384581b1 rejected them.
            r, g, b = subsurface["radius"]
            lines.append(f"                color3f inputs:subsurface_radius = ({r:g}, {g:g}, {b:g})")
    lines += ["            }", "        }"]
    return "\n".join(lines)


def write_model_layer(path: Path, materials: list[tuple], displacement: float, comment: str) -> None:
    """materials: (texture hash, maps, fallback intensity[, subsurface[, adaptive intensity]])."""
    blocks = "\n\n".join(material_block(m[0], m[1], displacement, m[2], m[3] if len(m) > 3 else None,
                                        m[4] if len(m) > 4 else None)
                         for m in materials)
    text = (
        "#usda 1.0\n(\n"
        f'    doc = "{comment}"\n'
        '    upAxis = "Z"\n'
        ")\n\n"
        'over "RootNode"\n{\n    over "Looks"\n    {\n'
        f"{blocks}\n"
        "    }\n}\n"
    )
    atomic_write(path, text)


def write_mod_root(mod_dir: Path, exclude: set[str] | None = None) -> list[str]:
    """Rewrite mod.usda listing every model layer except the ``exclude`` stems."""
    layers = sorted(
        p.relative_to(mod_dir).as_posix()
        for p in (mod_dir / "models").glob("*.usda")
        if p.stem not in (exclude or set())
    )
    sublayers = ",\n".join(f"        @./{layer}@" for layer in layers)
    text = (
        "#usda 1.0\n(\n"
        "    customLayerData = {\n"
        f'        string lightspeed_game_name = "{GAME_NAME}"\n'
        '        string lightspeed_layer_type = "replacement"\n'
        "    }\n"
        '    doc = "Generated by Remix PBR AI (rpai). Edits are overwritten on the next publish."\n'
        "    metersPerUnit = 0.01\n"
        f"    subLayers = [\n{sublayers}\n    ]\n"
        "    timeCodesPerSecond = 24\n"
        '    upAxis = "Z"\n'
        ")\n"
    )
    atomic_write(mod_dir / "mod.usda", text)
    return layers
