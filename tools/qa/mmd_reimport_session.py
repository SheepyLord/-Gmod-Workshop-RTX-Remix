"""R12-A: isolated, locked PoC delete/reimport readiness probe; ends a running field game first."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
import winreg

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import poc_session as poc

REPO = Path(__file__).resolve().parents[2]
POC = poc.DEFAULT_ROOT
LOCK = Path(r'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock')
TASK = 'R12-A'
VIDEO_SETTINGS = r'Software\Valve\Source\garrysmod\Settings'


def video_settings():
    values = {}
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, VIDEO_SETTINGS) as key:
            index = 0
            while True:
                try:
                    name, data, kind = winreg.EnumValue(key, index)
                except OSError as error:
                    if error.winerror != 259:
                        raise
                    break
                values[name] = (data, kind)
                index += 1
    except FileNotFoundError:
        return None
    return values


def restore_video_settings(before):
    current = video_settings()
    if current == before:
        return
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, VIDEO_SETTINGS) as key:
        for name in (current or {}).keys() - (before or {}).keys():
            winreg.DeleteValue(key, name)
        for name, (data, kind) in (before or {}).items():
            winreg.SetValueEx(key, name, 0, kind, data)
    if before is None:
        winreg.DeleteKey(winreg.HKEY_CURRENT_USER, VIDEO_SETTINGS)
    assert video_settings() == before, 'video registry restoration differs'


def end_field_games():
    """The field game is a test session (the user, 2026-11-02): a running one is ended before a PoC
    launch, never waited for. Asks it to close (WM_CLOSE), then ends what is left after 60 s."""
    field = {pid: poc.process_created(pid) for pid in poc.game_processes(poc.FIELD_ROOT)}
    field = {pid: created for pid, created in field.items() if created is not None}
    record = dict(time=poc.now(), field_pids=sorted(field), forced=[])
    if field:
        for pid in field:
            subprocess.run(['taskkill', '/PID', str(pid)], capture_output=True)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline and set(poc.game_processes(poc.FIELD_ROOT)) & set(field):
            time.sleep(2)
        left = {pid: created for pid, created in field.items() if pid in poc.game_processes(poc.FIELD_ROOT)}
        record['forced'] = poc.terminate(left)
        print(f'ended field gmod.exe {sorted(field)} (forced: {record["forced"]})', flush=True)
    record['remaining'] = poc.game_processes(poc.FIELD_ROOT)
    return record


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_move(source, destination):
    """Only the explicitly named PoC generated directories and worktree out may move."""
    source, destination = source.resolve(), destination.resolve()
    generated = {(POC / 'garrysmod/data').resolve(), (POC / 'rtx-remix/mods/~gmod_topbr').resolve()}
    allowed = lambda p: p in generated or p.is_relative_to((REPO / 'out').resolve())
    if not allowed(source) or not allowed(destination) or destination.exists():
        raise RuntimeError('refused cache move: ' + str((source, destination)))
    source.rename(destination)


class Probe:
    def __init__(self, out, source, candidate, seed=None, seed_only=False, cold=False):
        self.out, self.source, self.candidate = out, source, candidate
        self.events = []
        self.log = POC / 'garrysmod/console.log'
        self.offset = 0
        self.session = None
        self.restored = True
        self.seed, self.seed_only, self.cold = seed, seed_only, cold

    def window(self):
        for pid in poc.game_processes(POC):
            hwnd = poc.game_window(pid)
            if hwnd and not poc.window_hung(hwnd):
                return hwnd
        return None

    def wait(self, marker, offset=None, timeout=180):
        start = self.offset if offset is None else offset
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for line in poc.read_shared(self.log, start).splitlines():
                if line.startswith(marker):
                    value = line[len(marker):].strip()
                    self.events.append(dict(marker=marker, value=value))
                    print(marker, value, flush=True)
                    return value
                if line.startswith('R12A_ERROR'):
                    raise RuntimeError(line)
            if self.session and self.session.poll() is not None:
                raise RuntimeError('owning PoC session ended before ' + marker)
            time.sleep(.25)
        raise RuntimeError('timeout: ' + marker)

    def send(self, command):
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            hwnd = self.window()
            if hwnd and poc.console(hwnd, command):
                return
            time.sleep(.25)
        raise RuntimeError('console delivery failed')

    def lua(self, code, server=True):
        for command in poc.client_lua_lines('r12_a', code):
            self.send(command.replace('lua_run_cl ', 'lua_run ', 1) if server else command)

    def quiet(self):
        last, steady = None, time.monotonic()
        deadline = steady + 120
        while time.monotonic() < deadline:
            size = self.log.stat().st_size if self.log.exists() else 0
            if size != last:
                last, steady = size, time.monotonic()
            if time.monotonic() - steady >= 5 and self.window():
                return
            if self.session.poll() is not None:
                raise RuntimeError('owning session ended while waiting for map reloads')
            time.sleep(.25)
        raise RuntimeError('map never became quiet/responsive')

    def call(self, code, marker, server=True):
        at = self.log.stat().st_size
        self.lua(code, server)
        return self.wait(marker, at)

    def shot(self, label):
        self.send('hideconsole')
        time.sleep(1)
        hwnd = self.window()
        if not hwnd:
            raise RuntimeError('no responsive PoC window for screenshot')
        done, shots = threading.Event(), []
        def capture():
            try:
                shots.append(poc.capture_window(hwnd))
            finally:
                done.set()
        threading.Thread(target=capture, daemon=True).start()
        if not done.wait(poc.SCREENSHOT_TIMEOUT) or not shots:
            raise RuntimeError('PoC screenshot failed or timed out')
        shot = shots[0]
        if shot[1]['method'] != 'PrintWindow':
            raise RuntimeError('refusing an occluded screen-grab fallback')
        # poc_session returns a Pillow image plus the capture method.
        image = shot[0]
        image.save(self.out / (label + '.png'))

    def import_model(self):
        source = json.dumps(str(self.source), ensure_ascii=False)
        value = self.call('R12A.Import(' + source + ')', 'R12A_IMPORTED ', False)
        return json.loads(value)['asset']

    def spawn(self, role, scale=1):
        # Exercise the library's real client request/status route.
        self.send('setang 35 180 0')
        self.lua('player.GetAll()[1]:SetEyeAngles(Angle(35,180,0))')
        time.sleep(.4)
        ready = self.call('R12A.Spawn(' + json.dumps(role) + ',' + str(scale) + ')', 'R12A_READY ', False)
        index = json.loads(ready)['index']
        result = json.loads(self.call('R12A.Inspect(' + str(index) + ')', 'R12A_ENTITY '))
        self.lua('R12A.View(' + str(index) + ')', False)
        time.sleep(1)
        client = json.loads(self.call('R12A.Inspect(' + str(index) + ')', 'R12A_CLIENT ', False))
        deadline = time.monotonic() + 20
        while self.candidate and not client.get('instance') and time.monotonic() < deadline:
            time.sleep(.5)
            client = json.loads(self.call('R12A.Inspect(' + str(index) + ')', 'R12A_CLIENT ', False))
        result['client'] = client
        if self.candidate:
            assert result['ready'] and result['valid'] and result['manifest'] and result['modelRig'], result
            assert not result.get('bindingError'), result
            assert client.get('rig') == result['key'] and client.get('manifest') and client.get('instance', 0) > 0, client
        self.shot('%02d-%s' % (len(self.events), role))
        return result

    def delete(self):
        self.call('R12A.Delete()', 'R12A_DELETED ', False)
        # Server ForgetAssets and catalog withdrawal are asynchronous network messages.
        time.sleep(1)

    def retained(self):
        entries = json.loads(self.call('R12A.CheckRetained()', 'R12A_RETAINED '))
        if self.candidate:
            assert entries and all(e['same'] and e['valid'] and e.get('rig') == e.get('expected') for e in entries), entries

    def conversion(self):
        value = json.loads(self.call('R12A.Conversion()', 'R12A_CONVERTED '))
        if self.candidate:
            assert value.get('attached') and value.get('ready') and value.get('valid') and value.get('role') == 'citizen', value

    def sequence(self):
        probe = Path(__file__).with_name('mmd_reimport_probe.lua').read_text(encoding='utf8')
        installed = json.loads(self.call(probe, 'R12A_INSTALLED '))
        if self.candidate:
            source = (REPO / 'packages/model-hotloader/mmd_hotloader/lua/mmdhl/persistence.lua').read_text(encoding='utf8')
            line = source[:source.index(' meta.SetModel=function')].count('\n') + 1
            assert installed.get('wrapper', {}).get('line') == line, installed
        self.call(probe, 'R12A_INSTALLED ', False)
        self.send('sv_cheats 1')
        self.send('ai_disabled 1')
        self.send('engine_no_focus_sleep 0')
        self.send('fps_max 60')
        asset = self.import_model()
        self.call('R12A.asset=' + json.dumps(asset) + ' print("R12A_ASSET")', 'R12A_ASSET')
        first = None
        if not self.cold:
            first = self.spawn('citizen')
            if self.seed_only:
                return dict(asset=asset, seeded=first)
            self.spawn('player')
        self.delete()
        again = self.import_model()
        assert again == asset, (again, asset)
        ragdoll = self.spawn('ragdoll')
        npc = self.spawn('citizen')
        player = self.spawn('player')
        # New fit key, then the retained carrier's deletion/reimport with that option.
        changed = self.spawn('citizen', 1.1)
        assert changed['key'] != (first or npc)['key'], 'scale must change carrier identity'
        self.conversion()
        self.retained()
        self.delete()
        assert self.import_model() == asset
        self.spawn('ragdoll')
        changed_again = self.spawn('citizen', 1.1)
        self.spawn('player', 1.1)
        self.conversion()
        # An old entity remains valid when another fit is prepared/published.
        self.retained()
        return dict(asset=asset, first=first, ragdoll=ragdoll, npc=npc, player=player,
                    changed=changed, changed_again=changed_again)

    def run(self):
        field = end_field_games()
        poc.write_json(self.out / 'field-games.json', field)
        if field['remaining']:
            raise RuntimeError('a field game could not be ended')
        if poc.game_processes(POC):
            raise RuntimeError('PoC is already running')
        data_root = POC / 'garrysmod/data'
        cache = data_root / 'mmd_hotloader'
        saved = self.out / 'data-before'
        pbr = POC / 'rtx-remix/mods/~gmod_topbr'
        pbr_saved = self.out / 'pbr-before'
        lua_root = POC / 'garrysmod/addons/mmd_hotloader/lua'
        backups = self.out / 'lua-before'
        files = ['mmdhl/materials.lua', 'mmdhl/carrier.lua', 'mmdhl/actors.lua',
                 'mmdhl/persistence.lua', 'mmdhl/library.lua']
        config = POC / 'garrysmod/cfg/config.cfg'
        config_saved = self.out / 'config-before.cfg'
        if config.exists():
            shutil.copy2(config, config_saved)
        registry_before = video_settings()
        poc.write_json(self.out / 'video-before.json', registry_before)
        console_saved = self.out / 'console-before.log'
        self.restored = False
        changed, isolated_cache, isolated_pbr, isolated_log = [], False, False, False
        try:
            # Move the prior log without reading it. Waits can only see our new log.
            if self.log.exists():
                self.log.rename(console_saved)
            isolated_log = True
            if data_root.exists():
                checked_move(data_root, saved)
            data_root.mkdir(parents=True)
            isolated_cache = True
            if pbr.exists():
                checked_move(pbr, pbr_saved)
            pbr.mkdir(parents=True)
            isolated_pbr = True
            if self.seed:
                shutil.copytree(self.seed, cache)
            else:
                cache.mkdir(parents=True)
            # A field game started meanwhile is ended too, immediately before launch.
            field = end_field_games()
            poc.write_json(self.out / 'field-games-at-launch.json', field)
            if field['remaining']:
                raise RuntimeError('a field game could not be ended')
            env = dict(os.environ, TEMP=str(REPO / 'out/tmp'), TMP=str(REPO / 'out/tmp'))
            command = [sys.executable, str(REPO / 'tools/poc_session.py'), '--evidence', str(self.out),
                       'run', '--name', 'game', '--addons', '--settle', '0', '--screenshots', '0',
                       '--lua-shots', '1200', '--console', 'sv_cheats 1']
            if self.candidate:
                command += ['--map', '']  # stage at the menu, before any game Lua realm exists
            with (self.out / 'owner.log').open('w', encoding='utf8') as output:
                self.session = subprocess.Popen(command, cwd=REPO, env=env, stdout=output, stderr=subprocess.STDOUT)
                if self.candidate:
                    deadline = time.monotonic() + 180
                    while not self.window():
                        if time.monotonic() > deadline or self.session.poll() is not None:
                            raise RuntimeError('candidate did not reach its main menu')
                        time.sleep(.25)
                    self.quiet()
                    if 'Clientside Lua startup!' in poc.read_shared(self.log):
                        raise RuntimeError('candidate game Lua initialized before staging')
                    # The loader has restored owned files. Stage before the first
                    # map: auto-refreshing an already installed SetModel wrapper
                    # can retain its old local conversion memo and guard.
                    for rel in files:
                        before = backups / rel
                        before.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(lua_root / rel, before)
                        changed.append(rel)
                        shutil.copy2(REPO / 'packages/model-hotloader/mmd_hotloader/lua' / rel, lua_root / rel)
                    at = self.log.stat().st_size
                    self.send('map gm_construct')
                    self.wait('Clientside Lua startup!', at)
                    self.quiet()
                else:
                    self.wait('Clientside Lua startup!')
                    self.quiet()
                self.offset = 0  # the previous log was renamed before launch; this whole log is ours
                summary = self.sequence()
                poc.write_json(self.out / 'summary.json', summary)
        finally:
            if self.session and self.session.poll() is None:
                try:
                    self.lua('print("NL_SHOT_DONE")', False)
                except RuntimeError:
                    try:
                        self.send('quit')
                    except RuntimeError:
                        pass
                self.session.wait(timeout=180)
            if poc.game_processes(POC):
                raise RuntimeError('PoC still runs; preserve snapshot and lock for recovery')
            for rel in changed:
                shutil.copy2(backups / rel, lua_root / rel)
                assert digest(lua_root / rel) == digest(backups / rel)
            if isolated_cache and data_root.exists():
                checked_move(data_root, self.out / 'data-after')
            if saved.exists():
                checked_move(saved, data_root)
            if isolated_pbr and pbr.exists():
                checked_move(pbr, self.out / 'pbr-after')
            if pbr_saved.exists():
                checked_move(pbr_saved, pbr)
            if config_saved.exists():
                shutil.copy2(config_saved, config)
                assert digest(config) == digest(config_saved)
            elif config.exists():
                config.rename(self.out / 'config-after.cfg')
            restore_video_settings(registry_before)
            if isolated_log and self.log.exists():
                self.log.rename(self.out / 'console-after.log')
            if console_saved.exists():
                console_saved.rename(self.log)
            poc.write_json(self.out / 'events.json', self.events)
            poc.write_json(self.out / 'restored.json', dict(lua=changed, cache_restored=True,
                config_sha256=digest(config) if config.exists() else None))
            self.restored = True
            if self.session:
                history = json.loads((self.out / 'session.json').read_text(encoding='utf8'))
                if self.session.returncode or not history[-1].get('normal_quit'):
                    raise RuntimeError('owning session did not quit normally; see session.json')


def main():
    ctypes.windll.user32.SetProcessDPIAware()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', type=Path)
    ap.add_argument('--source', type=Path)
    ap.add_argument('--candidate', action='store_true')
    ap.add_argument('--seed-cache', type=Path, help='reuse a previous isolated seed cache from this worktree/out')
    ap.add_argument('--seed-only', action='store_true', help='import and spawn one NPC, then quit normally')
    ap.add_argument('--cold', action='store_true', help='delete the restored entry before any spawn warms its lookup')
    args = ap.parse_args()
    if not args.out or not args.source:
        ap.error('--out and --source are required')
    out, source = args.out.resolve(), args.source.resolve()
    if not out.is_relative_to(REPO / 'out') or not source.is_relative_to(REPO / 'out'):
        ap.error('evidence and copied source must be inside this worktree/out')
    if out.exists() or not source.is_file():
        ap.error('evidence must be new and copied source must exist')
    seed = args.seed_cache.resolve() if args.seed_cache else None
    if seed and (not seed.is_relative_to(REPO / 'out') or not seed.is_dir()):
        ap.error('seed cache must exist inside this worktree/out')
    try:
        with LOCK.open('x', encoding='utf8') as handle:
            json.dump(dict(task=TASK, pid=os.getpid(), time=poc.now(), evidence=str(out)), handle)
    except FileExistsError:
        print('PoC lock held by another task; retry after two minutes', flush=True)
        return 3
    out.mkdir(parents=True)
    probe = Probe(out, source, args.candidate, seed, args.seed_only, args.cold)
    try:
        probe.run()
    finally:
        if probe.restored and not poc.game_processes(POC):
            owner = json.loads(LOCK.read_text(encoding='utf8'))
            if owner.get('pid') == os.getpid() and owner.get('task') == TASK:
                LOCK.unlink()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
