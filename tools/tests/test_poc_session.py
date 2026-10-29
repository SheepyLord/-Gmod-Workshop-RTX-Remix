"""poc_session.py without a game: client Lua through the console (R1-015), ending only what a run
started (R1-019), the install step's config guard (R1-026) and PowerShell's module path (R1-029).
Process launches, console text and the Win32 lookups are mocked, so no game ever starts; one test
starts two Python processes and ends them. Scratch goes under out/tmp."""
import contextlib
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

if sys.platform != 'win32':
    raise unittest.SkipTest('poc_session.py drives Windows processes')

import poc_session as ps  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SCRATCH = REPO / 'out' / 'tmp'  # AGENTS.md rule 9
CHUNK_LINE = re.compile(r'^lua_run_cl NL_S=NL_S\.\."([0-9a-f]{1,200})"$')
# Lua that Source's console would break: ';' and line breaks split commands, '//' starts a comment.
AWKWARD_LUA = ('print("a; b") -- ; and "quotes"\n// not a comment in a Lua string: "http://x"\r\n'
               'local t = {1, 2, 3}; print(#t)\n-- caf\u00e9 \u30c6\u30b9\u30c8\n') * 6
# A stand-in for PowerShell 7's own Microsoft.PowerShell.Utility: a module Windows PowerShell 5.1
# cannot load. First in PSModulePath, it hides 5.1's Get-FileHash, as the real one does (R1-029).
CORE_ONLY_UTILITY = ("@{\n    ModuleVersion = '7.4.0.500'\n    GUID = '1da87e53-152b-403e-98dc-74d7b4d63d59'\n"
                     "    PowerShellVersion = '7.0'\n    CompatiblePSEditions = @('Core')\n"
                     "    CmdletsToExport = @('Get-FileHash')\n}\n")


def scratch(test, prefix):
    SCRATCH.mkdir(parents=True, exist_ok=True)
    folder = tempfile.TemporaryDirectory(dir=SCRATCH, prefix=prefix)
    test.addCleanup(folder.cleanup)
    return Path(folder.name)


def tree(root):
    return sorted(p.relative_to(root).as_posix() for p in root.rglob('*'))


def run_args(root, evidence, **changes):
    values = dict(root=str(root), evidence=str(evidence), name='run', reference=False, allow_steam_managed=False,
                  width=1280, height=720, workshop=False, addons=False, extra=[], players=1, map='gm_construct',
                  post=[], timeout=30, load_save=None, change_map=None, mount_workshop=None, console=[], camera=None,
                  hide_hud=False, no_window=False,
                  settle=0, screenshots=0, shot_interval=0, quit_timeout=5)
    values.update(changes)
    return SimpleNamespace(**values)


class Clock:
    """time.monotonic and time.sleep for step_run: a sleep moves the clock on, nobody waits."""

    def __init__(self):
        self.now = 1000.0

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.now += max(seconds, 0.01)


class FakeGame:
    """What subprocess.Popen returns for gmod.exe: running until it quits or is killed."""

    def __init__(self, pid=12345, running=True, quits=True, on_kill=None):
        self.pid = pid
        self.returncode = None if running else 0
        self.quits = quits
        self.killed = False
        self.on_kill = on_kill

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        if self.returncode is None:
            raise subprocess.TimeoutExpired('gmod.exe', timeout)
        return self.returncode

    def kill(self):
        self.killed = True
        self.returncode = 1
        if self.on_kill:
            self.on_kill()

    def quit(self):
        if self.quits:
            self.returncode = 0


class ClientLuaTests(unittest.TestCase):
    """R1-015: client Lua travels through the console, hex-encoded; no file is written for it."""

    def test_lines_carry_the_code_hex_encoded(self):
        lines = ps.client_lua_lines('camera', AWKWARD_LUA)
        self.assertEqual(lines[0], 'lua_run_cl NL_S=""')
        self.assertEqual(lines[-1], 'lua_run_cl RunString((NL_S:gsub("..",function(h) return string.char(tonumber(h,16)) '
                                    'end)),"nl_session_camera")')
        chunks = [CHUNK_LINE.match(line) for line in lines[1:-1]]
        self.assertTrue(all(chunks), lines[1:-1])
        self.assertGreater(len(chunks), 3)
        # What the last line does in Lua: two hex digits back into one byte, all of them in order.
        self.assertEqual(bytes.fromhex(''.join(match.group(1) for match in chunks)).decode('utf-8'), AWKWARD_LUA)
        for line in lines:
            self.assertFalse(set(line) & {';', '\n', '\r'} or '//' in line, line)
            self.assertLess(len(line.encode('utf-8')), 512, line)  # Source's command length limit

    def test_empty_code_and_bad_chunk_names(self):
        self.assertEqual(len(ps.client_lua_lines('mount', '')), 2)
        for name in ('', 'a"b', 'a b', 'x' * 33):
            with self.assertRaises(ValueError):
                ps.client_lua_lines(name, 'print(1)')

    def test_every_line_goes_through_console_and_a_failure_stops_the_rest(self):
        sent = []
        with mock.patch.object(ps, 'console', side_effect=lambda hwnd, line: sent.append(line) or True):
            self.assertTrue(ps.client_lua(7, 'camera', AWKWARD_LUA))
        self.assertEqual(sent, ps.client_lua_lines('camera', AWKWARD_LUA))
        sent.clear()
        with mock.patch.object(ps, 'console', side_effect=lambda hwnd, line: sent.append(line) or len(sent) < 2):
            self.assertFalse(ps.client_lua(7, 'camera', AWKWARD_LUA))
        self.assertEqual(len(sent), 2)  # the line that runs the chunk was never sent


class ClassifyTests(unittest.TestCase):
    """R1-019: which same-root games are the launched one and its descendants."""
    L = 1_000_000  # the launch time

    def classify(self, candidates, parents, created):
        return ps.classify(candidates, 100, self.L, parents, created.get)

    def test_the_launched_game_and_its_descendants_are_ours(self):
        L = self.L
        parents = {101: 100, 102: 101, 555: 100, 103: 555}  # 103 descends through 555, which is no game
        created = {100: L, 101: L + 1, 102: L + 2, 555: L + 3, 103: L + 4}
        self.assertEqual(self.classify([103, 100, 102, 101], parents, created),
                         ({100: L, 101: L + 1, 102: L + 2, 103: L + 4}, []))

    def test_games_that_do_not_descend_from_the_launch_are_not_ours(self):
        L = self.L
        parents = {200: 4, 201: 100, 300: 400, 400: 100, 500: 501, 501: 500}
        created = {100: L, 200: L + 5, 201: L - 1, 300: L + 5, 400: L + 9, 500: L + 1, 501: L + 1}
        ours, others = self.classify([200, 201, 300, 400, 500, 600], parents, created)
        # 200: another parent. 201: older than the launch (a recycled PID). 300: its parent PID now
        # names a process newer than 300 itself (recycled). 500: a parent cycle. 600: no creation time.
        self.assertEqual((ours, others), ({400: L + 9}, [200, 201, 300, 500, 600]))


class RealProcessTests(unittest.TestCase):
    """Toolhelp32 parents, creation times and terminate() on two real Python processes (no game)."""
    CHILD = ('import subprocess, sys, time\n'
             'g = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])\n'
             'print(g.pid, flush=True)\n'
             'time.sleep(30)\n')

    def test_a_child_and_a_grandchild(self):
        launched_at = ps.filetime_now()
        child = subprocess.Popen([sys.executable, '-c', self.CHILD], stdout=subprocess.PIPE, text=True)
        grandchild = None
        try:
            grandchild = int(child.stdout.readline())
            created = ps.process_created(grandchild)
            ours, others = ps.classify([child.pid, grandchild, os.getpid()], child.pid, launched_at,
                                       ps.process_parents(), ps.process_created)
            self.assertEqual(sorted(ours), sorted([child.pid, grandchild]))
            self.assertEqual(others, [os.getpid()])  # this test's own process predates the launch
            self.assertEqual(ps.terminate({grandchild: created + 1}), [])  # not the process classified
            self.assertEqual(ps.terminate({grandchild: created}), [grandchild])
        finally:
            child.kill()
            child.wait(10)
            child.stdout.close()
            if grandchild:
                ps.terminate({grandchild: ps.process_created(grandchild)})


class StepRunTests(unittest.TestCase):
    def setUp(self):
        base = scratch(self, 'poc-session-run-')
        self.root, self.evidence = base / 'game', base / 'evidence'
        (self.root / 'garrysmod').mkdir(parents=True)

    def test_a_reference_run_writes_nothing_into_the_game_folder(self):
        # R1-015's repro: an existing garrysmod/data/nl_session/ is the user's and stays as it is.
        user = self.root / 'garrysmod' / 'data' / 'nl_session' / 'user.txt'
        user.parent.mkdir(parents=True)
        user.write_text('USER DATA', encoding='utf-8')
        before = tree(self.root)
        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', return_value=FakeGame(running=False)), \
                mock.patch.object(ps.time, 'sleep'):
            record = ps.step_run(run_args(self.root, self.evidence, reference=True))
        self.assertTrue(record['early_exit'])
        self.assertEqual(user.read_text(encoding='utf-8'), 'USER DATA')
        self.assertEqual(tree(self.root), before)

    def test_camera_lua_goes_through_the_console_only(self):
        clock, game, sent = Clock(), FakeGame(), []
        log = self.root / 'garrysmod' / 'console.log'
        data = self.root / 'garrysmod' / 'data'

        def launch(*_, **__):
            log.write_text('Clientside Lua startup!\n', encoding='utf-8')
            return game

        def console(hwnd, command, attempts=6):
            sent.append(command)
            self.assertFalse(data.exists(), 'something was written under garrysmod/data')
            if command.startswith('lua_run_cl RunString((NL_S:gsub('):
                with open(log, 'a', encoding='utf-8') as handle:
                    handle.write('NL_SESSION_EYE 1.000,2.000,3.000,0.000,90.000,0.000\n')
            elif command == 'quit':
                game.quit()
            return True

        args = run_args(self.root, self.evidence, camera=[1.0, 2.0, 3.0, 0.0, 90.0, 0.0])
        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', clock.sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'console', side_effect=console), \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'game_window', return_value=None), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(args)
        self.assertTrue(record['camera'])
        self.assertEqual(record['eye'], '1.000,2.000,3.000,0.000,90.000,0.000')
        self.assertTrue(record['normal_quit'])
        self.assertEqual(sent, ps.client_lua_lines('camera', ps.camera_lua(args.camera, False)) + ['quit'])
        self.assertFalse(data.exists())

    def test_cleanup_leaves_a_game_this_run_did_not_start(self):
        # R1-019's repro: a same-root game that appears after the preflight is somebody else's.
        calls = iter([[]])
        with mock.patch.object(ps, 'game_processes', side_effect=lambda root: next(calls, [9876])), \
                mock.patch.object(ps, 'filetime_now', return_value=5_000, create=True), \
                mock.patch.object(ps, 'process_parents', return_value={9876: 4444}, create=True), \
                mock.patch.object(ps, 'process_created', side_effect={9876: 6_000}.get, create=True), \
                mock.patch.object(ps, 'terminate', return_value=[]) as terminate, \
                mock.patch.object(ps.subprocess, 'Popen', return_value=FakeGame(running=False)), \
                mock.patch.object(ps.time, 'sleep'):
            record = ps.step_run(run_args(self.root, self.evidence, reference=True))
        for call in terminate.call_args_list:
            self.assertNotIn(9876, call.args[0])
        self.assertEqual(record['not_ours'], [9876])
        self.assertNotIn('terminated_helpers', record)

    def test_a_timeout_ends_the_game_and_its_helpers_and_nothing_else(self):
        L, clock = 5_000, Clock()
        alive = {12345, 2001, 3001, 2002, 9876}  # 3001 is a helper's parent but not a game
        games = {12345, 2001, 2002, 9876}
        parents = {12345: 1, 2001: 12345, 3001: 12345, 2002: 3001, 9876: 4444}
        created = {12345: L + 1, 2001: L + 10, 3001: L + 20, 2002: L + 30, 9876: L + 40}
        game = FakeGame(quits=False, on_kill=lambda: alive.discard(12345))
        launched, terminated = [], []

        def terminate(expected):
            terminated.append(expected)
            alive.difference_update(expected)
            return sorted(expected)

        with mock.patch.object(ps, 'game_processes', side_effect=lambda root: sorted(games & alive) if launched else []), \
                mock.patch.object(ps, 'filetime_now', return_value=L, create=True), \
                mock.patch.object(ps, 'process_parents', side_effect=lambda: {p: q for p, q in parents.items() if p in alive},
                                  create=True), \
                mock.patch.object(ps, 'process_created', side_effect=lambda pid: created.get(pid) if pid in alive else None,
                                  create=True), \
                mock.patch.object(ps, 'terminate', side_effect=terminate), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=lambda *a, **k: launched.append(1) or game), \
                mock.patch.object(ps.time, 'sleep', clock.sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'console_window', return_value=None), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(run_args(self.root, self.evidence, timeout=1))
        self.assertTrue(game.killed)
        self.assertEqual(terminated[0], {2001: L + 10, 2002: L + 30})
        self.assertEqual((record['exit'], record['normal_quit']), ('terminated', False))
        self.assertEqual(record['not_ours'], [9876])
        self.assertEqual(alive, {3001, 9876})


class InstallConfigTests(unittest.TestCase):
    """R1-026: an existing config.json is never replaced silently."""
    USER = b'{"schema":1,"allow":{"local":["my-reviewed-package.gma"]}}'

    def setUp(self):
        base = scratch(self, 'poc-session-install-')
        self.root, self.evidence = base / 'game', base / 'evidence'
        self.config = self.root / 'native-loader' / 'config.json'
        self.config.parent.mkdir(parents=True)

    def args(self, **changes):
        values = dict(root=str(self.root), evidence=str(self.evidence), config='Release', allow_steam_managed=False,
                      allow_local=[], allow_dev=[], allow_workshop=[], remix='off', require_insecure='yes',
                      replace_config=False)
        values.update(changes)
        return SimpleNamespace(**values)

    @contextlib.contextmanager
    def installer(self, during=None):
        def run(*arguments):
            if during:
                during()
            return SimpleNamespace(returncode=0, stdout='Bootstrap installed', stderr='')
        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'powershell', side_effect=run) as shell:
            yield shell

    def backups(self):
        return sorted(self.evidence.glob('config.json.before-*')) if self.evidence.exists() else []

    def test_a_different_config_is_refused_before_anything_runs(self):
        self.config.write_bytes(self.USER)
        with self.installer() as shell, self.assertRaises(ps.Failure) as caught:
            ps.step_install(self.args())
        self.assertIn('--replace-config', str(caught.exception))
        shell.assert_not_called()
        self.assertEqual(self.config.read_bytes(), self.USER)
        self.assertEqual(self.backups(), [])

    def test_replace_config_saves_the_old_one_in_the_evidence_first(self):
        self.config.write_bytes(self.USER)
        with self.installer():
            record = ps.step_install(self.args(replace_config=True))
        backup = record['config_backup']
        self.assertEqual([Path(backup['path'])], self.backups())
        self.assertEqual(Path(backup['path']).read_bytes(), self.USER)
        self.assertEqual(backup['sha256'], hashlib.sha256(self.USER).hexdigest())
        self.assertEqual(json.loads(self.config.read_text(encoding='utf-8'))['allow'],
                         {'workshop': [], 'local': [], 'dev_folders': []})

    def test_only_an_unchanged_config_is_rewritten(self):
        ps.step_config(self.args())  # the same config this install writes: no flag, no backup needed
        with self.installer():
            self.assertNotIn('config_backup', ps.step_install(self.args()))
        written = self.config.read_bytes()
        # Somebody edits the config while the installer runs: it is kept, even with --replace-config.
        with self.installer(during=lambda: self.config.write_bytes(self.USER)), self.assertRaises(ps.Failure) as caught:
            ps.step_install(self.args(replace_config=True))
        self.assertIn('changed while the installer ran', str(caught.exception))
        self.assertEqual(self.config.read_bytes(), self.USER)
        self.assertNotEqual(written, self.USER)
        self.assertEqual(self.backups(), [])

    def test_the_command_line(self):
        def main(*arguments):
            with self.installer(), contextlib.redirect_stdout(io.StringIO()):
                code = ps.main(['--root', str(self.root), '--evidence', str(self.evidence), 'install', *arguments])
            return code, json.loads((self.evidence / 'session.json').read_text(encoding='utf-8'))[-1]
        self.assertEqual(main()[0], 0)  # no config yet
        code, record = main('--allow-local', 'b.gma')
        self.assertEqual(code, 1)
        self.assertIn('differs', record['failed'])
        code, record = main('--allow-local', 'b.gma', '--replace-config')
        self.assertEqual(code, 0)
        self.assertEqual(Path(record['config_backup']['path']).parent, self.evidence)
        self.assertEqual(json.loads(self.config.read_text(encoding='utf-8'))['allow']['local'], ['b.gma'])


class PowerShellTests(unittest.TestCase):
    """R1-029: every Windows PowerShell child starts without an inherited PSModulePath."""

    def test_every_powershell_child_gets_no_module_path(self):
        calls = []

        def run(command, **kwargs):
            calls.append((command, kwargs))
            return SimpleNamespace(returncode=0, stdout='ok', stderr='')

        root = scratch(self, 'poc-session-shell-')
        args = SimpleNamespace(root=str(root), evidence=str(root / 'evidence'), config='Release', allow_steam_managed=False,
                               allow_local=[], allow_dev=[], allow_workshop=[], remix='on', require_insecure='yes',
                               replace_config=False)
        with mock.patch.dict(os.environ, {'PSModulePath': r'C:\Program Files\PowerShell\7\Modules'}), \
                mock.patch.object(ps.subprocess, 'run', side_effect=run), \
                mock.patch.object(ps, 'game_processes', return_value=[]):
            ps.step_install(args)
            ps.step_uninstall(args)
        shells = [kwargs for command, kwargs in calls if command[0].lower() == 'powershell']
        self.assertEqual(len(shells), 2)  # install-loader.ps1 and uninstall-loader.ps1
        for kwargs in shells:
            self.assertIsNotNone(kwargs.get('env'))
            self.assertEqual([name for name in kwargs['env'] if name.upper() == 'PSMODULEPATH'], [])
            self.assertEqual(kwargs['env'].get('PATH'), os.environ.get('PATH'))

    @unittest.skipUnless(shutil.which('powershell'), 'Windows PowerShell is not installed')
    def test_windows_powershell_finds_get_filehash_under_a_powershell_7_module_path(self):
        folder = scratch(self, 'poc-session-pwsh-')
        module = folder / 'modules' / 'Microsoft.PowerShell.Utility'
        module.mkdir(parents=True)
        (module / 'Microsoft.PowerShell.Utility.psd1').write_text(CORE_ONLY_UTILITY, encoding='utf-8')
        probe = folder / 'probe.ps1'
        probe.write_text('(Get-Command Get-FileHash -ErrorAction SilentlyContinue).Source\n', encoding='utf-8')
        inherited = str(folder / 'modules') + os.pathsep + os.environ.get('PSModulePath', '')
        with mock.patch.dict(os.environ, {'PSModulePath': inherited}):
            done = ps.powershell(probe)
        self.assertEqual(done.stdout.strip(), 'Microsoft.PowerShell.Utility', done.stderr)


if __name__ == '__main__':
    unittest.main()
