"""R13-A: locked, isolated PoC sessions with a copy of the field character library: memory phases,
the lag trigger, and first spawns on every route. Ends a running field game first."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time
from ctypes import wintypes

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import poc_session as poc  # noqa: E402
import mmd_reimport_session as r12a  # noqa: E402  (field games, video settings)

REPO = Path(__file__).resolve().parents[2]
POC = poc.DEFAULT_ROOT
LOCK = Path(r'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock')
TASK = 'R13-A'
FIELD_CACHE = Path(r'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r13\field-cache')
FIELD_INDEX = FIELD_CACHE.parent / 'field-cache-files.json'
DATA = POC / 'garrysmod/data'
CACHE = DATA / 'mmd_hotloader'
TOPBR = POC / 'rtx-remix/mods/~gmod_topbr'
SAVES = POC / 'garrysmod/saves'
ICONS = POC / 'garrysmod/materials/spawnicons'  # model panels write the icons they draw here
ADDON = POC / 'garrysmod/addons/mmd_hotloader'
SOURCE_ADDON = REPO / 'packages/model-hotloader/mmd_hotloader'
PROBE = Path(__file__).with_name('mmd_lazy_probe.lua')
# GMod keeps cfg/config.cfg in Steam Cloud: it takes the cloud copy at start and writes the session's
# settings back at its quit, so a PoC session's last settings reach the user's game at its next start.
FIELD_CONFIG = Path(r'H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\cfg\config.cfg')
SETTINGS_BACK = 'r13a_settings_back.cfg'
# PoC data folders that stay where they are: the cache swapped in below, and an old test cache.
KEEP_OUT = {'mmd_hotloader', 'mmd_hotloader.after-evernight-test'}
PHASE = re.compile(r'^R13_PHASE (\S+) (\S+) lua_kb=(\d+) vram=(.*)$')
GB = 1e9


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 22), b''):
            h.update(chunk)
    return h.hexdigest()


def settings_state() -> dict:
    """The field game's config.cfg and the Steam Cloud copies of GMod's (app 4000), read only."""
    state = dict(field=digest(FIELD_CONFIG) if FIELD_CONFIG.is_file() else None, cloud=[])
    steam = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Steam/userdata'
    for path in sorted(steam.glob('*/4000/remote/cfg/config.cfg')) if steam.is_dir() else []:
        state['cloud'].append(dict(path=str(path), sha256=digest(path), modified=path.stat().st_mtime,
                                   same_as_field=digest(path) == state['field']))
    return state


def inside(path: Path, *roots: Path) -> bool:
    path = path.resolve()
    return any(path == r.resolve() or path.is_relative_to(r.resolve()) for r in roots)


def move(source: Path, destination: Path) -> None:
    """Renames on one volume. Only the PoC's swapped folders and this worktree's out may move."""
    allowed = (CACHE, TOPBR, REPO / 'out')
    if not inside(source, *allowed) or not inside(destination, *allowed) or destination.exists():
        raise RuntimeError(f'refused move {source} -> {destination}')
    # A scanner can hold a just-written file for a moment after the game exits (run 05: access
    # denied once, then the same rename succeeded).
    for attempt in range(24):
        try:
            source.rename(destination)
            return
        except PermissionError:
            if attempt == 23:
                raise
            time.sleep(5)


# ---------------------------------------------------------------- the copied library

def pristine(copy: Path, textures: Path | None = None) -> dict:
    """Puts the working copy back to the read-only field cache's files: a changed or missing file is
    copied again, a file a session added is removed. Size and modification time decide (copy2 keeps
    the time), so a clean copy costs only a directory walk. The field cache is never written.
    textures: a folder of the assets' textures/<sha256>.png (the field cache has none; the native
    module reads them to load a character), kept in the copy too."""
    index = {rel: FIELD_CACHE / rel for rel in json.loads(FIELD_INDEX.read_text(encoding='utf-8'))}
    if textures:
        for png in textures.glob('*.png'):
            index['textures/' + png.name] = png
    copied, removed = [], []
    for rel, source in index.items():
        target = copy / rel
        s = source.stat()
        if target.is_file():
            t = target.stat()
            if t.st_size == s.st_size and t.st_mtime_ns == s.st_mtime_ns:
                continue
            target.unlink()
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied.append(rel)
    for p in sorted(copy.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        rel = p.relative_to(copy).as_posix()
        if p.is_file() and rel not in index:
            p.unlink()
            removed.append(rel)
        elif p.is_dir() and not any(p.iterdir()) and not (FIELD_CACHE / rel).is_dir():
            p.rmdir()
    return dict(copied=copied, removed=removed)


def library_plan(copy: Path) -> dict:
    """The library's saved actor registrations (as the server reads them at map start) and its
    characters without one, for choosing test characters."""
    approved = json.loads((copy / 'approved.json').read_text(encoding='utf-8'))
    actors, others = {}, []
    for key, entry in approved.get('rigs', {}).items():
        if entry.get('role') not in ('citizen', 'combine', 'player') or entry.get('asset') not in approved.get('assets', {}):
            continue
        rig_path = copy / 'rigs' / key / 'rig.json'
        if not rig_path.is_file() or not (copy / 'rigs' / key / 'carrier.gma').is_file():
            continue
        rig = json.loads(rig_path.read_text(encoding='utf-8'))
        if rig.get('generator') not in (30, 31):
            continue
        actors.setdefault(entry['asset'], []).append(dict(key=key, role=entry['role'], model=rig.get('model'),
                                                          generator=rig.get('generator'), arms=entry.get('arms')))
    for asset in approved.get('assets', {}):
        if asset not in actors and (copy / 'assets' / asset / 'materials-v5.gma').is_file():
            others.append(asset)
    sizes = {a: (copy / 'assets' / a / 'materials-v5.gma').stat().st_size
             for a in approved.get('assets', {}) if (copy / 'assets' / a / 'materials-v5.gma').is_file()}
    return dict(actors=actors, others=sorted(others), sizes=sizes,
                names={a: e.get('name') for a, e in approved.get('assets', {}).items()})


# ---------------------------------------------------------------- RAM sampler

class MEMORY_COUNTERS(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD), ('PeakWorkingSetSize', ctypes.c_size_t),
                ('WorkingSetSize', ctypes.c_size_t), ('QuotaPeakPagedPoolUsage', ctypes.c_size_t),
                ('QuotaPagedPoolUsage', ctypes.c_size_t), ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t),
                ('QuotaNonPagedPoolUsage', ctypes.c_size_t), ('PagefileUsage', ctypes.c_size_t),
                ('PeakPagefileUsage', ctypes.c_size_t), ('PrivateUsage', ctypes.c_size_t)]


class MEMORYSTATUSEX(ctypes.Structure):
    _fields_ = [('dwLength', wintypes.DWORD), ('dwMemoryLoad', wintypes.DWORD), ('ullTotalPhys', ctypes.c_uint64),
                ('ullAvailPhys', ctypes.c_uint64), ('ullTotalPageFile', ctypes.c_uint64), ('ullAvailPageFile', ctypes.c_uint64),
                ('ullTotalVirtual', ctypes.c_uint64), ('ullAvailVirtual', ctypes.c_uint64),
                ('ullAvailExtendedVirtual', ctypes.c_uint64)]


kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
psapi = ctypes.WinDLL('psapi', use_last_error=True)
kernel32.OpenProcess.restype = wintypes.HANDLE
psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(MEMORY_COUNTERS), wintypes.DWORD]


def memory_of(pid: int):
    handle = kernel32.OpenProcess(0x1000 | 0x0010, False, pid)  # limited query, VM read
    if not handle:
        return None
    try:
        counters = MEMORY_COUNTERS()
        counters.cb = ctypes.sizeof(counters)
        if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return None
        return counters.PrivateUsage, counters.WorkingSetSize, counters.PeakWorkingSetSize
    finally:
        kernel32.CloseHandle(handle)


class Sampler(threading.Thread):
    """Every 2 s: private bytes (commit), working set and peak working set of each PoC gmod.exe, and
    the system's available memory. CSV columns as the main session's ram_sampler.ps1 writes them."""

    def __init__(self, path: Path):
        super().__init__(daemon=True)
        self.path, self.stop_event, self.rows = path, threading.Event(), []

    def run(self):
        with self.path.open('w', encoding='utf-8') as out:
            out.write('utc,pid,role,private_bytes,working_set,peak_working_set,system_available_bytes\n')
            while not self.stop_event.is_set():
                status = MEMORYSTATUSEX()
                status.dwLength = ctypes.sizeof(status)
                kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
                stamp = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
                pids = poc.game_processes(POC)
                parents = poc.process_parents()
                for pid in pids:
                    counters = memory_of(pid)
                    if not counters:
                        continue
                    role = 'helper' if parents.get(pid) in pids else 'game'
                    out.write(f'{stamp},{pid},{role},{counters[0]},{counters[1]},{counters[2]},{status.ullAvailPhys}\n')
                    if role == 'game':
                        self.rows.append((time.time(), counters[0], counters[1]))
                out.flush()
                self.stop_event.wait(2)

    def latest(self):
        return self.rows[-1] if self.rows else (0, 0, 0)


# ---------------------------------------------------------------- the session

class Session:
    def __init__(self, args):
        self.args = args
        self.out = args.out
        self.log = POC / 'garrysmod/console.log'
        self.events, self.phases, self.errors = [], [], set()
        self.session = None
        self.restored = True
        self.sampler = None

    # -- console and markers
    def window(self):
        for pid in poc.game_processes(POC):
            hwnd = poc.game_window(pid)
            if hwnd and not poc.window_hung(hwnd):
                return hwnd
        return None

    def text(self, offset=0):
        # The console log ends its lines with CR LF; patterns here end at the line's text.
        return poc.read_shared(self.log, offset).replace('\r', '')

    def size(self):
        return self.log.stat().st_size if self.log.exists() else 0

    def wait(self, pattern, offset=0, timeout=300, count=1):
        expression = re.compile(pattern, re.M)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = self.text(offset)
            found = expression.findall(text)
            if len(found) >= count:
                return found[count - 1]
            for line in text.splitlines():
                if line.startswith('R13A_ERROR') and line not in self.errors:
                    self.errors.add(line)
                    self.events.append(dict(error=line))
                    print(line, flush=True)
            if self.session and self.session.poll() is not None:
                raise RuntimeError('owning PoC session ended while waiting for ' + pattern)
            time.sleep(.25)
        raise RuntimeError('timeout: ' + pattern)

    def send(self, command):
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            hwnd = self.window()
            if hwnd and poc.console(hwnd, command):
                return
            if self.session and self.session.poll() is not None:
                raise RuntimeError('owning PoC session ended')
            time.sleep(.25)
        raise RuntimeError('console delivery failed: ' + command)

    def lua(self, code, server=False):
        for command in poc.client_lua_lines('r13_a', code):
            self.send(command.replace('lua_run_cl ', 'lua_run ', 1) if server else command)

    def call(self, code, marker, server=False, timeout=120):
        at = self.size()
        self.lua(code, server)
        value = self.wait('^' + re.escape(marker) + r' ?(.*)$', at, timeout)
        return value

    def json_call(self, code, marker, server=False, timeout=120):
        value = self.call(code, marker, server, timeout)
        return json.loads(value) if value else None

    def quiet(self, seconds=5, limit=180):
        last, steady = None, time.monotonic()
        deadline = steady + limit
        while time.monotonic() < deadline:
            size = self.size()
            if size != last:
                last, steady = size, time.monotonic()
            if time.monotonic() - steady >= seconds and self.window():
                return True
            if self.session and self.session.poll() is not None:
                raise RuntimeError('owning session ended while waiting for quiet')
            time.sleep(.25)
        return False

    def wait_workshop(self, timeout):
        """As poc_session: Workshop add-ons mount twice at start (before and after Steam lists the
        subscriptions). Ready at the second mount, a first that mounted all or none, or a partial
        first with no remount within 20 s. A map asked for before that waits on the fetch."""
        deadline, first = time.monotonic() + timeout, None
        while time.monotonic() < deadline:
            text = self.text()
            found = poc.WORKSHOP_MOUNTED.findall(text)
            if found and first is None:
                first = time.monotonic()
            if len(found) >= 2:
                return 'the remount'
            if found:
                mounted, total = int(found[0][0]), int(found[0][1])
                if not total or mounted >= total:
                    return 'a complete first mount'
                if mounted and not poc.WORKSHOP_REMOUNTING.search(text) and time.monotonic() - first >= poc.PARTIAL_MOUNT_GRACE:
                    return 'a partial first mount'
            if self.session and self.session.poll() is not None:
                raise RuntimeError('owning PoC session ended before the Workshop mount')
            time.sleep(.5)
        raise RuntimeError('the Workshop add-ons never finished mounting')

    def shot(self, label):
        self.send('hideconsole')
        time.sleep(1)
        hwnd = self.window()
        if not hwnd:
            raise RuntimeError('no responsive PoC window for a screenshot')
        done, shots = threading.Event(), []

        def capture():
            try:
                shots.append(poc.capture_window(hwnd))
            finally:
                done.set()
        threading.Thread(target=capture, daemon=True).start()
        if not done.wait(poc.SCREENSHOT_TIMEOUT) or not shots:
            raise RuntimeError('screenshot failed or timed out')
        image, details = shots[0]
        if details['method'] != 'PrintWindow':
            raise RuntimeError('refusing an occluded screen-grab fallback')
        image.save(self.out / f'{label}.png')
        self.events.append(dict(screenshot=f'{label}.png', **details))

    # -- probe
    def inject(self):
        code = PROBE.read_text(encoding='utf-8')
        at = self.size()
        self.lua(code, True)
        self.lua(code, False)
        self.wait(r'^R13A_INSTALLED server', at, 90)
        self.wait(r'^R13A_INSTALLED client', at, 90)
        self.lua('R13A.Watch()')

    def action(self, name):
        """Names what comes next in both realms: mounts, precaches and texture jumps carry it."""
        self.lua(f'R13A.Action({json.dumps(name)})', True)
        self.lua(f'R13A.Action({json.dumps(name)})')

    def phase(self, name):
        at = self.size()
        self.lua(f'R13A.ServerCensus({json.dumps(name)})', True)
        self.lua(f'R13A.Phase({json.dumps(name)})', False)
        line = self.wait(r'^(R13_PHASE ' + re.escape(name) + r' .*)$', at, 60)
        server = json.loads(self.wait(r'^R13A_CENSUS (\{.*"realm":"server".*\})$', at, 60))
        client = json.loads(self.wait(r'^R13A_CENSUS (\{.*"realm":"client".*\})$', at, 60))
        match = PHASE.match(line)
        vram = json.loads(match.group(4)) if match and match.group(4).startswith('{') else {}
        time.sleep(2.5)  # the sampler's next row
        _, private, working = self.sampler.latest() if self.sampler else (0, 0, 0)
        record = dict(phase=name, utc=match.group(2) if match else None, app_textures=vram.get('usedAppTextureBytes'),
                      replacement=vram.get('usedMaterialTextureBytes'), dxvk_used=vram.get('totalUsedBytes'),
                      driver=vram.get('driverAllocatedBytes'), private=private, working_set=working,
                      server=server, client=client)
        self.phases.append(record)
        poc.write_json(self.out / 'phases.json', self.phases)
        print(f"PHASE {name:28} app {(record['app_textures'] or 0) / GB:6.2f} GB  private {private / GB:6.2f} GB  "
              f"working {working / GB:6.2f} GB  loaded {server.get('loaded')}/{server.get('registrations')} "
              f"client loaded {client.get('loaded')}/{client.get('registrations')}", flush=True)
        return record

    def step(self, name, code=None, server=False, settle=15):
        if code:
            self.action(name)
            self.lua(code, server)
        time.sleep(settle)
        return self.phase(name)

    def entries(self):
        at = self.size()
        self.lua('R13A.Entries()')
        count = int(self.wait(r'^R13A_ENTRIES_DONE (\d+)$', at, 60))
        lines = re.findall(r'^R13A_ENTRY (\{.*\})$', self.text(at), re.M)
        assert len(lines) == count, (len(lines), count)
        return [json.loads(line) for line in lines]

    def presented(self, label, timeout=100):
        """The spawn's R13A_PRESENTED; a spawn that never presents is recorded and the sequence goes on."""
        try:
            value = json.loads(self.wait(r'^R13A_PRESENTED (\{.*"label":"' + re.escape(label) + r'".*\})$', self.mark, timeout))
        except RuntimeError as error:
            if self.session and self.session.poll() is not None:
                raise
            self.events.append(dict(not_presented=label, error=str(error)))
            print('NOT PRESENTED', label, flush=True)
            return None
        self.events.append(dict(presented=value))
        print('PRESENTED', label, value.get('ms'), 'ms', flush=True)
        return value

    def spawn(self, label, asset, role, view=True, extra=None):
        self.action(label)
        self.mark = self.size()
        self.lua('R13A.Spawn(%s,%s,%s,%s)' % (json.dumps(asset), json.dumps(role), json.dumps(label),
                                               'util.JSONToTable(%s)' % json.dumps(json.dumps(extra)) if extra else 'nil'))
        value = self.presented(label)
        spawned = re.findall(r'^R13A_SPAWN (\{.*"label":"' + re.escape(label) + r'".*\})$', self.text(self.mark), re.M)
        if spawned:
            self.events.append(dict(spawn=json.loads(spawned[-1])))
        self.inspect(label, value, view)
        return value

    def inspect(self, label, value, view):
        """The presented entity's server facts, and a screenshot of it."""
        if not value:
            self.lua(f'R13A.InspectMMD({json.dumps(label)})', True)
            return
        self.lua(f'R13A.Inspect({value["index"]},{json.dumps(label)})', True)
        if view:
            self.lua(f'R13A.View({value["index"]})')
            time.sleep(4)
            self.shot(label)
            self.lua('R13A.ResetView()')

    def npc_tab_spawn(self, label, entry, view=True):
        self.lua('R13A.Aim(30)', True)
        self.action(label)
        time.sleep(.5)
        self.mark = self.size()
        self.lua('R13A.NPCTabSpawn(%s,%s,%s)' % (json.dumps(entry['key']), json.dumps(entry['asset']), json.dumps(label)))
        value = self.presented(label)
        self.inspect(label, value, view)
        return value

    def player_model(self, label, entry, view=True):
        self.action(label)
        self.mark = self.size()
        self.lua('R13A.ChoosePlayerModel(%s,%s,%s)' % (json.dumps(entry['key']), json.dumps(entry['model']), json.dumps(label)))
        time.sleep(1)
        self.lua('R13A.WaitPlayer()')
        self.lua('R13A.RespawnPlayer()', True)
        value = self.presented(label)
        self.inspect(label, value, view)
        return value

    def change_map(self, name):
        at = self.size()
        self.send(f'map {name}')
        self.wait(r'^Clientside Lua startup!\s*$', at, 600)
        self.quiet(8, 240)
        self.inject()

    # -- sequences
    def seq_trigger(self):
        """The trigger the reproduction found (a hotloader spawn that made a new fit and published it),
        split up and traced on the clock both realms share: a plain Combine soldier, a character
        with no saved entry spawned as a citizen (a new fit and a new citizen entry), then a saved
        character spawned as a Combine soldier (a new fit and a new entry of another role)."""
        plan = self.plan
        self.inject()
        self.lua('R13A.CloseWindows()')
        self.step('idle', settle=self.args.idle)
        listed = self.entries()
        poc.write_json(self.out / 'entries.json', listed)
        # The menus as a player sees them, with what they load (nothing, for a saved character).
        self.step('npc-tab', 'R13A.NPCTab()', settle=8)
        self.shot('menu-npc-tab')
        self.lua('R13A.CloseMenu()')
        self.step('player-models', 'R13A.PlayerModels()', settle=8)
        self.shot('menu-player-models')
        self.lua('R13A.CloseWindows()')
        self.lua('R13A.TraceServer()', True)
        self.lua('R13A.Trace()')
        self.lua('R13A.Aim(30)', True)
        self.step('combine-plain', 'R13A.SpawnClassic("npc_combine_s","combine-plain")', settle=20)
        self.lua('R13A.RemoveClass("npc_combine_s") R13A.EnsureAlive()', True)
        self.step('after-combine-plain', settle=10)
        if plan['others']:
            self.spawn('new-fit-citizen', plan['others'][0], 'citizen', extra={'gender': 'female'})
            self.step('after-new-fit-citizen', settle=15)
        registered = [a for a in plan['actors'] if not any(e['asset'] == a and e['role'] == 'combine' for e in listed)]
        if registered:
            self.spawn('new-fit-combine', registered[-1], 'combine', extra={'gender': 'female'})
            self.step('after-new-fit-combine', settle=15)

    def seq_combine(self):
        """Which part of a first Combine soldier makes every loaded texture GPU-resident: what its
        class precaches (the Combine faction, the AR2, the frag grenade, items), one at a time and
        stock only, then the soldier itself. After the first jump the rest cannot show another."""
        self.inject()
        self.lua('R13A.CloseWindows()')
        self.step('idle', settle=self.args.idle)
        self.lua('R13A.Aim(30)', True)
        parts = [('metropolice', 'gmod_spawnnpc npc_metropolice none', 'npc_metropolice'),
                 ('citizen-ar2', 'gmod_spawnnpc npc_citizen weapon_ar2', 'npc_citizen'),
                 ('weapon-frag', 'gm_spawnswep weapon_frag', 'weapon_frag'),
                 ('item-healthvial', 'gm_spawnsent item_healthvial', 'item_healthvial'),
                 ('item-ar2-altfire', 'gm_spawnsent item_ammo_ar2_altfire', 'item_ammo_ar2_altfire'),
                 ('combine-unarmed', 'gmod_spawnnpc npc_combine_s none', 'npc_combine_s')]
        for label, command, cls in parts:
            self.action(label)
            self.send(command)
            self.step(label, settle=12)
            self.lua(f'R13A.RemoveClass({json.dumps(cls)}) R13A.EnsureAlive()', True)

    def seq_ammo(self):
        """The part `combine` found (HL2's AR2 alt-fire ammo item, which every Combine soldier
        precaches), split: its particle system precache, then its model precache, then the item."""
        self.inject()
        self.lua('R13A.CloseWindows()')
        self.step('idle', settle=self.args.idle)
        self.lua('R13A.Aim(30)', True)
        parts = [('particle-combineball', 'PrecacheParticleSystem("combineball") print("R13A_PRECACHED particle")'),
                 ('model-ammo', 'util.PrecacheModel("models/items/combine_rifle_ammo01.mdl") print("R13A_PRECACHED model")')]
        for label, code in parts:
            self.action(label)
            self.lua(code, True)
            self.step(label, settle=12)
        self.action('item-ar2-altfire')
        self.send('gm_spawnsent item_ammo_ar2_altfire')
        self.step('item-ar2-altfire', settle=12)
        self.lua('R13A.RemoveClass("item_ammo_ar2_altfire")', True)

    def seq_reproduce(self):
        """Every candidate action of the lag report, one at a time, with a phase after each."""
        plan = self.plan
        self.inject()
        self.lua('R13A.CloseWindows()')
        self.step('idle', settle=self.args.idle)
        self.step('catalog', 'R13A.Catalog()', server=True)
        listed = self.entries()
        poc.write_json(self.out / 'entries.json', listed)
        preview = listed[0]['asset'] if listed else None
        self.step('library-preview', f'R13A.Library({json.dumps(preview)})')
        self.lua('R13A.CloseWindows()')
        self.step('npc-tab', 'R13A.NPCTab()', settle=12)
        self.lua('R13A.CloseMenu()')
        self.step('player-models', 'R13A.PlayerModels()', settle=15)
        self.lua('R13A.CloseWindows()')
        citizens = [e for e in listed if e['role'] == 'citizen']
        players = [e for e in listed if e['role'] == 'player']
        if citizens:
            self.npc_tab_spawn('npc-tab-registered', citizens[len(citizens) // 2])
            self.step('after-npc-tab-spawn', settle=10)
        if players:
            # The field's player wore a character: give the player a saved player model.
            self.player_model('player-model-registered', players[len(players) // 2])
            self.step('after-player-model', settle=10)
        # A manhack from the NPC tab, left to attack (the field: the player was killed or hurt).
        self.lua('R13A.Aim(30)', True)
        self.step('manhack', 'R13A.SpawnClassic("npc_manhack","manhack")', settle=25)
        self.lua('R13A.RemoveClass("npc_manhack") R13A.EnsureAlive()', True)
        self.step('after-manhack', settle=10)
        if len(plan['others']) > 1:
            path = f"data/mmd_hotloader/assets/{plan['others'][1]}/materials-v5.gma"
            self.step('mount-unregistered-archive', f'R13A.Mount({json.dumps(path)})', server=True)
        if plan['others']:
            self.spawn('ragdoll-unregistered', plan['others'][0], 'ragdoll')
            self.step('after-ragdoll-unregistered', settle=10)
        registered = [a for a in plan['actors'] if not any(e['asset'] == a and e['role'] == 'combine' for e in listed)]
        if registered:
            self.spawn('new-fit-combine', registered[-1], 'combine', extra={'gender': 'female'})
            self.step('after-new-fit', settle=10)
        self.step('end', settle=5)
        # The field wrote what a map start writes (names/assets, approved.json) right before the jump.
        self.lua('R13A.RemoveMMD()', True)
        self.change_map('gm_flatgrass')
        self.lua('R13A.CloseWindows()')
        self.step('map-change', settle=30)
        self.change_map('gm_flatgrass')
        self.lua('R13A.CloseWindows()')
        self.step('map-reload', settle=30)
        # Last, as they may make everything resident: what a Workshop remount or a settings change
        # does to the material system (a reload of every material, then of every texture).
        self.send('sv_cheats 1')
        self.action('mat-reloadallmaterials')
        self.send('mat_reloadallmaterials')
        self.quiet(8, 240)
        self.step('mat-reloadallmaterials', settle=15)
        self.action('mat-reloadtextures')
        self.send('mat_reloadtextures')
        self.quiet(8, 240)
        self.step('mat-reloadtextures', settle=15)

    def pick(self, listed):
        """The same test characters for every build: by the native module's last-use records
        (names/rigs times, what the ready set falls back to), the newest character with a citizen
        entry, and the oldest ones for cold first spawns."""
        times = {}
        for asset, rigs in self.plan['actors'].items():
            keys = [r['key'] for r in rigs] + [r['arms'] for r in rigs if r.get('arms')]
            stamps = [(CACHE / 'names/rigs' / (key[:16] + '.json')) for key in keys]
            times[asset] = max([p.stat().st_mtime for p in stamps if p.exists()] or [0])
        citizens = sorted((e for e in listed if e['role'] == 'citizen'), key=lambda e: (times.get(e['asset'], 0), e['rig']))
        players = sorted((e for e in listed if e['role'] == 'player'), key=lambda e: (times.get(e['asset'], 0), e['rig']))
        byAsset = {}
        for e in citizens:
            byAsset.setdefault(e['asset'], e)
        order = sorted(byAsset.values(), key=lambda e: (times.get(e['asset'], 0), e['rig']))
        picks = dict(ready=order[-1], cold=order[0], menu=order[1], ragdoll=order[2], map2=order[3],
                     player=next((p for p in players if p['asset'] not in {order[0]['asset'], order[1]['asset'], order[2]['asset'], order[3]['asset']}), None))
        poc.write_json(self.out / 'picks.json', dict(picks=picks, times=times))
        return picks

    def seq_measure(self):
        """Idle memory, then first spawns timed on every route, removal, a save, a map change."""
        self.inject()
        self.lua('R13A.CloseWindows()')
        self.step('idle', settle=self.args.idle)
        self.step('idle-late', settle=30)
        listed = self.entries()
        poc.write_json(self.out / 'entries.json', listed)
        picks = self.pick(listed)
        self.npc_tab_spawn('npc-tab-ready', picks['ready'])
        self.step('after-ready', settle=8)
        cold = self.npc_tab_spawn('npc-tab-cold', picks['cold'])
        self.step('after-cold', settle=8)
        self.spawn('menu-npc-cold', picks['menu']['asset'], 'citizen')
        self.spawn('menu-ragdoll-cold', picks['ragdoll']['asset'], 'ragdoll')
        if picks['player']:
            self.player_model('player-model-cold', picks['player'])
            self.step('after-player-model', settle=8)
        if cold:
            self.action('dupe')
            self.lua(f'R13A.Dupe({cold["index"]})', True)
            time.sleep(3)
        self.step('after-spawns', settle=5)
        self.lua('R13A.InspectMMD("before-save")', True)
        self.save_and_load()
        self.lua('R13A.RemoveMMD()', True)
        self.step('removed', settle=10)
        # What still holds the removed characters: the fixes' manual purge uncaches every Source
        # material (their textures go until something draws them again) and asks Remix to clean up.
        self.action('rtx-flush-textures')
        self.send('rtx_flush_textures')
        self.quiet(5, 120)
        self.step('after-flush', settle=15)
        if picks['player']:
            self.lua('RunConsoleCommand("cl_playermodel","kleiner")')
            time.sleep(1)
            self.lua('R13A.RespawnPlayer()', True)
        self.change_map('gm_flatgrass')
        self.lua('R13A.CloseWindows()')
        self.step('map2-idle', settle=20)
        self.npc_tab_spawn('map2-npc-tab-cold', picks['map2'])
        self.lua('R13A.ErrorModels()')
        self.step('map2-after-spawn', settle=8)

    def save_and_load(self):
        """A save made now, loaded at once: the saved characters come back on the reloaded map."""
        before = {p for p in SAVES.rglob('*.gms')} if SAVES.is_dir() else set()
        self.action('save')
        self.send('gm_save')
        deadline, made = time.monotonic() + 60, None
        while time.monotonic() < deadline and not made:
            new = [p for p in SAVES.rglob('*.gms') if p not in before] if SAVES.is_dir() else []
            made = max(new, key=lambda p: p.stat().st_mtime) if new else None
            time.sleep(.5)
        if not made:
            self.events.append(dict(save='no save file appeared'))
            return
        time.sleep(2)
        at = self.size()
        relative = made.relative_to(POC / 'garrysmod').as_posix()
        self.events.append(dict(save=relative))
        self.action('load-save')
        self.send(f'gm_load "{relative}"')
        # A save of the current map is restored in place (GMod cleans the map up and pastes the
        # saved entities); another map loads first, with new Lua states.
        time.sleep(10)
        self.quiet(8, 240)
        if re.search(r'^Clientside Lua startup!\s*$', self.text(at), re.M):
            self.quiet(8, 240)
            self.inject()
        time.sleep(5)
        self.lua('R13A.InspectMMD("loaded-save")', True)
        self.lua('R13A.ErrorModels()')
        self.step('loaded-save', settle=10)

    def seq_integrated(self):
        """R13's integrated check of one memory profile: idle memory, the newest character and the
        oldest one from the NPC tab, their removal, then the lag report's trigger (a plain Combine
        soldier), the runtime's release after it, and the same two characters again."""
        self.inject()
        self.lua('R13A.CloseWindows()')
        self.step('idle', settle=self.args.idle)
        self.step('idle-late', settle=30)
        listed = self.entries()
        poc.write_json(self.out / 'entries.json', listed)
        picks = self.pick(listed)
        self.npc_tab_spawn('npc-tab-newest', picks['ready'])
        self.step('after-newest', settle=8)
        self.npc_tab_spawn('npc-tab-oldest', picks['cold'])
        # Two more, so the minimum profile's 2 GiB of game textures is exceeded and released later.
        self.npc_tab_spawn('npc-tab-third', picks['menu'])
        self.npc_tab_spawn('npc-tab-fourth', picks['ragdoll'])
        self.step('characters', settle=20)
        self.lua('R13A.RemoveMMD()', True)
        self.step('removed', settle=10)
        self.lua('R13A.Aim(30)', True)
        self.step('combine-plain', 'R13A.SpawnClassic("npc_combine_s","combine-plain")', settle=15)
        self.lua('R13A.RemoveClass("npc_combine_s") R13A.EnsureAlive()', True)
        self.step('trigger-30s', settle=15)
        self.step('trigger-90s', settle=60)
        self.step('trigger-150s', settle=60)
        self.npc_tab_spawn('npc-tab-newest-again', picks['ready'])
        self.npc_tab_spawn('npc-tab-oldest-again', picks['cold'])
        self.lua('R13A.ErrorModels()')
        self.step('characters-again', settle=20)

    def seq_idle(self):
        """Idle memory only: registrations at map start, nothing spawned."""
        self.inject()
        self.lua('R13A.CloseWindows()')
        self.step('idle', settle=self.args.idle)
        poc.write_json(self.out / 'entries.json', self.entries())
        self.step('idle-late', settle=30)

    # -- the hold
    def stage_lua(self):
        """Copies the worktree's hotloader files that differ from the deployed ones into the PoC addon,
        at the main menu (the loader has deployed; no game Lua realm exists yet)."""
        backups, created = self.out / 'lua-before', []
        changed = []
        # Lua only: the part stores its binaries as .xz for Git LFS, deployed decompressed.
        for source in sorted((SOURCE_ADDON / 'lua').rglob('*.lua')):
            if not source.is_file():
                continue
            rel = source.relative_to(SOURCE_ADDON)
            target = ADDON / rel
            if target.is_file() and digest(target) == digest(source):
                continue
            if target.is_file():
                (backups / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backups / rel)
            else:
                created.append(rel.as_posix())
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            changed.append(rel.as_posix())
        self.staged = dict(changed=changed, created=created)
        poc.write_json(self.out / 'staged.json', self.staged)
        print('STAGED', len(changed), 'files', flush=True)

    def unstage_lua(self):
        staged = getattr(self, 'staged', None)
        if not staged:
            return
        backups = self.out / 'lua-before'
        for rel in staged['changed']:
            target = ADDON / rel
            if rel in staged['created']:
                if target.exists():
                    target.unlink()
                continue
            shutil.copy2(backups / rel, target)
            assert digest(target) == digest(backups / rel), rel
        self.unstaged, self.staged = staged, None

    def inject_memory(self):
        """Stands in for R13-C's loader: activation.memory in this session's status.json."""
        path = DATA / 'native-loader/status.json'
        status = json.loads(path.read_text(encoding='utf-8'))
        memory = status.setdefault('activation', {}).setdefault('memory', {})
        text = self.args.status_memory
        if text.lstrip().startswith('{'):
            memory.update(json.loads(text))
        else:  # profile=minimum,warm_characters=0 (no quotes to lose on a command line)
            for pair in filter(None, text.split(',')):
                key, value = pair.split('=', 1)
                memory[key.strip()] = int(value) if value.strip().lstrip('-').isdigit() else value.strip()
        path.write_text(json.dumps(status, indent=2), encoding='utf-8')
        self.events.append(dict(status_memory=memory))

    def settings_back(self):
        """Ends the session with the user's own settings. GMod writes config.cfg to Steam Cloud at its
        quit and the user's game takes that copy at its next start, so the player-model steps
        (cl_playermodel) and other drivers' settings (fps_max) would reach the field game. The field
        game's own last config.cfg is read (never written) and executed from a copy in the PoC's cfg
        folder, removed again; the quit then writes those values."""
        if not FIELD_CONFIG.is_file():
            self.events.append(dict(settings_back='no field config.cfg'))
            return
        copy = POC / 'garrysmod/cfg' / SETTINGS_BACK
        shutil.copyfile(FIELD_CONFIG, copy)
        try:
            self.send('exec ' + SETTINGS_BACK)
            time.sleep(3)
            self.send('host_writeconfig')
            time.sleep(3)
        finally:
            copy.unlink(missing_ok=True)
        self.events.append(dict(settings_back=digest(FIELD_CONFIG)))

    def snapshot_rest(self):
        """The PoC's other data folders, copied (empty folders too) so they can be put back exactly."""
        folder, records = self.out / 'data-before', {}
        folder.mkdir()
        for top in DATA.iterdir():
            if top.name in KEEP_OUT:
                continue
            for p in ([top] if top.is_file() else [top, *top.rglob('*')]):
                rel = p.relative_to(DATA).as_posix()
                target = folder / rel
                if p.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                elif p.is_file():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(p, target)
                    records[rel] = digest(p)
        poc.write_json(self.out / 'data-before.json', records)
        return records

    def restore_rest(self, records):
        folder, after, changed = self.out / 'data-before', self.out / 'data-after', []
        for top in DATA.iterdir():
            if top.name in KEEP_OUT:
                continue
            for p in sorted(([top] if top.is_file() else top.rglob('*')), key=lambda p: len(p.parts), reverse=True):
                rel = p.relative_to(DATA).as_posix()
                if p.is_file():
                    value = digest(p)
                    if records.get(rel) == value:
                        continue
                    archive = after / rel
                    archive.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(p, archive)
                    if rel in records:
                        shutil.copy2(folder / rel, p)
                    else:
                        p.unlink()
                    changed.append(rel)
                elif p.is_dir() and not any(p.iterdir()) and not (folder / rel).is_dir():
                    p.rmdir()
        for rel, value in records.items():
            p = DATA / rel
            if not p.is_file():
                p.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(folder / rel, p)
            assert digest(p) == value, rel
        return changed

    def run(self):
        args = self.args
        library = args.library
        state = pristine(library, args.textures)
        poc.write_json(self.out / 'library-before.json', state)
        print('library: copied', len(state['copied']), 'removed', len(state['removed']), flush=True)
        self.plan = library_plan(library)
        poc.write_json(self.out / 'plan.json', self.plan)
        field = r12a.end_field_games()
        poc.write_json(self.out / 'field-games.json', field)
        if field['remaining']:
            raise RuntimeError('a field game could not be ended')
        if poc.game_processes(POC):
            raise RuntimeError('the PoC is already running')
        config = POC / 'garrysmod/cfg/config.cfg'
        config_saved = self.out / 'config-before.cfg'
        if config.exists():
            shutil.copy2(config, config_saved)
        poc.write_json(self.out / 'settings-before.json', settings_state())
        registry = r12a.video_settings()
        poc.write_json(self.out / 'video-before.json', registry)
        saves_before = {p.relative_to(POC).as_posix() for p in [SAVES, *SAVES.rglob('*')]} if SAVES.exists() else set()
        icons_before = {p.relative_to(POC).as_posix() for p in [ICONS, *ICONS.rglob('*')]} if ICONS.exists() else set()
        console_saved = self.out / 'console-before.log'
        cache_saved, topbr_saved = self.out / 'poc-mmd_hotloader', self.out / 'poc-topbr'
        self.restored = False
        records = None
        swapped = topbr = False
        try:
            records = self.snapshot_rest()
            if self.log.exists():
                self.log.rename(console_saved)  # never read: this session's log starts empty
            if CACHE.exists():
                move(CACHE, cache_saved)
            move(library, CACHE)
            swapped = True
            if TOPBR.exists():
                move(TOPBR, topbr_saved)
            TOPBR.mkdir(parents=True)
            topbr = True
            field = r12a.end_field_games()
            poc.write_json(self.out / 'field-games-at-launch.json', field)
            if field['remaining']:
                raise RuntimeError('a field game could not be ended')
            # Two launches right after another game's exit crashed at the menu in the NVIDIA driver
            # (nvoglv64.dll+0xe622f8, as R12-C's 07 control): give the driver a moment first.
            time.sleep(args.cooldown)
            self.sampler = Sampler(self.out / 'ram.csv')
            self.sampler.start()
            env = dict(os.environ, TEMP=str(REPO / 'out/tmp'), TMP=str(REPO / 'out/tmp'))
            command = [sys.executable, str(REPO / 'tools/poc_session.py'), '--evidence', str(self.out),
                       'run', '--name', 'game', '--addons', '--map', '', '--settle', '0', '--screenshots', '0',
                       '--lua-shots', '5400', '--timeout', '900', '--hang-grace', '900', '--quit-timeout', '180',
                       '--width', str(args.width), '--height', str(args.height), '--players', str(args.players)]
            if args.workshop:
                command += ['--workshop']
            command += [f'--extra={extra}' for extra in args.extra]
            with (self.out / 'owner.log').open('w', encoding='utf8') as output:
                self.session = subprocess.Popen(command, cwd=REPO, env=env, stdout=output, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 300
                while not self.window():
                    if time.monotonic() > deadline or self.session.poll() is not None:
                        raise RuntimeError('the game did not reach its main menu')
                    time.sleep(.25)
                if args.workshop:
                    self.events.append(dict(workshop=self.wait_workshop(600)))
                self.quiet(5, 300)
                if 'Clientside Lua startup!' in self.text():
                    raise RuntimeError('a game Lua realm started before staging')
                if args.candidate:
                    self.stage_lua()
                if args.status_memory:
                    self.inject_memory()
                for line in args.console:
                    self.send(line)
                at = self.size()
                self.send(f'map {args.map}')
                self.wait(r'^Clientside Lua startup!\s*$', at, 900)
                self.quiet(8, 300)
                getattr(self, 'seq_' + args.sequence)()
        finally:
            try:
                if self.session and self.session.poll() is None:
                    try:
                        self.settings_back()
                    except (RuntimeError, OSError) as error:
                        self.events.append(dict(settings_back_failed=str(error)))
                    try:
                        self.lua('print("NL_SHOT_DONE")')
                    except RuntimeError:
                        try:
                            self.send('quit')
                        except RuntimeError:
                            pass
                    self.session.wait(timeout=300)
            finally:
                if self.sampler:
                    self.sampler.stop_event.set()
                    self.sampler.join(10)
            if poc.game_processes(POC):
                raise RuntimeError('the PoC still runs; snapshot and lock kept for recovery')
            self.unstage_lua()
            if swapped:
                move(CACHE, library)
            if cache_saved.exists():
                move(cache_saved, CACHE)
            if topbr:
                if TOPBR.exists():
                    move(TOPBR, self.out / 'topbr-after')
                if topbr_saved.exists():
                    move(topbr_saved, TOPBR)
            changed = self.restore_rest(records) if records is not None else None
            if SAVES.is_dir():
                # Saves (and their folders) this session made.
                for p in sorted([SAVES, *SAVES.rglob('*')], key=lambda p: len(p.parts), reverse=True):
                    rel = p.relative_to(POC).as_posix()
                    if rel in saves_before:
                        continue
                    if p.is_file():
                        archive = self.out / 'saves-after' / rel
                        archive.parent.mkdir(parents=True, exist_ok=True)
                        shutil.move(str(p), str(archive))
                    elif p.is_dir() and not any(p.iterdir()):
                        p.rmdir()
            if ICONS.exists():
                # Icons this session's menus drew (files first, then folders it created).
                for p in sorted([ICONS, *ICONS.rglob('*')], key=lambda p: len(p.parts), reverse=True):
                    rel = p.relative_to(POC).as_posix()
                    if rel in icons_before:
                        continue
                    if p.is_file():
                        archive = self.out / 'icons-after' / rel
                        archive.parent.mkdir(parents=True, exist_ok=True)
                        shutil.move(str(p), str(archive))
                    elif p.is_dir() and not any(p.iterdir()):
                        p.rmdir()
            if config_saved.exists():
                shutil.copy2(config_saved, config)
                assert digest(config) == digest(config_saved)
            poc.write_json(self.out / 'settings.json', settings_state())
            r12a.restore_video_settings(registry)
            if self.log.exists():
                self.log.rename(self.out / 'console-after.log')
            if console_saved.exists():
                console_saved.rename(self.log)
            state = pristine(library, self.args.textures)
            poc.write_json(self.out / 'library-after.json', state)
            print('library: copied', len(state['copied']), 'removed', len(state['removed']), flush=True)
            poc.write_json(self.out / 'events.json', self.events)
            poc.write_json(self.out / 'restored.json', dict(data_changed=changed, lua=getattr(self, 'unstaged', None),
                                                            cache_swapped_back=CACHE.exists(), finished=poc.now()))
            self.restored = True
            if self.session:
                history = json.loads((self.out / 'session.json').read_text(encoding='utf8'))
                if self.session.returncode or not history[-1].get('normal_quit'):
                    raise RuntimeError('the owning session did not quit normally; see session.json')


def take_lock(out: Path, wait_minutes: float):
    deadline = time.monotonic() + wait_minutes * 60
    while True:
        try:
            with LOCK.open('x', encoding='utf8') as handle:
                json.dump(dict(task=TASK, pid=os.getpid(), time=poc.now(), evidence=str(out)), handle)
            return True
        except FileExistsError:
            if time.monotonic() > deadline:
                return False
            print('PoC lock held by another task; retrying in two minutes', flush=True)
            time.sleep(120)


def main():
    ctypes.windll.user32.SetProcessDPIAware()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--library', type=Path, required=True, help='the working copy of the field cache, in this worktree/out')
    ap.add_argument('--textures', type=Path, help="a folder of the assets' textures/<sha256>.png kept in the copy")
    ap.add_argument('--sequence', default='idle')
    ap.add_argument('--candidate', action='store_true', help="stage this worktree's hotloader Lua at the main menu")
    ap.add_argument('--status-memory', help='JSON merged into status.json activation.memory before the map')
    ap.add_argument('--console', action='append', default=[], help='console command before the map (repeatable)')
    ap.add_argument('--map', default='gm_construct')
    ap.add_argument('--idle', type=float, default=60)
    ap.add_argument('--width', type=int, default=1920)
    ap.add_argument('--height', type=int, default=1080)
    ap.add_argument('--players', type=int, default=1)
    ap.add_argument('--workshop', action='store_true')
    ap.add_argument('--lock-wait', type=float, default=120, help='minutes to wait for the PoC lock')
    ap.add_argument('--cooldown', type=float, default=45, help='seconds to wait before the launch')
    ap.add_argument('--extra', action='append', default=[], help='an extra launch option for the game, such as -insecure (repeatable)')
    args = ap.parse_args()
    args.out, args.library = args.out.resolve(), args.library.resolve()
    args.textures = args.textures.resolve() if args.textures else None
    if not inside(args.out, REPO / 'out') or not inside(args.library, REPO / 'out') or \
            (args.textures and not inside(args.textures, REPO / 'out')):
        ap.error('evidence, the library copy and its textures must be inside this worktree/out')
    if args.out.exists() or not (args.library / 'approved.json').is_file():
        ap.error('evidence must be new and the library copy must exist')
    if not hasattr(Session, 'seq_' + args.sequence):
        ap.error('unknown sequence ' + args.sequence)
    args.out.mkdir(parents=True)
    if not take_lock(args.out, args.lock_wait):
        print('PoC lock still held; nothing was changed', flush=True)
        return 3
    session = Session(args)
    try:
        session.run()
    finally:
        if session.restored and not poc.game_processes(POC):
            owner = json.loads(LOCK.read_text(encoding='utf8'))
            if owner.get('pid') == os.getpid() and owner.get('task') == TASK:
                LOCK.unlink()
                print('lock released', poc.now(), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
