"""Export Model Hotloader characters as a Workshop package add-on folder, through the running game.

It does what the library's Export dialog (lua/mmdhl/workshop_export.lua) does, with the same item
settings (spawn preset, body groups, arms, fits, terms-of-use records) and the same native call
(StartPackageExport), then unpacks the archive Model Hotloader writes into an add-on folder
(addon.json + data_static/mmdhl/...) that package_content.py takes as --addon.

    python hotloader_export.py --game-root <GarrysMod> --asset cf3eec2f --asset e2c25f9e ^
        --title "Evernight and March 7th (Model Hotloader + RTX PBR)" --description-file desc.txt ^
        --file-name evernight-march7th --tag cartoon --out out\\packages\\x\\mmdhl_x

--asset takes the full 64-digit id or any unique prefix. The game must be in a map (client Lua
runs there) with Model Hotloader loaded; the models must be in its library (not shared ones).

The export dialog asks the player to acknowledge the models' terms of use first
(mmdhl_terms_warning_export). This script does not show that dialog and does not change the
setting: use it for private items, and make an item public only after exporting through the dialog.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tool"
sys.path.insert(0, str(TOOL))

START = r'''
local meta = util.JSONToTable(__META__)
local native = mmdhl.native
if not native.StartPackageExport then return { error = "this Model Hotloader has no package export" } end
local items = {}
for _, id in ipairs(meta.assets) do
  local entry = mmdhl.library.entries[id]
  if not entry then return { error = "not in the library: " .. id } end
  if entry.shared then return { error = "a shared (Workshop) model cannot be exported: " .. id } end
  if not mmdhl.workshop.InCache("character", id) then return { error = "not in the cache: " .. id } end
  local s = entry.settings or {}
  local item = { kind = "character", asset = id, name = entry.name,
    settings = { spawn = s.spawn, bodygroups = s.bodygroups },
    terms = mmdhl.terms and mmdhl.terms.ForPackage("character", id) or nil }
  local arms = mmdhl.GetArmsParts and mmdhl.GetArmsParts(id) or {}
  if next(arms) then item.arms = {} for k, v in pairs(arms) do item.arms[tostring(k)] = v end end
  local fit = util.JSONToTable(file.Read("mmd_hotloader/fit_overrides/" .. id .. ".json", "DATA") or "")
  -- Who saved a physics default stays on this computer (as the dialog does).
  if istable(fit) then
    if istable(fit.editor) then fit.editor.savedBy = nil fit.editor.savedByName = nil end
    item.fit = fit
  end
  items[#items + 1] = item
end
local spec = { title = meta.title, author = meta.author, description = meta.description, tags = meta.tags,
  install = "workshop", fileName = meta.file_name, items = items }
local handle, err = native.StartPackageExport(util.TableToJSON(spec))
if not handle then return { error = tostring(err) } end
RPAI_EXPORT = handle
local names = {}
for _, item in ipairs(items) do names[#names + 1] = item.name end
return { started = true, names = names }
'''

POLL = r'''
local state = util.JSONToTable(mmdhl.native.PollPackageExport(RPAI_EXPORT) or "") or { state = "failed" }
return state
'''


def resolve_assets(game_root: Path, prefixes: list[str]) -> list[str]:
    folder = game_root / "garrysmod" / "data" / "mmd_hotloader" / "assets"
    out = []
    for prefix in prefixes:
        hits = [p.name for p in folder.iterdir() if p.name.startswith(prefix.lower())]
        if len(hits) != 1:
            raise SystemExit(f"--asset {prefix}: {len(hits)} matches in {folder}")
        out.append(hits[0])
    return out


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--game-root", type=Path, required=True)
    p.add_argument("--asset", action="append", required=True)
    p.add_argument("--title", required=True)
    p.add_argument("--author", default="SheepyLord")
    p.add_argument("--description-file", type=Path, required=True)
    p.add_argument("--file-name", required=True, help="the archive's name (no extension)")
    p.add_argument("--tag", action="append", default=[], help="a Workshop tag, at most two")
    p.add_argument("--out", type=Path, required=True, help="the add-on folder to write (must not exist)")
    p.add_argument("--timeout", type=float, default=600.0)
    p.add_argument("--gmapack", type=Path, default=Path(r"H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\tools\gmapack\gmapack.py"),
                   help="the native-loader repository's tools/gmapack/gmapack.py (unpacks the archive)")
    a = p.parse_args()
    if a.out.exists():
        raise SystemExit(f"{a.out} exists")
    from rpai.gamebridge import GameBridge, lua_long_string
    bridge = GameBridge(a.game_root)
    assets = resolve_assets(a.game_root, a.asset)
    meta = {"assets": assets, "title": a.title, "author": a.author, "tags": a.tag, "file_name": a.file_name,
            "description": a.description_file.read_text(encoding="utf-8").strip()}
    r = bridge.run_client_lua(START.replace("__META__", lua_long_string(json.dumps(meta, ensure_ascii=False))))
    if not r.get("ok") or r.get("error"):
        raise SystemExit(f"export not started: {r.get('error')}")
    print("exporting:", ", ".join(r.get("names", {}).values() if isinstance(r.get("names"), dict) else r.get("names", [])))
    deadline = time.monotonic() + a.timeout
    while True:
        s = bridge.run_client_lua(POLL)
        if s.get("state") == "running":
            print(f"  {s.get('stage')} {float(s.get('progress') or 0):.0%}", flush=True)
        else:
            break
        if time.monotonic() > deadline:
            raise SystemExit("timed out; the export may still be running in the game")
        time.sleep(3)
    if s.get("state") != "complete":
        raise SystemExit(f"export {s.get('state')}: {s.get('error')}")
    print(f"archive {s['path']} ({int(s['bytes']) / 1e6:.0f} MB, {s['items']} model(s), package {s['packageId']})")
    subprocess.run([sys.executable, "-I", str(a.gmapack), "extract", "--file", s["path"], "--out", str(a.out)],
                   check=True)
    files = sorted(p for p in a.out.rglob("*") if p.is_file())
    print(f"add-on folder {a.out}: {len(files)} files, {sum(f.stat().st_size for f in files) / 1e6:.0f} MB")


if __name__ == "__main__":
    main()
