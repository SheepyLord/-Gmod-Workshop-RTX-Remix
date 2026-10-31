"""Command line for Remix PBR AI.

    python -m rpai run "E:\\path\\model.pmx"      hashes -> generate -> publish
    python -m rpai hashes|generate|publish|remove "model.pmx"
    python -m rpai status | doctor
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

from . import __version__, config
from .classify import CLASS_ID, class_params, classify
from .hotloader import HotloaderAsset, load_asset
from .pmx import PmxModel, read_pmx
from .sourcemodel import load_compiled, remember, remembered


def log(message: str = "") -> None:
    print(message, flush=True)


def normalize_hash(value: str) -> str:
    return f"0x{int(str(value), 16):016X}"


# ---------------------------------------------------------------- context

class Context:
    def __init__(self, args):
        self.args = args
        self.pmx_path = Path(args.pmx).resolve()
        self.game_root, self.bridge = locate_game(getattr(args, "game_root", None))
        self.model: PmxModel = read_pmx(self.pmx_path)
        # A character installed as a compiled addon is named once with --mdl; later commands reuse it.
        mdl = getattr(args, "mdl", None)
        if mdl:
            remember(self.pmx_path, mdl)
        else:
            mdl = remembered(self.pmx_path)
        if mdl:
            self.asset: HotloaderAsset = load_compiled(self.game_root, self.pmx_path, self.model, mdl, log)
        else:
            # --asset binds this PMX to one Model Hotloader import: Guinaifen's source folder was
            # deleted, and Guinevere's byte-identical PMX now rebuilds her layer (2026-10-26).
            self.asset = load_asset(self.game_root, self.pmx_path, resolve_asset(self.game_root, args.asset)
                                    if getattr(args, "asset", None) else None)
        self.key = config.model_key(self.asset.asset_id, self.model.name_en or self.model.name)
        self.work = config.WORK / self.key
        self.work.mkdir(parents=True, exist_ok=True)
        # Order: --settings files, then this model's own presets file, then flags.
        self.settings = config.Settings.load([Path(p) for p in (getattr(args, "settings", None) or [])])
        own = config.model_presets(self.key)
        if own.exists():
            self.settings.merge_file(own)
        for name in ("mod_name", "max_size", "upscaler", "height", "displacement", "emissive_intensity", "tile"):
            value = getattr(args, name, None)
            if value is not None:
                setattr(self.settings, name, value)
        log(f"model   {self.model.name} ({len(self.model.materials)} materials, "
            f"{len(self.asset.textures)} textures)  key={self.key}"
            f"{f'  compiled {self.asset.mdl}' if self.asset.mdl else ''}")
        if own.exists():
            log(f"presets {own}")
        log(f"game    {self.game_root}  {'(running)' if self.bridge else '(not running)'}")

    def mod_dir(self) -> Path:
        return self.game_root / "rtx-remix" / "mods" / self.settings.mod_name

    def read(self, name: str) -> dict:
        path = self.work / name
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}

    def write(self, name: str, data: dict) -> None:
        (self.work / name).write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


def resolve_asset(game_root: Path, prefix: str) -> str:
    assets = game_root / "garrysmod" / "data" / "mmd_hotloader" / "assets"
    found = [p.name for p in assets.glob(f"{prefix}*") if (p / "manifest.json").exists()]
    if len(found) != 1:
        raise SystemExit(f"--asset {prefix} matches {len(found)} Model Hotloader imports")
    return found[0]


def locate_game(game_root: str | None):
    from .gamebridge import GameBridge, find_game_windows

    saved = config.HOME / "config.json"
    stored = json.loads(saved.read_text(encoding="utf-8")) if saved.exists() else {}
    if find_game_windows():
        try:
            bridge = GameBridge(Path(game_root) if game_root else None)
            stored["game_root"] = str(bridge.game_root)
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_text(json.dumps(stored, indent=1), encoding="utf-8")
            return bridge.game_root, bridge
        except RuntimeError:
            pass
    root = game_root or stored.get("game_root")
    if not root:
        raise SystemExit("Garry's Mod is not running and no --game-root was given.")
    return Path(root), None


# ---------------------------------------------------------------- hashes

def cmd_hashes(ctx: Context) -> dict:
    from .remixhash import predict, read_obsolete_hash_option

    asset = ctx.asset
    live: dict[str, set[str]] = {}
    spawned = None
    if ctx.bridge and not ctx.args.no_live:
        from .gamebridge import query_remix_hashes

        materials = [asset.vmts[i] for i in sorted(asset.vmts)]
        try:
            result = query_remix_hashes(ctx.bridge, materials, [t.vtf for t in asset.textures.values()],
                                        [asset.mdl] if asset.mdl else [])
        except (RuntimeError, TimeoutError) as error:  # loading, hung, or in a menu
            log(f"warning: the game did not answer ({error}); using hashes from earlier runs and predictions")
            result = {"ok": True}
        if not result.get("ok"):
            log(f"warning: in-game query failed: {result.get('error')}")
        elif not result.get("remix"):
            log("warning: RemixMaterial is unavailable in game; is this the RTX Remix client?")
        for entry in result.get("materials", []):
            live.setdefault(entry["base"].lower(), set()).update(entry["hashes"])
        for entry in result.get("tracked", []):
            live.setdefault(entry["base"].lower(), set()).add(entry["hash"])
        spawned = any((e.get("model") == asset.mdl) if asset.mdl else (e.get("asset") == asset.asset_id)
                      for e in result.get("entities", []))
        if not spawned:
            log("note: this model is not spawned in the current map; only predicted hashes are available")

    obsolete = read_obsolete_hash_option(ctx.game_root)
    # A hash the game reported once stays valid while the texture (its key is
    # content-addressed) and the hash rule are unchanged. Without this, a run
    # with --no-live, or with parts hidden in game, replaced verified hashes
    # with predictions; on Guinevere 3 of 16 predictions miss and those
    # overrides silently stopped applying (2026-10-25).
    earlier = ctx.read("hashes.json")
    remembered = earlier.get("textures", {}) if earlier.get("obsolete_hash") == obsolete else {}
    table = {}
    agree = checked = 0
    for key, texture, blob in asset.iter_vtf_data():
        predicted = predict(blob, obsolete)
        got = sorted({normalize_hash(h) for h in live.get(texture.vtf.lower(), set())})
        if got:
            checked += 1
            agree += bool(set(got) & set(predicted))
        previous = remembered.get(key, {})
        earlier_live = previous.get("live", []) if previous.get("verified") and previous.get("vtf") == texture.vtf else []
        kept = not got and bool(earlier_live)
        # The same texture can upload differently between game sessions:
        # after a restart, Guinevere's 灰.jpg and sita.png reported new
        # hashes. Every hash the game ever reported stays overridden.
        got = sorted(set(got) | set(earlier_live))
        table[key] = {
            "vtf": texture.vtf,
            "source": str(texture.source) if texture.source else None,
            "game_size": [texture.width, texture.height],
            "materials": texture.materials,
            "live": got,
            "predicted": predicted,
            "use": got or predicted,
            "verified": bool(got),
        }
        if kept:
            table[key]["earlier"] = True  # reported by the game in an earlier run
    ctx.write("hashes.json", {"asset": asset.asset_id, "spawned": spawned, "obsolete_hash": obsolete, "textures": table})

    log(f"\n{'texture':<20} {'size':>9}  {'hash(es)':<40} source")
    for key, entry in table.items():
        name = Path(entry["source"]).name if entry["source"] else "?"
        tag = ("live (earlier run)" if entry.get("earlier") else "live") if entry["verified"] else "predicted"
        log(f"{name[:20]:<20} {entry['game_size'][0]:>4}x{entry['game_size'][1]:<4}  "
            f"{', '.join(entry['use'])[:40]:<40} {tag}")
    if checked:
        log(f"\noffline prediction agreed with the game on {agree}/{checked} textures with live hashes")
    unverified = [Path(e["source"]).name for e in table.values() if not e["verified"] and e["source"]]
    if unverified and ctx.bridge:
        log("not drawn in game yet (predicted hashes used): " + ", ".join(unverified))
        log("  show those parts in game (morphs/bodygroups) and re-run 'hashes' to confirm them")
    return table


# ---------------------------------------------------------------- generate

def material_classes(ctx: Context) -> dict[int, tuple[str, str]]:
    model = ctx.model
    out = {}
    for material in model.materials:
        sphere = model.textures[material.sphere] if 0 <= material.sphere < len(model.textures) else ""
        texture = model.textures[material.texture] if 0 <= material.texture < len(model.textures) else ""
        texture_stem = Path(texture.replace("\\", "/")).stem if texture else ""
        out[material.index] = classify(material.name, material.name_en, sphere, texture_stem)
    # {"presets": {"_materials": {"11": "cloth"}}} pins a material's class by index.
    for index, cls in ctx.settings.presets.get("_materials", {}).items():
        out[int(index)] = (cls, "settings file")
    return out


def _signature(ctx: Context, raw_signature: str, assignment: dict[int, str], regions: list[dict],
               presets: dict, normal_map: Path | None = None) -> str:
    """Identity of a texture's final maps: its AI outputs plus only the class
    parameters it actually uses (with this texture's own presets), so tuning one
    class leaves other textures alone."""
    used = set(assignment.values()) | {"default"} | {r["class"] for r in regions}
    from .compose import GUTTER_VERSION, RELIEF_VERSION

    payload = {
        "v": __version__, "raw": raw_signature, "height": ctx.settings.height, "gutter": GUTTER_VERSION,
        "classes": {str(i): c for i, c in sorted(assignment.items())},
        "params": {c: class_params(c, presets) for c in sorted(used)},
    }
    if regions:
        payload["regions"] = regions  # absent when unused, so existing signatures stay valid
    if normal_map is not None:
        stat = normal_map.stat()
        payload["normal_map"] = [str(normal_map), stat.st_size, int(stat.st_mtime), RELIEF_VERSION]
    return hashlib.sha1(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def cmd_generate(ctx: Context) -> dict:
    from PIL import Image

    from . import compose, uvmask
    from .ai import ModelRunner

    hashes = ctx.read("hashes.json").get("textures") or cmd_hashes(ctx)
    classes = material_classes(ctx)
    ctx.write("classes.json", {
        str(i): {"name": ctx.model.materials[i].name, "class": c, "reason": r} for i, (c, r) in classes.items()
    })
    done = ctx.read("generated.json")
    only = set(ctx.args.only.split(",")) if getattr(ctx.args, "only", None) else None
    runner = ModelRunner(tile=ctx.settings.tile, log=log)
    started = time.time()
    for key, texture in ctx.asset.textures.items():
        if only and key not in only and (not texture.source or texture.source.name not in only):
            continue
        if not hashes.get(key, {}).get("use"):
            log(f"skip {key}: no Remix hash")
            continue
        if not texture.source or not texture.source.exists():
            log(f"skip {key}: source image missing ({texture.source})")
            continue
        assignment = {i: classes[i][0] for i in texture.materials}
        override = ctx.settings.textures.get(texture.source.name) or ctx.settings.textures.get(key) or {}
        # A recoloured copy of the sheet (Evernight's whitened skin) stands in for the source as the
        # albedo and the AI input, and is always published, since the game still has the original.
        source = texture.source
        if override.get("albedo_source"):
            source = texture.source.parent / override["albedo_source"]
            if not source.exists():
                log(f"  warning: albedo_source {source} not found; using {texture.source.name}")
                source = texture.source
        recoloured = source != texture.source
        with Image.open(source) as image:
            source_size = image.size
            settings = ctx.settings.for_texture(key, texture.source.name, source_size)
        if settings.max_size != ctx.settings.max_size:
            log(f"  {texture.source.name}: size cap {settings.max_size} (texture override)")
        regions = [r for r in settings.regions if r.get("texture") in (texture.source.name, key)]
        used = set(assignment.values()) | {r["class"] for r in regions}
        presets = settings.presets  # this texture's own class overrides merged in
        if not recoloured and all(class_params(c, presets).get("original") for c in used):
            # Nothing on this sheet gets PBR (a body skin sheet): no override, so
            # Remix keeps its own texture and legacy material.
            if done.pop(key, None) is not None:
                ctx.write("generated.json", done)
            log(f"= {texture.source.name}: left to Remix ({', '.join(sorted(used))} keep the original look)")
            continue
        if "skin" in used and not class_params("skin", presets).get("original"):
            # The user's rule: body skin changes are made and applied only on their request.
            log(f"  note: skin on {texture.source.name} gets PBR from the settings; apply it only on the user's request")
        if recoloured:
            log(f"  albedo from {source} (recoloured copy; skin colour changes are made only on the user's request)")
        normal_map = texture.source.parent / override["normal_map"] if override.get("normal_map") else None
        if normal_map is not None and not normal_map.exists():
            log(f"  warning: normal_map {normal_map} not found; using the AI normals")
            normal_map = None
        raw_signature = compose.raw_signature(source, settings)
        signature = _signature(ctx, raw_signature, assignment, regions, presets, normal_map)
        previous = done.get(key)
        if previous and previous.get("signature") == signature and not ctx.args.force and \
                all(Path(p).exists() for p in previous["maps"].values()):
            log(f"= {texture.source.name}: up to date")
            continue
        t0 = time.time()
        log(f"> {texture.source.name} ({key}), used by {len(texture.materials)} material(s)")
        if ctx.args.force:
            for stale in (ctx.work / "raw").glob(f"{key}_*.png"):
                stale.unlink(missing_ok=True)
        width, height = compose.output_size(source_size, settings)
        ids, covered = uvmask.rasterize(ctx.model, assignment, width, height)
        raw = compose.load_or_make_raw(source, (texture.width, texture.height), settings, runner,
                                       ctx.work / "raw", key, log, covered, normal_map)
        albedo = raw.albedo
        island_map = uvmask.islands(ctx.model, texture.materials, width, height) \
            if any("islands" in r for r in regions) else None
        ids = uvmask.apply_regions(ids, albedo.rgba, regions, covered, island_map)
        masks = ctx.work / "masks"
        masks.mkdir(exist_ok=True)
        uvmask.preview(ids, albedo.rgba).save(masks / f"{key}_classes.png")
        maps, emissive_scale = compose.compose_maps(raw, ids, settings, covered)
        # Subsurface scattering is per material and forces it opaque, so only a sheet whose every
        # class asks for it gets it (Guinaifen's neck skin shares 衣.png with cloth). Remix takes the
        # skin colour from the transmittance texture, which must then be published.
        sss = min((class_params(c, presets).get("sss", 0.0) for c in used), default=0.0)
        if (sss > 0 or recoloured) and "albedo" not in maps:
            maps["albedo"] = albedo.rgba
        paths = compose.save_maps(maps, ctx.work / "maps", key)
        coverage = {name: round(float((ids == cid).mean()), 4) for name, cid in CLASS_ID.items() if (ids == cid).any()}
        done[key] = {
            "source": str(texture.source), "size": [width, height], "albedo_replaced": albedo.replace,
            "maps": {k: str(v) for k, v in paths.items()}, "classes": coverage,
            "uv_coverage": round(float(covered.mean()), 4), "signature": signature,
        }
        if recoloured:
            done[key]["albedo_source"] = str(source)
        if emissive_scale:
            done[key]["emissive_scale"] = emissive_scale
        if sss > 0:
            radius = next((class_params(c, presets).get("sss_radius") for c in used
                           if class_params(c, presets).get("sss_radius")), None)
            done[key]["subsurface"] = {"radius_scale": sss, "radius": radius}
        ctx.write("generated.json", done)
        log(f"  done in {time.time() - t0:.1f}s: {', '.join(sorted(paths))}"
            f"{'' if 'albedo' in paths else ' (albedo kept from game)'}")
    runner.unload()
    contact_sheet(ctx, done)
    log(f"generate finished in {time.time() - started:.0f}s; review {ctx.work / 'preview.jpg'}")
    return done


def contact_sheet(ctx: Context, done: dict) -> None:
    import numpy as np
    from PIL import Image, ImageDraw

    rows = [k for k in done if Path(done[k]["maps"].get("normal", "")).exists()]
    if not rows:
        return
    cell = 256
    columns = ["albedo", "classes", "normal", "roughness", "metallic", "emissive"]
    sheet = Image.new("RGB", (cell * len(columns), cell * len(rows) + 20), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for x, name in enumerate(columns):
        draw.text((x * cell + 6, 4), name, fill=(220, 220, 220))
    for y, key in enumerate(rows):
        info = done[key]
        tiles = {}
        source = info["maps"].get("albedo") or info["source"]
        with Image.open(source) as im:
            tiles["albedo"] = im.convert("RGB")
        classes = ctx.work / "masks" / f"{key}_classes.png"
        if classes.exists():
            tiles["classes"] = Image.open(classes).convert("RGB")
        oct_ = np.asarray(Image.open(info["maps"]["normal"]), np.float32)[..., :2] / 255 * 2 - 1
        nx, ny = (oct_[..., 0] + oct_[..., 1]) / 2, (oct_[..., 0] - oct_[..., 1]) / 2
        nz = np.clip(1 - np.abs(nx) - np.abs(ny), 0, 1)
        n = np.dstack([nx, ny, nz])
        n /= np.linalg.norm(n, axis=2, keepdims=True) + 1e-8
        tiles["normal"] = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))
        for kind in ("roughness", "metallic", "emissive"):
            if kind in info["maps"]:
                tiles[kind] = Image.open(info["maps"][kind]).convert("RGB")
        for x, name in enumerate(columns):
            if name in tiles:
                sheet.paste(tiles[name].resize((cell, cell), Image.BILINEAR), (x * cell, 20 + y * cell))
        draw.text((6, 24 + y * cell), Path(info["source"]).name, fill=(255, 255, 0))
    sheet.save(ctx.work / "preview.jpg", quality=88)


# ---------------------------------------------------------------- publish

def cmd_publish(ctx: Context) -> None:
    from . import dds, usda

    hashes = ctx.read("hashes.json").get("textures", {})
    done = ctx.read("generated.json")
    if not done:
        raise SystemExit("nothing generated yet; run 'generate' first")
    mod_dir = ctx.mod_dir()
    new_mod = not (mod_dir / "mod.usda").exists()
    texture_dir = mod_dir / "textures" / ctx.key
    jobs, materials, keep = [], [], set()
    for key, info in done.items():
        targets = hashes.get(key, {}).get("use", [])
        if not targets:
            continue
        rel = {}
        for kind, png in info["maps"].items():
            digest = hashlib.sha1(Path(png).read_bytes()).hexdigest()[:8]
            dst = texture_dir / f"{key}_{digest}.{dds.SUFFIX[kind]}.rtex.dds"
            keep.add(dst.name)
            if not dst.exists():
                jobs.append((Path(png), dst, kind))
            rel[kind] = f"../textures/{ctx.key}/{dst.name}"
        emissive = info.get("emissive_scale", 0.0) * ctx.settings.emissive_intensity
        for texture_hash in targets:
            materials.append((normalize_hash(texture_hash), rel, emissive, info.get("subsurface")))
    log(f"publishing {len(materials)} material override(s) to {mod_dir}")
    if jobs:
        log(f"encoding {len(jobs)} DDS file(s) with NVTT")
        dds.encode(jobs, log=log)
    usda.write_model_layer(mod_dir / "models" / f"{ctx.key}.usda", materials, ctx.settings.displacement,
                           f"Remix PBR AI layer for {ctx.key} (asset {ctx.asset.asset_id[:16]})")
    layers = usda.write_mod_root(mod_dir)
    if not ctx.args.no_prune:
        _prune(texture_dir, keep)
    _report_shared(mod_dir, ctx.key, {m[0] for m in materials}, layers)
    log(f"mod.usda now lists {len(layers)} model layer(s); Remix hot-reloads it within about a second")
    if new_mod:
        log("\nFIRST INSTALL: Remix only discovers new mod folders at startup. In game press Alt+X and click")
        log('"Rescan Mods & Reload USD Stage" once (or restart). Later publishes reload automatically.')


def _report_shared(mod_dir: Path, key: str, hashes: set[str], layers: list[str]) -> None:
    """Warn about textures this model shares with another published model.

    Identical files (common MMD accessory sheets) have one Remix hash, so two
    layers override the same material. USD lets the earlier sublayer win, and
    mod.usda lists layers alphabetically.
    """
    import re

    mine = {h.upper().replace("0X", "") for h in hashes}
    order = [Path(layer).stem for layer in layers]
    for layer in (mod_dir / "models").glob("*.usda"):
        if layer.stem == key:
            continue
        theirs = set(re.findall(r'over "mat_([0-9A-F]{16})"', layer.read_text(encoding="utf-8")))
        shared = mine & theirs
        if shared:
            winner = min(key, layer.stem, key=lambda k: order.index(k) if k in order else len(order))
            log(f"note: {len(shared)} texture(s) are identical to {layer.stem}'s, so Remix treats them as one "
                f"material; {winner}'s maps apply to both models")


def _prune(folder: Path, keep: set[str]) -> None:
    if not folder.exists():
        return
    for path in folder.glob("*.dds"):
        if path.name not in keep:
            try:
                path.unlink()  # may be held open by the runtime; it is retried next publish
            except OSError:
                pass


def cmd_remove(ctx: Context) -> None:
    from . import usda

    mod_dir = ctx.mod_dir()
    layer = mod_dir / "models" / f"{ctx.key}.usda"
    if layer.exists():
        layer.unlink()
    usda.write_mod_root(mod_dir)
    _prune(mod_dir / "textures" / ctx.key, set())
    log(f"removed {ctx.key} from {mod_dir.name}")


def _screenshot(ctx: Context, label: str) -> Path:
    """Take a Source ``jpeg`` screenshot (it captures the Remix frame) and return its path."""
    import re

    log_path = ctx.bridge.console_log
    start = log_path.stat().st_size
    ctx.bridge.console("jpeg")
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        time.sleep(0.5)
        with log_path.open("rb") as f:
            f.seek(start)
            text = f.read().decode("utf-8", errors="replace")
        m = re.search(r"Wrote '([^']+\.jpg)'", text)
        if m:
            path = ctx.game_root / "garrysmod" / m.group(1)
            log(f"  {label}: {path.name}")
            return path
    raise TimeoutError("the game did not report a screenshot")


def _reload_and_wait(ctx: Context, write, settle: float) -> None:
    """Rewrite mod.usda, then wait until Remix has swapped the new state in.

    "async reload completed" is not enough: the swap can lag it by ~9 s when
    many textures are preloaded (measured with two models, 1.4 GB of DDS), and
    a fixed delay then photographs the old state.
    """
    log_path = ctx.game_root / "rtx-remix" / "logs" / "remix-dxvk.log"
    start = log_path.stat().st_size if log_path.exists() else 0
    write()
    # Runtime c6b48ed1 (in use since 2026-10-25) logs no reload line at all; then the
    # settle time alone covers the swap.
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        time.sleep(0.5)
        with log_path.open("rb") as f:
            f.seek(start)
            text = f.read().decode("utf-8", errors="replace")
        if "swapped in successfully" in text:
            # A second reload can still be queued behind the first; take the last swap.
            last = text.rfind("swapped in successfully")
            if "reload completed" not in text[last:]:
                break
    else:
        log("  note: no reload swap logged within 30 s (normal for runtime c6b48ed1); relying on --settle")
    time.sleep(settle)  # textures stream in and the denoiser settles


def cmd_compare(ctx: Context) -> None:
    """A/B the published maps in the running game from the current camera."""
    from PIL import Image, ImageDraw

    from . import usda

    if not ctx.bridge:
        raise SystemExit("compare needs the running game")
    mod_dir = ctx.mod_dir()
    if not (mod_dir / "models" / f"{ctx.key}.usda").exists():
        raise SystemExit("this model is not published yet")
    settle = ctx.args.settle
    ctx.bridge.console("jpeg_quality 95")
    try:
        _reload_and_wait(ctx, lambda: usda.write_mod_root(mod_dir, exclude={ctx.key}), settle)
        before = _screenshot(ctx, "without AI maps")
    finally:
        _reload_and_wait(ctx, lambda: usda.write_mod_root(mod_dir), settle)
    after = _screenshot(ctx, "with AI maps")
    a, b = Image.open(before).convert("RGB"), Image.open(after).convert("RGB")
    width = 1600
    a = a.resize((width, round(a.height * width / a.width)), Image.LANCZOS)
    b = b.resize(a.size, Image.LANCZOS)
    sheet = Image.new("RGB", (a.width, a.height * 2 + 8), (0, 0, 0))
    sheet.paste(a, (0, 0))
    sheet.paste(b, (0, a.height + 8))
    draw = ImageDraw.Draw(sheet)
    draw.text((12, 10), "Remix, original materials", fill=(255, 255, 0))
    draw.text((12, a.height + 18), "Remix + AI PBR (rpai)", fill=(255, 255, 0))
    out = ctx.work / f"compare_{time.strftime('%Y%m%d_%H%M%S')}.jpg"
    sheet.save(out, quality=90)
    log(f"comparison saved to {out}")


# ---------------------------------------------------------------- status / doctor

def cmd_status(args) -> None:
    root, _ = locate_game(args.game_root)
    mod_dir = root / "rtx-remix" / "mods" / (args.mod_name or config.Settings().mod_name)
    log(f"mod folder: {mod_dir}")
    for layer in sorted((mod_dir / "models").glob("*.usda")):
        count = layer.read_text(encoding="utf-8").count('over "mat_')
        log(f"  {layer.stem}: {count} material override(s)")


def cmd_doctor(args) -> None:
    ok = True

    def check(label, fn):
        nonlocal ok
        try:
            log(f"[ok]   {label}: {fn()}")
        except Exception as error:  # noqa: BLE001 - report every failure
            ok = False
            log(f"[fail] {label}: {error}")

    def torch_info():
        import torch

        return f"torch {torch.__version__}, CUDA {torch.cuda.is_available()} " \
               f"{torch.cuda.get_device_name(0) if torch.cuda.is_available() else ''}"

    def weights():
        missing = [p.name for p in [*config.UPSCALERS.values(), config.NORMAL_MODEL, config.ROUGHNESS_MODEL,
                                    config.HEIGHT_MODEL] if not p.exists()]
        if missing:
            raise FileNotFoundError(", ".join(missing))
        return str(config.MODELS / "pbrify")

    def game():
        from .gamebridge import GameBridge

        bridge = GameBridge()
        reply = bridge.run_client_lua('return { remix = istable(RemixMaterial), map = game.GetMap() }', timeout=10)
        return f"{bridge.game_root} map={reply.get('map')} RemixMaterial={reply.get('remix')}"

    check("python packages", torch_info)
    check("model weights", weights)
    check("NVTT exporter", lambda: str(config.nvtt_path()))
    check("running game", game)
    sys.exit(0 if ok else 1)


# ---------------------------------------------------------------- main

def main(argv: list[str] | None = None) -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(prog="rpai", description="AI PBR textures for RTX Remix (Garry's Mod + Model Hotloader)")
    sub = parser.add_subparsers(dest="command", required=True)

    def model_command(name: str, help_text: str):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("pmx", help="path to the .pmx (as imported with Model Hotloader)")
        p.add_argument("--mdl", help="compiled model as the game loads it (models/.../x.mdl), for a character "
                                     "installed as a compiled addon instead of a Model Hotloader import; remembered")
        p.add_argument("--asset", help="Model Hotloader import (id or prefix) to use for this PMX, e.g. a re-import "
                                       "whose source folder is gone, rebuilt from a byte-identical copy")
        p.add_argument("--game-root", help="Garry's Mod folder (default: the running game)")
        p.add_argument("--settings", action="append",
                       help="JSON file with Settings fields and class presets (repeatable; later files win)")
        p.add_argument("--mod", dest="mod_name", help="mod folder name under rtx-remix/mods (default ai_pbr)")
        p.add_argument("--max-size", type=int, help="long side of generated maps (default 4096)")
        p.add_argument("--upscaler", choices=["auto", "v4", "span"],
                       help="v4 (default): PBRify DAT, best; span: ~40x faster; auto: DAT up to 1024px, SPAN above")
        p.add_argument("--height", action="store_true", default=None, help="also generate height maps")
        p.add_argument("--displacement", type=float, help="Remix displace_in when height maps are used")
        p.add_argument("--emissive-intensity", type=float,
                       help="multiplier on the eye emission (default 1); takes effect on publish, no regeneration")
        p.add_argument("--tile", type=int, help="inference tile size (default 512)")
        p.add_argument("--only", help="comma-separated texture keys or source file names")
        p.add_argument("--force", action="store_true", help="regenerate even if up to date")
        p.add_argument("--no-live", action="store_true", help="do not query the running game for hashes")
        p.add_argument("--no-prune", action="store_true", help="keep DDS files the new layer no longer uses (for A/B tests)")
        return p

    model_command("run", "hashes + generate + publish")
    model_command("hashes", "find Remix texture hashes (live from the game, else predicted)")
    model_command("generate", "AI upscale + PBR maps into the work folder")
    model_command("publish", "encode DDS and write the Remix mod layer")
    model_command("remove", "remove this model's layer from the mod")
    model_command("compare", "screenshot the game without and with the AI maps (same camera)").add_argument(
        "--settle", type=float, default=4.0, help="seconds to wait after Remix swaps the reload in, before the screenshot")
    status = sub.add_parser("status", help="list models in the mod")
    status.add_argument("--game-root")
    status.add_argument("--mod", dest="mod_name")
    sub.add_parser("doctor", help="check the installation").add_argument("--game-root")
    args = parser.parse_args(argv)

    if args.command == "doctor":
        return cmd_doctor(args)
    if args.command == "status":
        return cmd_status(args)
    ctx = Context(args)
    if args.command in ("run", "hashes"):
        cmd_hashes(ctx)
    if args.command in ("run", "generate"):
        cmd_generate(ctx)
    if args.command in ("run", "publish"):
        cmd_publish(ctx)
    if args.command == "remove":
        cmd_remove(ctx)
    if args.command == "compare":
        cmd_compare(ctx)
