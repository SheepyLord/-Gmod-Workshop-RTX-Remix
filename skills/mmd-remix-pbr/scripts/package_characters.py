"""Package published rpai characters into a folder for reuse.

    python package_characters.py --dest "H:\\path\\to\\package" ^
        --character guinevere=new_mmd_model_9cdc990f="E:\\...\\桂乃芬.pmx" ^
        --character hyacine=hyacine_r18_6ca2dcc3

Layout:
    remix_mod/<mod>/       drop-in Remix mod: mod.usda (only the packaged layers), models/*.usda and
                           exactly the DDS files those layers reference
    characters/<name>/     maps/ (final PNGs), raw/ (AI cache), masks/, classes/hashes/generated.json,
                           preview.jpg, compare_*.jpg, preset.json (per-model settings, when present)
    tool/                  a copy of rpai (skip with --no-tool)
    package.json, README.md

The destination must be empty or new, unless --update is given. Every referenced DDS is checked
against the live mod after copying.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tool"
sys.path.insert(0, str(TOOL))
RPAI_HOME = Path.home() / ".rpai"


def copy(src: Path, dst: Path) -> int:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return src.stat().st_size


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dest", required=True)
    p.add_argument("--character", action="append", required=True, help="NAME=MODEL_KEY[=PMX path]")
    p.add_argument("--mod", default="ai_pbr")
    p.add_argument("--game-root", help="default: the game root rpai stored in ~/.rpai/config.json")
    p.add_argument("--no-raw", action="store_true", help="leave out the AI cache (saves ~300 MB per character)")
    p.add_argument("--no-tool", action="store_true")
    p.add_argument("--update", action="store_true", help="allow writing into a non-empty destination")
    args = p.parse_args()

    from rpai import usda

    dest = Path(args.dest)
    if dest.exists() and any(dest.iterdir()) and not args.update:
        raise SystemExit(f"{dest} is not empty; pass --update to write into it")
    game_root = Path(args.game_root or json.loads((RPAI_HOME / "config.json").read_text(encoding="utf-8"))["game_root"])
    live = game_root / "rtx-remix" / "mods" / args.mod
    pkg_mod = dest / "remix_mod" / args.mod
    characters = []
    for spec in args.character:
        parts = spec.split("=", 2)
        if len(parts) < 2:
            raise SystemExit(f"--character {spec!r}: expected NAME=MODEL_KEY[=PMX]")
        characters.append((parts[0], parts[1], parts[2] if len(parts) > 2 else ""))

    total, summary = 0, {}
    for name, key, pmx in characters:
        layer = live / "models" / f"{key}.usda"
        work = RPAI_HOME / "work" / key
        if not layer.exists() or not (work / "generated.json").exists():
            raise SystemExit(f"{name}: {layer} or {work / 'generated.json'} is missing; publish the model first")
        text = layer.read_text(encoding="utf-8")
        total += copy(layer, pkg_mod / "models" / layer.name)
        refs = sorted(set(re.findall(r"@\.\./(textures/[^@]+)@", text)))
        size = sum(copy(live / rel, pkg_mod / rel) for rel in refs)
        total += size
        out = dest / "characters" / name
        generated = json.loads((work / "generated.json").read_text(encoding="utf-8"))
        for info in generated.values():
            for path in info["maps"].values():
                total += copy(Path(path), out / "maps" / Path(path).name)
        for sub in ("masks",) + (() if args.no_raw else ("raw",)):
            for f in sorted((work / sub).glob("*")):
                if f.is_file():
                    total += copy(f, out / sub / f.name)
        for f in ["classes.json", "hashes.json", "generated.json", "preview.jpg", *sorted(x.name for x in work.glob("compare_*.jpg"))]:
            if (work / f).exists():
                total += copy(work / f, out / f)
        preset = TOOL / "presets" / "models" / f"{key}.json"
        if preset.exists():
            total += copy(preset, out / "preset.json")
        hashes = json.loads((work / "hashes.json").read_text(encoding="utf-8")).get("textures", {})
        summary[name] = {"model_key": key, "pmx": pmx, "overrides": text.count('over "mat_'),
                         "textures_published": len(generated), "dds_files": len(refs), "dds_mb": round(size / 2**20),
                         "predicted_only": sorted(Path(e["source"]).name for e in hashes.values()
                                                  if e.get("source") and not e.get("verified"))}
    usda.write_mod_root(pkg_mod)  # lists exactly the packaged layers

    if not args.no_tool:
        for f in TOOL.rglob("*"):
            if f.is_file() and "__pycache__" not in f.parts:
                total += copy(f, dest / "tool" / f.relative_to(TOOL))

    # verify against the live mod
    problems = []
    for name, key, _ in characters:
        for rel in re.findall(r"@\.\./(textures/[^@]+)@", (pkg_mod / "models" / f"{key}.usda").read_text(encoding="utf-8")):
            if not (pkg_mod / rel).exists() or (pkg_mod / rel).stat().st_size != (live / rel).stat().st_size:
                problems.append(rel)
    (dest / "package.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1), encoding="utf-8")

    rows = "\n".join(f"| {n} | {s['model_key']} | {s['pmx'] or '-'} | {s['overrides']} | {s['textures_published']} | {s['dds_mb']} MB |"
                     for n, s in summary.items())
    readme = dest / "README.md"
    if not readme.exists():  # with --update, a README already written by hand stays
        readme.write_text(f"""# RTX Remix PBR package

Made with rpai (Remix PBR AI) for Garry's Mod RTX and Model Hotloader imports.

| Character | Model key | PMX | Overrides | Textures | DDS |
| --- | --- | --- | --- | --- | --- |
{rows}

## Install

1. Copy `remix_mod/{args.mod}` to `<Garry's Mod RTX>/rtx-remix/mods/{args.mod}`.
2. A new mod folder is only discovered at startup: Alt+X → Enhancements → Loaded USD Files →
   "Rescan Mods & Reload USD Stage", or restart the game.

Overrides are keyed by Remix texture hashes of the current Model Hotloader imports. If a model is
re-imported with changed textures, re-run `rpai run "<pmx>"` (the tool is in `tool/`). Copying
`characters/<name>/raw` to `%USERPROFILE%\\.rpai\\work\\<model key>\\raw` skips the AI step when the source
images are unchanged.

## Contents

- `remix_mod/`: the drop-in mod. `characters/<name>/`: final maps, AI cache, class masks, settings.
- `tool/`: rpai and its README (method, class standards, runtime notes).
""", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    print(f"copied {total / 2**30:.2f} GiB to {dest}")
    print("verification:", "all referenced DDS present and identical in size" if not problems else f"PROBLEMS: {problems}")


if __name__ == "__main__":
    main()
