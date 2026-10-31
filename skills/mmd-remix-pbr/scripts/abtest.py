"""AABB test rig: compare RTX Remix material variants on a spawned Model Hotloader character.

Works through rpai's console bridge, so it needs no display: a scripted camera (a client
CalcView hook), optional part hiding through Model Hotloader's own API, variant model layers
swapped into the live mod, and every view shot N times back to back, so each comparison
carries its own noise floor ("AABB": A, A, B, B).

    python abtest.py bones   --asset 9cdc990f
    python abtest.py capture --asset 9cdc990f --model-key new_mmd_model_9cdc990f ^
        --variant A=layer_a.usda --variant B=layer_b.usda --views views.json --repeats 2 --out run1
    python abtest.py metrics run1 --baseline A --mask skin

With more than one game running, put --game-root <GarrysMod folder> before the command.

views.json maps a view name to a camera. The target is a bone position plus an optional
offset (or an absolute "target"); the camera sits at target + "camera", looking at the target:

    {"forearm": {"bone": "ValveBiped.Bip01_L_Forearm", "camera": [0.01, 0, 18], "fov": 40},
     "neck": {"bone": "ValveBiped.Bip01_Neck1", "target_offset": [-1, 0, 2], "camera": [-0.01, 0, 14],
              "fov": 32, "crop": [1100, 150, 2900, 1100]}}

A small horizontal component in "camera" picks which way is up in a straight-down shot.
"crop" (pixels of the game's screenshot) only affects the comparison sheets; leave it out in the
user's debug sessions, which keep frames whole. With several spawned copies of the model, "ent"
picks one by its order among them (0 = lowest entity index), e.g. a face-up and a face-down copy
for front and back views in one run; --hide then hides those parts on every copy.

capture always puts the original layer back, removes its camera hook and restores exactly the
parts it hid on each copy, even when the game stops answering partway (partial results are kept).
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import time
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tool"
sys.path.insert(0, str(TOOL))

HOOK = "rpai_abtest_cam"
# --game-root picks the game when several run (another session's PoC test beside the user's game).
GAME_ROOT: Path | None = None


# ---------------------------------------------------------------- game helpers

def bridge():
    from rpai.gamebridge import GameBridge
    return GameBridge(GAME_ROOT)


def lua(b, body: str, timeout: float = 20.0) -> dict:
    result = b.run_client_lua(body, timeout)
    if not result.get("ok"):
        raise RuntimeError(result.get("error"))
    return result


# --asset is a Model Hotloader asset id (prefix), or a compiled model's path (models/.../x.mdl), which
# matches spawned entities of that model; the player and its hands are skipped (a player model can
# share the path).
FIND = r"""
local want = string.lower(%s)
local compiled = string.EndsWith(want, ".mdl")
RPAI_AB_ENTS = {}
for _, e in ipairs(ents.GetAll()) do
  if IsValid(e) then
    local hit
    if compiled then
      hit = not e:IsPlayer() and e:GetClass() ~= "gmod_hands" and string.lower(e:GetModel() or "") == want
    else
      hit = e.GetNW2String and e:GetNW2String("MMDHLAsset", ""):sub(1, #want) == want
    end
    if hit then RPAI_AB_ENTS[#RPAI_AB_ENTS + 1] = e end
  end
end
table.sort(RPAI_AB_ENTS, function(a, b) return a:EntIndex() < b:EntIndex() end)
RPAI_AB_ENT = RPAI_AB_ENTS[1]
if not IsValid(RPAI_AB_ENT) then error("no spawned entity for " .. want) end
"""


def bones(b, asset: str, ent: int = 0) -> dict:
    return lua(b, FIND % json.dumps(asset) + r"""
local e = RPAI_AB_ENTS[%d] if not IsValid(e) then error("only " .. #RPAI_AB_ENTS .. " spawned copies") end
e:SetupBones()
local out = { index = e:EntIndex(), copies = #RPAI_AB_ENTS, bones = {} }""" % (ent + 1) + r"""
for i = 0, e:GetBoneCount() - 1 do
  local p = e:GetBonePosition(i)
  out.bones[#out.bones + 1] = { i = i, name = e:GetBoneName(i), pos = { p.x, p.y, p.z } }
end
return out
""")


def set_camera(b, asset: str, view: dict) -> None:
    if "target" in view:
        target = "Vector(%f, %f, %f)" % tuple(view["target"])
    else:
        off = view.get("target_offset", [0, 0, 0])
        bone = json.dumps(view["bone"])
        target = ("(function() local e = RPAI_AB_ENTS[%d] if not IsValid(e) then error('no spawned copy %d') end "
                  "e:SetupBones() local i = e:LookupBone(%s) "
                  "if not i then error('bone not found: ' .. %s) end return e:GetBonePosition(i) + Vector(%f, %f, %f) end)()"
                  % (view.get("ent", 0) + 1, view.get("ent", 0), bone, bone, *off))
    cam = view["camera"]
    lua(b, FIND % json.dumps(asset) + f"""
local t = {target}
local o = t + Vector({cam[0]}, {cam[1]}, {cam[2]})
local v = {{ origin = o, angles = (t - o):Angle(), fov = {view.get("fov", 40)}, drawviewer = false }}
hook.Add("CalcView", "{HOOK}", function() return v end)
return {{}}
""")


def camera_off(b) -> None:
    lua(b, f'hook.Remove("CalcView", "{HOOK}") return {{}}')


def visibility(b, asset: str, indices: list[int]) -> list[dict[int, bool]]:
    """Visibility of the given parts on every spawned copy, in copy order."""
    r = lua(b, FIND % json.dumps(asset) + "local out = {} for k, e in ipairs(RPAI_AB_ENTS) do local v = {} "
            "for _, i in ipairs({%s}) do v[#v + 1] = mmdhl.IsMaterialVisible(e, i) end out[k] = v end return { v = out }"
            % ", ".join(map(str, indices)))
    return [dict(zip(indices, row)) for row in r["v"]]


def set_visible(b, asset: str, per_copy: list[list[int]], visible: bool) -> None:
    # Model Hotloader draws natively and keeps parts as bodygroups; SetSubMaterial does nothing.
    for k, indices in enumerate(per_copy):
        if indices:
            lua(b, FIND % json.dumps(asset) + "local e = RPAI_AB_ENTS[%d] for _, i in ipairs({%s}) do mmdhl.SetMaterialVisible(e, i, %s) end return {}"
                % (k + 1, ", ".join(map(str, indices)), "true" if visible else "false"))
    if any(per_copy):
        time.sleep(1.0)


def screenshot(b, label: str) -> Path:
    # The new file in garrysmod/screenshots, not console.log's "Wrote" line: a game started
    # without -condebug writes no console.log (the user's game, 2026-10-30).
    folder = b.game_root / "garrysmod" / "screenshots"
    before = {p.name for p in folder.glob("*.jpg")}
    b.console("jpeg_quality 95")
    b.console("jpeg")
    deadline = time.monotonic() + 20
    sizes: dict[Path, int] = {}
    while time.monotonic() < deadline:
        time.sleep(0.4)
        for path in folder.glob("*.jpg"):
            if path.name in before:
                continue
            size = path.stat().st_size
            if size and sizes.get(path) == size:  # finished writing
                print(f"  {label}: {path.name}", flush=True)
                return path
            sizes[path] = size
    raise TimeoutError("the game did not report a screenshot")


def reload_mod(mod_dir: Path, game_root: Path, settle: float) -> None:
    """Rewrite mod.usda (the runtime watches only its mtime) and wait for the swap.

    remix-main+384581b1 logs "swapped in successfully". The c6b48ed1 build the game runs since
    2026-10-25 logs no reload line, so after 30 s the settle time alone has to cover the swap.
    """
    from rpai import usda
    log = game_root / "rtx-remix" / "logs" / "remix-dxvk.log"
    start = log.stat().st_size if log.exists() else 0
    usda.write_mod_root(mod_dir)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        time.sleep(0.5)
        with log.open("rb") as f:
            f.seek(start)
            text = f.read().decode("utf-8", "replace")
        if "swapped in successfully" in text and "reload completed" not in text[text.rfind("swapped in successfully"):]:
            break
    else:
        print("  note: no reload swap logged within 30 s (normal for runtime c6b48ed1); relying on --settle", flush=True)
    time.sleep(settle)


# ---------------------------------------------------------------- commands

def cmd_bones(args) -> None:
    r = bones(bridge(), args.asset, args.ent)
    print(f"entity {r['index']} (copy {args.ent} of {r['copies']})")
    for bone in r["bones"]:
        x, y, z = bone["pos"]
        print(f"{bone['i']:3} {bone['name']:<34} {x:9.2f} {y:9.2f} {z:9.2f}")


def cmd_capture(args) -> None:
    b = bridge()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    views = json.loads(Path(args.views).read_text(encoding="utf-8"))
    variants = dict(v.split("=", 1) for v in args.variant)
    mod_dir = b.game_root / "rtx-remix" / "mods" / args.mod
    layer = mod_dir / "models" / f"{args.model_key}.usda"
    if not layer.exists():
        raise SystemExit(f"{layer} does not exist: publish the model first")
    for name, path in variants.items():
        if not Path(path).exists():
            raise SystemExit(f"variant {name}: {path} not found")
    backup = out / "_original_layer.usda"
    shutil.copyfile(layer, backup)
    hide = [int(i) for i in args.hide.split(",")] if args.hide else []
    if hide and args.asset.lower().endswith(".mdl"):
        raise SystemExit("--hide uses Model Hotloader's part API; a compiled model has none")
    # Per copy, only the parts that are visible now get hidden, and exactly those come back.
    hidden_before = visibility(b, args.asset, hide) if hide else []
    to_hide = [[i for i, visible in row.items() if visible] for row in hidden_before]
    results = {"asset": args.asset, "model_key": args.model_key, "variants": list(variants), "views": views,
               "repeats": args.repeats, "shots": {}, "complete": False}
    try:
        set_visible(b, args.asset, to_hide, False)
        for name, path in variants.items():
            print(f"variant {name}", flush=True)
            shutil.copyfile(path, layer)
            reload_mod(mod_dir, b.game_root, args.settle)
            results["shots"][name] = {}
            for view_name, view in views.items():
                set_camera(b, args.asset, view)
                time.sleep(args.camera_settle)  # after a camera cut the denoiser needs a few seconds
                shots = [screenshot(b, f"{name}/{view_name}/{k + 1}") for k in range(args.repeats)]
                results["shots"][name][view_name] = [str(s) for s in shots]
                (out / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
        results["complete"] = True
    except (RuntimeError, TimeoutError) as error:
        print(f"stopped: {error}. Partial results kept in {out / 'results.json'}", flush=True)
    finally:
        shutil.copyfile(backup, layer)
        try:
            reload_mod(mod_dir, b.game_root, 1.0)
        except OSError as error:
            print(f"warning: could not trigger the reload ({error}); the original layer file is back in place")
        for step in (lambda: camera_off(b), lambda: set_visible(b, args.asset, to_hide, True)):
            try:
                step()
            except (RuntimeError, TimeoutError) as error:
                print(f"warning: cleanup in game failed ({error}); check the camera and parts by hand")
        (out / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"results: {out / 'results.json'}")


def cmd_metrics(args) -> None:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
    from scipy import ndimage

    run = Path(args.run)
    results = json.loads((run / "results.json").read_text(encoding="utf-8"))
    variants = [v for v in results["variants"] if v in results["shots"]]
    baseline = args.baseline or variants[0]
    lum_w = np.array([0.2126, 0.7152, 0.0722], np.float32)
    try:
        font, small = ImageFont.truetype("arial.ttf", 22), ImageFont.truetype("arial.ttf", 18)
    except OSError:
        font = small = ImageFont.load_default()

    def load(p):
        return np.asarray(Image.open(p).convert("RGB"), np.float32)

    def band(channel):
        return ndimage.gaussian_filter(channel, 2) - ndimage.gaussian_filter(channel, 40)

    table, md = {}, [f"# AABB metrics ({run.name}), baseline {baseline}", ""]
    for view_name, view in results["views"].items():
        if view_name not in results["shots"].get(baseline, {}):
            continue
        ref_shots = [load(p) for p in results["shots"][baseline][view_name]]
        ref = ref_shots[0]
        if args.mask == "skin":
            lum = ref @ lum_w
            mask = (lum > 110) & ((ref[..., 0] - ref[..., 2]) < 75) & (ref[..., 0] >= ref[..., 2]) & (ref[..., 0] - ref[..., 1] < 45)
            mask = ndimage.binary_erosion(mask, iterations=8)
        else:
            mask = np.ones(ref.shape[:2], bool)
        ref_mean = sum(ref_shots) / len(ref_shots)
        ref_red = band(ref[..., 0] - (ref[..., 1] + ref[..., 2]) / 2)[mask].std()
        ref_lum = band(ref @ lum_w)[mask].std()
        md += [f"## {view_name} ({int(mask.sum())} px)", "",
               "| variant | noise (repeat) | change vs baseline | detail kept (redness / luminance) | mean RGB |",
               "| --- | --- | --- | --- | --- |"]
        tiles = []
        for v in variants:
            paths = results["shots"][v].get(view_name)
            if not paths:
                md.append(f"| {v} | not captured | | | |")
                continue
            shots = [load(p) for p in paths]
            mean = sum(shots) / len(shots)
            noise = float(np.abs(shots[0] - shots[1])[mask].mean()) if len(shots) > 1 else float("nan")
            effect = float(np.abs(mean - ref_mean)[mask].mean())
            red = float(band(shots[0][..., 0] - (shots[0][..., 1] + shots[0][..., 2]) / 2)[mask].std() / max(ref_red, 1e-6))
            lum = float(band(shots[0] @ lum_w)[mask].std() / max(ref_lum, 1e-6))
            rgb = mean[mask].mean(0)
            table.setdefault(view_name, {})[v] = {"noise": noise, "effect": effect, "detail_redness": red,
                                                  "detail_luminance": lum, "mean_rgb": [round(float(c), 1) for c in rgb]}
            md.append(f"| {v} | {noise:.2f} | {effect:.2f} | {red:.0%} / {lum:.0%} | {rgb[0]:.0f}, {rgb[1]:.0f}, {rgb[2]:.0f} |")
            im = Image.open(paths[0]).convert("RGB")
            if view.get("crop"):
                im = im.crop(tuple(view["crop"]))
            t = im.resize((640, round(640 * im.height / im.width)), Image.LANCZOS)
            d = ImageDraw.Draw(t)
            d.rectangle([0, 0, 640, 30], fill=(0, 0, 0))
            d.text((8, 3), v, fill=(255, 255, 0), font=font)
            d.rectangle([0, t.height - 26, 640, t.height], fill=(0, 0, 0))
            d.text((8, t.height - 24), f"change {effect:.1f}/255  noise {noise:.1f}  detail {red:.0%}", fill=(255, 255, 255), font=small)
            tiles.append(t)
        md.append("")
        if tiles:
            cols = 2 if len(tiles) > 1 else 1
            rows = (len(tiles) + cols - 1) // cols
            h = max(t.height for t in tiles)
            sheet = Image.new("RGB", (646 * cols - 6, (h + 6) * rows - 6), (0, 0, 0))
            for i, t in enumerate(tiles):
                sheet.paste(t, ((i % cols) * 646, (i // cols) * (h + 6)))
            sheet.save(run / f"sheet_{view_name}.jpg", quality=90)
    (run / "metrics.json").write_text(json.dumps(table, indent=1), encoding="utf-8")
    (run / "metrics.md").write_text("\n".join(md), encoding="utf-8")
    print("\n".join(md))


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--game-root", type=Path, help="Garry's Mod folder of the game to use (default: the first running)")
    sub = p.add_subparsers(dest="command", required=True)
    s = sub.add_parser("bones", help="list the spawned character's bones")
    s.add_argument("--asset", required=True, help="Model Hotloader asset id or prefix (e.g. 9cdc990f), "
                                                   "or a compiled model's path (models/.../x.mdl)")
    s.add_argument("--ent", type=int, default=0, help="which spawned copy (0 = lowest entity index)")
    s = sub.add_parser("capture", help="shoot every variant layer from every view, N times each")
    s.add_argument("--asset", required=True)
    s.add_argument("--model-key", required=True, help="rpai model key = the layer name under mods/<mod>/models")
    s.add_argument("--variant", action="append", required=True, help="NAME=path/to/layer.usda (repeatable, in order)")
    s.add_argument("--views", required=True, help="views.json")
    s.add_argument("--repeats", type=int, default=2)
    s.add_argument("--hide", help="comma-separated material indices to hide during the capture")
    s.add_argument("--mod", default="ai_pbr")
    # Auto-exposure re-adapts after a material swap: with 8 s the first shot of a variant came out
    # 8/255 darker than its repeat (Guinaifen stockings, 2026-10-25); 20 s and 6 s left 0.9-1.9/255.
    s.add_argument("--settle", type=float, default=20.0, help="seconds after a reload swap")
    s.add_argument("--camera-settle", type=float, default=6.0, help="seconds after a camera cut")
    s.add_argument("--out", required=True)
    s = sub.add_parser("metrics", help="noise floor, change and detail retention per view, plus comparison sheets")
    s.add_argument("run")
    s.add_argument("--baseline")
    s.add_argument("--mask", choices=["skin", "all"], default="skin")
    args = p.parse_args()
    global GAME_ROOT
    GAME_ROOT = args.game_root
    {"bones": cmd_bones, "capture": cmd_capture, "metrics": cmd_metrics}[args.command](args)


if __name__ == "__main__":
    main()
