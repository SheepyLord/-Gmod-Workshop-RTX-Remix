"""Talk to a running Garry's Mod (Source engine) instance.

Source executes the payload of a ``WM_COPYDATA`` message sent to its
``Valve001`` window as console text (the mechanism behind ``-hijack``).
Measured on the x86-64 RTX client: ``echo RPAI_PING_2`` sent this way is
printed to the console immediately. Lua runs through ``lua_run_cl`` (falling
back to the server's ``SendLua`` in single player), reading its code from
``garrysmod/data/rpai`` and answering with a JSON file in the same folder.
"""

from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import json
import time
import uuid
from pathlib import Path

WM_COPYDATA = 0x004A
SMTO_ABORTIFHUNG = 0x0002
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

_user32 = ctypes.windll.user32
_kernel32 = ctypes.windll.kernel32


class _COPYDATASTRUCT(ctypes.Structure):
    _fields_ = [("dwData", ctypes.c_size_t), ("cbData", wt.DWORD), ("lpData", ctypes.c_void_p)]


def _process_path(pid: int) -> Path | None:
    handle = _kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return None
    try:
        size = wt.DWORD(1024)
        buffer = ctypes.create_unicode_buffer(size.value)
        if _kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return Path(buffer.value)
    finally:
        _kernel32.CloseHandle(handle)
    return None


def find_game_windows() -> list[tuple[int, int, Path]]:
    """All (hwnd, pid, exe) for visible Source windows owned by gmod.exe/hl2.exe."""
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def callback(hwnd, _):
        name = ctypes.create_unicode_buffer(64)
        _user32.GetClassNameW(hwnd, name, 64)
        if name.value == "Valve001":
            pid = wt.DWORD()
            _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            exe = _process_path(pid.value)
            if exe and exe.name.lower() in ("gmod.exe", "hl2.exe"):
                found.append((hwnd, pid.value, exe))
        return True

    _user32.EnumWindows(callback, 0)
    return found


def game_root_from_exe(exe: Path) -> Path:
    for parent in exe.parents:
        if (parent / "garrysmod").is_dir():
            return parent
    raise FileNotFoundError(f"no garrysmod folder above {exe}")


class GameBridge:
    def __init__(self, game_root: Path | None = None):
        windows = find_game_windows()
        if game_root is not None:
            windows = [w for w in windows if game_root_from_exe(w[2]).resolve() == Path(game_root).resolve()]
        if not windows:
            raise RuntimeError("Garry's Mod is not running (no Valve001 window owned by gmod.exe).")
        self.hwnd, self.pid, self.exe = windows[0]
        self.game_root = game_root_from_exe(self.exe)
        self.data_dir = self.game_root / "garrysmod" / "data" / "rpai"
        self.data_dir.mkdir(parents=True, exist_ok=True)

    @property
    def console_log(self) -> Path:
        return self.game_root / "garrysmod" / "console.log"

    def console(self, command: str, attempts: int = 3) -> bool:
        payload = command.encode("utf-8") + b"\0"
        buffer = ctypes.create_string_buffer(payload, len(payload))
        cds = _COPYDATASTRUCT(0, len(payload), ctypes.cast(buffer, ctypes.c_void_p))
        result = ctypes.c_size_t(0)
        for attempt in range(attempts):
            # A game that is loading a map or rebuilding its swap chain can stall the
            # message loop for several seconds; that is not a hang, so try again.
            if _user32.SendMessageTimeoutW(self.hwnd, WM_COPYDATA, 0, ctypes.byref(cds), SMTO_ABORTIFHUNG, 5000,
                                           ctypes.byref(result)):
                return True
            if attempt + 1 < attempts:
                time.sleep(2)
        return False

    def run_client_lua(self, body: str, timeout: float = 20.0) -> dict:
        """Run ``body`` (a Lua function body returning a table) on the client.

        The command line never carries the code itself: Source splits console
        input at ``;`` and newlines, so only a short loader goes through.
        """
        token = uuid.uuid4().hex[:12]
        request = self.data_dir / f"req_{token}.txt"
        response = self.data_dir / f"res_{token}.json"
        request.write_text(_wrap(body, token), encoding="utf-8")
        loader = f'RunString(file.Read("rpai/req_{token}.txt","DATA"),"rpai_{token}")'
        try:
            attempts = [f"lua_run_cl {loader}", f"lua_run Entity(1):SendLua([[{loader}]])"]
            deadline_each = max(timeout / len(attempts), 5.0)
            for command in attempts:
                if not self.console(command):
                    raise RuntimeError("the game window did not accept the console message")
                deadline = time.monotonic() + deadline_each
                while time.monotonic() < deadline:
                    if response.exists():
                        result = _read_json(response)
                        if result is not None:
                            return result
                    time.sleep(0.1)
            raise TimeoutError(
                "the client did not answer; check that you are in a map and look at garrysmod/console.log"
            )
        finally:
            for path in (request, response):
                try:
                    path.unlink()
                except OSError:
                    pass


def _read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None  # still being written


def _wrap(body: str, token: str) -> str:
    return f"""local function rpai_main()
{body}
end
local ok, value = xpcall(rpai_main, debug.traceback)
local out = (ok and istable(value)) and value or {{ error = tostring(value) }}
out.ok = ok
out.token = "{token}"
file.CreateDir("rpai")
file.Write("rpai/res_{token}.json", util.TableToJSON(out, true))
"""


def lua_long_string(text: str) -> str:
    level = 1
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[{text}]{eq}]"


HASH_QUERY_BODY = r"""
local Q = util.JSONToTable(%s)
local R = rawget(_G, "RemixMaterial")
local result = { remix = istable(R), materials = {}, tracked = {}, entities = {} }
-- Compiled models (sourcemodel.py) are recognised by their model path.
local models = {}
for _, path in ipairs(Q.models or {}) do models[string.lower(path)] = true end
for _, ent in ipairs(ents.GetAll()) do
  if IsValid(ent) then
    local asset = ent.GetNW2String and ent:GetNW2String("MMDHLAsset", "") or ""
    if asset == "" and ent.GetAsset then
      local ok, value = pcall(ent.GetAsset, ent)
      if ok and isstring(value) then asset = value end
    end
    local model = string.lower(ent:GetModel() or "")
    if asset ~= "" or models[model] then
      result.entities[#result.entities + 1] = { index = ent:EntIndex(), class = ent:GetClass(), asset = asset, model = model }
    end
  end
end
if not istable(R) then return result end

local function add(list, seen, hash)
  if isstring(hash) and hash ~= "" and hash ~= "0x0" and not seen[hash] then
    seen[hash] = true
    list[#list + 1] = hash
  end
end

-- GetTextureHash's first return is a Lua number and cannot hold every
-- 64-bit value; only the string forms are used.
local function hashes(name)
  local list, seen = {}, {}
  if isfunction(R.GetAllTextureHashes) then
    local ok, all = pcall(R.GetAllTextureHashes, name)
    if ok and istable(all) then
      for _, hash in ipairs(all) do add(list, seen, hash) end
    end
  end
  if #list == 0 and isfunction(R.GetTextureHash) then
    local ok, _, hash = pcall(R.GetTextureHash, name)
    if ok then add(list, seen, hash) end
  end
  return list
end

local function base(name)
  local ok, material = pcall(Material, name)
  if not ok or not material or material:IsError() then return "" end
  local texture = material:GetTexture("$basetexture")
  if not texture or texture:IsError() then return "" end
  return string.lower(texture:GetName())
end

for _, name in ipairs(Q.materials) do
  if isfunction(R.TrackMaterial) then pcall(R.TrackMaterial, name) end
  result.materials[#result.materials + 1] = { name = name, base = base(name), hashes = hashes(name) }
end

-- Model Hotloader may draw through runtime materials rather than the VMTs;
-- the tracker knows every material that was actually bound.
if isfunction(R.DumpAllTextureHashes) then
  local wanted = {}
  for _, texture in ipairs(Q.textures) do wanted[string.lower(texture)] = true end
  local ok, all = pcall(R.DumpAllTextureHashes)
  if ok and istable(all) then
    for _, entry in ipairs(all) do
      if isstring(entry.material) then
        local texture = base(entry.material)
        if wanted[texture] then
          result.tracked[#result.tracked + 1] = { material = entry.material, base = texture, hash = entry.hash }
        end
      end
    end
  end
end
return result
"""


def query_remix_hashes(bridge: GameBridge, materials: list[str], textures: list[str], models: list[str] = ()) -> dict:
    payload = json.dumps({"materials": materials, "textures": textures, "models": list(models)}, ensure_ascii=False)
    return bridge.run_client_lua(HASH_QUERY_BODY % lua_long_string(payload), timeout=30.0)
