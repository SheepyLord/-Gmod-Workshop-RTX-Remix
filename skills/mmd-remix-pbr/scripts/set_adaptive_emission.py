"""Set scene-adaptive emission in a published rpai mod without rebuilding textures.

    python set_adaptive_emission.py --mod out/pbr_robin --value 3.33333333 --dry-run
    python set_adaptive_emission.py --mod out/pbr_robin --multiplier 5.55555556

--value is the literal USD input; --multiplier scales each shader's existing fallback intensity.
Only emissive-map shaders inside mat_<HASH> materials in ASCII .usda layers are edited.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tool"))
from rpai.config import emission_multiplier
from rpai.usda import check_adaptive_intensity


# Mask literals/comments before matching braces or input declarations. Keep offsets and newlines
# intact, so an update can replace just a number, preserving BOM, comments, spacing and CRLF.
_LITERAL = re.compile(rb'\#[^\r\n]*|""".*?"""|"(?:\\.|[^"\\])*"|@@@.*?@@@|@[^@]*@', re.S)
_PRIM = re.compile(rb'\b(?:over|def(?:\s+(?:Material|Shader))?)\s+"(?P<name>[^"\r\n]+)"\s*\{')
_MAP = re.compile(rb'(?m)^(?P<indent>[ \t]*)asset[ \t]+inputs:emissive_mask_texture[ \t]*=')
_NUMBER = rb'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?'


def _scalar(name: bytes) -> re.Pattern[bytes]:
    return re.compile(rb'(?m)^(?P<indent>[ \t]*)float[ \t]+inputs:' + name
                      + rb'[ \t]*=[ \t]*(?P<value>' + _NUMBER + rb')(?=[ \t\r\n;]|$)')


_FALLBACK = _scalar(b"emissive_intensity")
_ADAPTIVE = _scalar(b"emissive_adaptive_intensity")


def _masked(data: bytes) -> bytes:
    return _LITERAL.sub(lambda m: re.sub(rb'[^\r\n]', b' ', m.group()), data)


def update_layer(data: bytes, value: float, *, multiply_fallback: bool = False) -> tuple[bytes, list[str]]:
    """Plan byte-range edits to rpai's plain mat/Shader prims; return bytes and changed materials.

    This is a text editor, not a USD stage composer: no asset resolution, inheritance or binary USD.
    Unexpected duplicate/non-float adaptive inputs and unbalanced braces fail before any file write.
    """
    value = emission_multiplier(value) if multiply_fallback else check_adaptive_intensity(value)
    code = _masked(data)
    closes, stack = {}, []
    for brace in re.finditer(rb'[{}]', code):
        if brace.group() == b'{':
            stack.append(brace.start())
        elif stack:
            closes[stack.pop()] = brace.start()
        else:
            raise ValueError("unbalanced USDA braces")
    if stack:
        raise ValueError("unbalanced USDA braces")

    prims = [(m.group("name"), m.end() - 1, closes[m.end() - 1]) for m in _PRIM.finditer(data)
             if code[m.start():m.start() + 3] in (b'ove', b'def')]
    materials = [(name, start, end) for name, start, end in prims
                 if re.fullmatch(rb'mat_[0-9A-Fa-f]{16}', name)]
    edits, changed = [], []
    for name, start, end in prims:
        if name != b'Shader':
            continue
        parent = next((n for n, s, e in reversed(materials) if s < start < end < e), None)
        if parent is None:
            continue
        body = code[start + 1:end]
        emissive_map = _MAP.search(body)
        if not emissive_map:
            continue
        # A declaration with no actual asset (e.g. a blocked input) is not an emissive map.
        asset_start = start + 1 + emissive_map.end()
        asset = re.match(rb'[ \t]*@([^@\r\n]+)@', data[asset_start:end])
        if not asset or not asset.group(1).strip():
            continue
        fallback = list(_FALLBACK.finditer(body))
        target = value
        if multiply_fallback:
            if len(fallback) != 1:
                raise ValueError(f"{parent.decode()}: --multiplier needs one float emissive_intensity")
            target = check_adaptive_intensity(emission_multiplier(float(fallback[0].group("value"))) * value)
        encoded = f"{target:.9g}".encode("ascii")
        existing = list(_ADAPTIVE.finditer(body))
        declarations = list(re.finditer(rb'\binputs:emissive_adaptive_intensity\b', body))
        if len(declarations) != len(existing) or len(existing) > 1:
            raise ValueError(f"{parent.decode()}: expected at most one float emissive_adaptive_intensity")
        if existing:
            old = existing[0]
            # Compare the serialised float too: 9 significant digits intentionally round doubles.
            if float(old.group("value")) == float(encoded):
                continue
            edits.append((start + 1 + old.start("value"), start + 1 + old.end("value"), encoded))
        else:
            # Insert next to the unchanged fallback. If it is implicit, add before the shader close.
            anchor = fallback[0] if len(fallback) == 1 else None
            if anchor:
                position = data.find(b'\n', start + 1 + anchor.end()) + 1
                if not start < position <= end:
                    raise ValueError(f"{parent.decode()}: fallback must be on its own line")
                indent = anchor.group("indent")
            else:
                position = data.rfind(b'\n', 0, end) + 1
                if data[position:end].strip():
                    raise ValueError(f"{parent.decode()}: shader close must be on its own line")
                indent = emissive_map.group("indent")
            newline = b'\r\n' if data[position - 2:position] == b'\r\n' else b'\n'
            line = indent + b'float inputs:emissive_adaptive_intensity = ' + encoded + newline
            edits.append((position, position, line))
        material = parent.decode("ascii")
        if material not in changed:
            changed.append(material)
    for start, end, replacement in sorted(edits, reverse=True):
        data = data[:start] + replacement + data[end:]
    return data, changed


def _replace(path: Path, data: bytes) -> None:
    """Atomic replacement; the temporary file stays beside the layer and is always cleaned up."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + '.adaptive-',
                                         suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mod", type=Path, required=True, help="an existing published rpai mod folder")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--value", type=check_value, help="literal USD intensity, 0..65504 (0 disables adaptation)")
    mode.add_argument("--multiplier", type=emission_multiplier,
                      help="multiply each existing emissive_intensity; use 5.55555556 for exposure 1")
    parser.add_argument("--dry-run", action="store_true", help="report planned edits; write and touch nothing")
    args = parser.parse_args(argv)
    try:
        mod = args.mod.resolve(strict=True)
        if not mod.is_dir():
            raise ValueError(f"not a mod folder: {mod}")
        pending = []
        for layer in sorted(mod.rglob("*.usda")):
            if not layer.resolve().is_relative_to(mod):
                raise ValueError(f"layer resolves outside the mod: {layer}")
            data, materials = update_layer(layer.read_bytes(),
                                           args.value if args.value is not None else args.multiplier,
                                           multiply_fallback=args.multiplier is not None)
            if materials:
                pending.append((layer, data, materials))
        # Validate every layer first, including during dry runs, before making any change.
        for layer, data, materials in pending:
            print(f"{layer.relative_to(mod).as_posix()}: {', '.join(materials)}")
            if not args.dry_run:
                _replace(layer, data)
        if pending and not args.dry_run and (mod / "mod.usda").is_file():
            (mod / "mod.usda").touch()  # Remix watches the root timestamp, not the model layers.
        count = sum(len(materials) for _, _, materials in pending)
        print(f"{'would change' if args.dry_run else 'changed'} {count} material(s) in {len(pending)} layer(s)")
        return 0
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


def check_value(value: str) -> float:
    return check_adaptive_intensity(float(value))


if __name__ == "__main__":
    raise SystemExit(main())
