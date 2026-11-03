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
import threading
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
                  hide_hud=False, no_window=False, fps=None, lua=[], lua_shots=None, menu_shot=False,
                  settle=0, screenshots=0, shot_interval=0, quit_timeout=5, hang_grace=ps.HANG_GRACE)
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
        # Every window and prompt in these session tests is fake, including background lookups.
        for name, value in (('window_hung', False), ('crash_prompts', []),
                            ('console_window', None), ('game_window', None)):
            patch = mock.patch.object(ps, name, return_value=value)
            patch.start()
            self.addCleanup(patch.stop)

    def test_a_reference_run_writes_nothing_into_the_game_folder(self):
        # R1-015's repro: an existing garrysmod/data/nl_session/ is the user's and stays as it is.
        user = self.root / 'garrysmod' / 'data' / 'nl_session' / 'user.txt'
        user.parent.mkdir(parents=True)
        user.write_text('USER DATA', encoding='utf-8')
        before = tree(self.root)
        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', return_value=FakeGame(running=False)) as launch, \
                mock.patch.dict(os.environ, {'NATIVE_LOADER_EXIT_REPORT': 'off'}), \
                mock.patch.object(ps.time, 'sleep'):
            record = ps.step_run(run_args(self.root, self.evidence, reference=True))
        self.assertTrue(record['early_exit'])
        self.assertEqual(launch.call_args.kwargs['env']['NATIVE_LOADER_EXIT_REPORT'], 'quiet')
        self.assertEqual(user.read_text(encoding='utf-8'), 'USER DATA')
        self.assertEqual(tree(self.root), before)

    def test_camera_lua_goes_through_the_console_only(self):
        clock, game, sent = Clock(), FakeGame(), []
        log = self.root / 'garrysmod' / 'console.log'
        data = self.root / 'garrysmod' / 'data'

        def launch(*_, **__):
            log.write_text('Clientside Lua startup!\n', encoding='utf-8')
            return game

        def console(hwnd, command, attempts=6, check=None):
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

    def test_the_frame_rate_is_timed_in_client_lua_sent_through_the_console(self):
        clock, game, sent = Clock(), FakeGame(), []
        log = self.root / 'garrysmod' / 'console.log'
        result = {'frames': 1200, 'seconds': 10.004, 'fps': 119.95, 'median_ms': 8.3, 'p99_ms': 12.5, 'max_ms': 20.1}

        def launch(*_, **__):
            log.write_text('Clientside Lua startup!\n', encoding='utf-8')
            return game

        def console(hwnd, command, attempts=6, check=None):
            sent.append(command)
            if command.endswith('"nl_session_fps")'):
                with open(log, 'a', encoding='utf-8') as handle:
                    handle.write('NL_SESSION_FPS ' + json.dumps(result) + '\n')
            elif command == 'quit':
                game.quit()
            return True

        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', clock.sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'console', side_effect=console), \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'game_window', return_value=None), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(run_args(self.root, self.evidence, fps=10.0))
        self.assertEqual(record['fps'], result)
        self.assertEqual(sent, ps.client_lua_lines('fps', ps.fps_lua(10.0)) + ['quit'])
        self.assertIn('hook.Add("PostRender", "nl_session_fps"', ps.fps_lua(10.0))
        self.assertIn('< 10.000 then return end', ps.fps_lua(10.0))
        self.assertFalse((self.root / 'garrysmod' / 'data').exists())

    def test_a_lua_file_paces_its_own_screenshots(self):
        # --lua runs a file through the console like the camera Lua; --lua-shots takes one screenshot
        # for each NL_SHOT line it prints and answers it with nl_shot_taken, until NL_SHOT_DONE.
        clock, game, sent, shots = Clock(), FakeGame(), [], []
        log = self.root / 'garrysmod' / 'console.log'
        script = self.root.parent / 'tour.lua'
        script.write_text('-- a tour\nprint("hello; world")\n', encoding='utf-8')
        replies = {'nl_shot_taken 1': 'NL_SHOT dusk\n', 'nl_shot_taken 2': 'NL_SHOT_DONE\n'}

        def launch(*_, **__):
            log.write_text('Clientside Lua startup!\n', encoding='utf-8')
            return game

        def console(hwnd, command, attempts=6, check=None):
            sent.append(command)
            text = None
            if command.endswith('"nl_session_lua1")'):
                text = 'NL_SESSION_LUA 1\nhello; world\nNL_SHOT noon_clear\n'
            elif command in replies:
                text = replies[command]
            elif command == 'quit':
                game.quit()
            if text:
                with open(log, 'a', encoding='utf-8') as handle:
                    handle.write(text)
            return True

        def screenshot(window, destination):
            shots.append((window, destination.name))
            return {'file': destination.name}

        args = run_args(self.root, self.evidence, lua=[str(script)], lua_shots=60.0)
        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', clock.sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'console', side_effect=console), \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'game_window', return_value=9), \
                mock.patch.object(ps, 'screenshot', side_effect=screenshot), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(args)
        code = ps.file_lua(1, script.read_text(encoding='utf-8'))
        self.assertTrue(code.startswith('print("NL_SESSION_LUA 1")\n'))
        self.assertEqual(record['lua'], [{'file': str(script), 'started': True}])
        self.assertEqual(shots, [(9, 'shot-01-noon_clear.png'), (9, 'shot-02-dusk.png')])
        self.assertEqual([shot['label'] for shot in record['lua_shots']], ['noon_clear', 'dusk'])
        self.assertTrue(record['lua_shots_done'])
        self.assertEqual(sent, ps.client_lua_lines('lua1', code) + ['nl_shot_taken 1', 'nl_shot_taken 2', 'quit'])
        self.assertFalse((self.root / 'garrysmod' / 'data').exists())

    def test_a_partial_first_mount_waits_for_a_remount_for_a_while(self):
        # R3-013: "Mounted 3 of 755" first, then the remount: the map waits for the second mount. A
        # partial first mount that no remount follows counts once PARTIAL_MOUNT_GRACE has passed.
        log = self.root / 'garrysmod' / 'console.log'

        def run(remount_at):
            clock, game, sent = Clock(), FakeGame(), []

            def launch(arguments, **_):
                log.write_text('Mounted 3 of 755 workshop addons!\n', encoding='utf-8')
                return game

            def sleep(seconds):
                clock.sleep(seconds)
                if remount_at and clock.now > remount_at and 'remounting' not in log.read_text(encoding='utf-8'):
                    with open(log, 'a', encoding='utf-8') as handle:
                        handle.write('Addons have changes - remounting\nMounted 752 of 755 workshop addons!\n')

            def console(hwnd, command, attempts=6, check=None):
                sent.append((clock.now, command))
                if command.startswith('map '):
                    with open(log, 'a', encoding='utf-8') as handle:
                        handle.write('Clientside Lua startup!\n')
                elif command == 'quit':
                    game.quit()
                return True

            with mock.patch.object(ps, 'game_processes', return_value=[]), \
                    mock.patch.object(ps, 'terminate', return_value=[]), \
                    mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                    mock.patch.object(ps.time, 'sleep', sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                    mock.patch.object(ps, 'console', side_effect=console), \
                    mock.patch.object(ps, 'console_window', return_value=7), \
                    mock.patch.object(ps, 'game_window', return_value=None), \
                    mock.patch.object(ps, 'modules_of', return_value=[]):
                record = ps.step_run(run_args(self.root, self.evidence, workshop=True))
            return clock, record, sent

        clock, record, sent = run(remount_at=1012)
        self.assertEqual(record['workshop_mounted'], ['3 of 755', '752 of 755'])
        self.assertEqual(record['workshop_ready_by'], 'the remount')
        self.assertGreater(sent[0][0], 1012)
        clock, record, sent = run(remount_at=None)
        self.assertEqual(record['workshop_mounted'], ['3 of 755'])
        self.assertTrue(record['workshop_ready_by'].startswith('a partial first mount'))
        self.assertGreater(sent[0][0], 1000 + ps.PARTIAL_MOUNT_GRACE)
        self.assertTrue(record['map_loaded'])

    def test_crash_report_prompts_are_declined_never_accepted(self):
        # After a crash the runtime's next start asks to upload crash data and then may show a notice;
        # unanswered they hold the run until its timeout. They are answered No (IDNO), then OK (IDOK),
        # by button id, so any Windows language works; IDYES is never sent.
        sent = []
        prompts = [[101], [102]]  # the question, then the notice that replaces it
        with mock.patch.object(ps, 'crash_prompts', side_effect=lambda pid: prompts.pop(0) if prompts else []), \
                mock.patch.object(ps.user32, 'SendMessageTimeoutW',
                                  side_effect=lambda h, m, w, *a: sent.append((h, m, w)) or 1):
            self.assertEqual(ps.decline_crash_prompts(4242), 2)
        self.assertEqual(sent, [(101, ps.WM_COMMAND, ps.IDNO), (102, ps.WM_COMMAND, ps.IDOK)])
        self.assertNotIn(6, [command for _, _, command in sent])  # IDYES
        # The run answers them while it waits for the map, and records how many.
        clock, game = Clock(), FakeGame()
        log = self.root / 'garrysmod' / 'console.log'
        waits = {'n': 0}
        answered = threading.Event()

        def launch(*_, **__):
            log.write_text('', encoding='utf-8')
            return game

        def decline(pid):
            waits['n'] += 1
            if waits['n'] == 3:
                log.write_text('Clientside Lua startup!\n', encoding='utf-8')
                answered.set()
                return 1
            return 0

        def console(hwnd, command, attempts=6, check=None):
            if command == 'quit':
                game.quit()
            return True

        def sleep(seconds):
            # Synchronize with the real watchdog thread, rather than depend on thread scheduling
            # while the session's fake clock races through its map timeout.
            self.assertTrue(answered.wait(2))
            clock.sleep(seconds)

        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'WATCHDOG_INTERVAL', 0.001), \
                mock.patch.object(ps, 'decline_crash_prompts', side_effect=decline), \
                mock.patch.object(ps, 'console', side_effect=console), \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'game_window', return_value=None), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(run_args(self.root, self.evidence))
        self.assertEqual(record['declined_crash_prompts'], 1)
        self.assertTrue(record['map_loaded'])

    def test_crash_minidumps_are_kept_before_the_declined_prompt_deletes_them(self):
        # Declining the prompt lets Remix delete the reports, the only evidence of a crash (R4): a run
        # copies the minidumps waiting from an earlier crash before it starts, and its own after a crash.
        reports = self.root / 'rtx-remix' / 'logs' / '.sentry-native' / 'reports'
        reports.mkdir(parents=True)
        (reports / 'earlier.dmp').write_bytes(b'MDMP earlier')
        clock = Clock()
        log = self.root / 'garrysmod' / 'console.log'

        def launch(*_, **__):
            log.write_text('', encoding='utf-8')
            (reports / 'earlier.dmp').unlink()  # the declined prompt
            (reports / 'this.dmp').write_bytes(b'MDMP this run')
            return FakeGame(running=False)  # it crashed before the map
        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', clock.sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'decline_crash_prompts', return_value=0), \
                mock.patch.object(ps, 'console_window', return_value=None), \
                mock.patch.object(ps, 'game_window', return_value=None), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(run_args(self.root, self.evidence, name='crashed'))
        self.assertFalse(record['normal_quit'])
        self.assertEqual(record['crash_reports_before'], ['reports-earlier.dmp'])
        self.assertEqual(record['crash_reports'], ['reports-this.dmp'])
        step = self.evidence / 'crashed'
        self.assertEqual((step / 'crash-reports-before' / 'reports-earlier.dmp').read_bytes(), b'MDMP earlier')
        self.assertEqual((step / 'crash-reports' / 'reports-this.dmp').read_bytes(), b'MDMP this run')

    def test_the_menu_shot_is_taken_at_the_menu_before_the_map(self):
        # --menu-shot: the main menu (the loader's diagnostics panel and add-on cards) is captured once
        # the Workshop is mounted, and only then is the map asked for.
        clock, game, events = Clock(), FakeGame(), []
        log = self.root / 'garrysmod' / 'console.log'

        def launch(arguments, **_):
            log.write_text('Mounted 755 of 755 workshop addons!\n', encoding='utf-8')
            return game

        def console(hwnd, command, attempts=6, check=None):
            events.append(command)
            if command == 'map gm_construct':
                with open(log, 'a', encoding='utf-8') as handle:
                    handle.write('Clientside Lua startup!\n')
            elif command == 'quit':
                game.quit()
            return True

        def screenshot(window, destination):
            events.append(('shot', window, destination.name))
            return {'file': destination.name}

        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', clock.sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'console', side_effect=console), \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'game_window', return_value=9), \
                mock.patch.object(ps, 'screenshot', side_effect=screenshot), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(run_args(self.root, self.evidence, workshop=True, menu_shot=True))
        self.assertEqual(events, [('shot', 9, 'menu.png'), 'map gm_construct', 'quit'])
        self.assertEqual(record['menu_screenshot'], {'file': 'menu.png'})
        self.assertTrue(record['map_loaded'])
        with self.assertRaises(SystemExit):  # it waits at the menu only with --workshop
            with mock.patch('sys.stderr'):
                ps.main(['--evidence', str(self.evidence), 'run', '--name', 'x', '--menu-shot'])

    def test_with_workshop_add_ons_the_map_waits_for_the_workshop_mount(self):
        # A map on the command line, or sent while Steam still lists the subscriptions, waits on that
        # fetch and the game stops answering: the run starts at the menu and asks for the map once the
        # second mount is done and the log is quiet.
        clock, game, sent, launched = Clock(), FakeGame(), [], []
        log = self.root / 'garrysmod' / 'console.log'

        def launch(arguments, **_):
            launched.append(arguments)
            log.write_text('Mounted 0 of 755 workshop addons!\n', encoding='utf-8')
            return game

        def sleep(seconds):
            clock.sleep(seconds)
            if clock.now > 1010 and 'remounting' not in log.read_text(encoding='utf-8'):
                with open(log, 'a', encoding='utf-8') as handle:
                    handle.write('Addons have changes - remounting\nMounted 752 of 755 workshop addons!\n')

        def console(hwnd, command, attempts=6, check=None):
            sent.append((clock.now, command))
            if command == 'map gm_construct':
                self.assertIn('Mounted 752 of 755', log.read_text(encoding='utf-8'))
                with open(log, 'a', encoding='utf-8') as handle:
                    handle.write('Clientside Lua startup!\n')
            elif command == 'quit':
                game.quit()
            return True

        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'console', side_effect=console), \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'game_window', return_value=None), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(run_args(self.root, self.evidence, workshop=True))
        self.assertNotIn('+map', launched[0])
        self.assertNotIn('-noworkshop', launched[0])
        self.assertIn('-multirun', launched[0])  # beside another install the user may be playing
        self.assertEqual(record['workshop_mounted'], ['0 of 755', '752 of 755'])
        self.assertTrue(record['workshop_ready'] and record['quiet_before_map'] and record['map_command'])
        self.assertTrue(record['map_loaded'])
        commands = [command for _, command in sent]
        self.assertEqual(commands, ['map gm_construct', 'quit'])
        self.assertGreater(sent[0][0], 1015)  # after the remount, and 5 s of quiet
        # Without Workshop add-ons the map stays on the command line.
        log.unlink()
        launched.clear()
        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=lambda a, **k: launched.append(a) or FakeGame(running=False)), \
                mock.patch.object(ps.time, 'sleep'):
            record = ps.step_run(run_args(self.root, self.evidence))
        self.assertEqual(launched[0][-2:], ['+map', 'gm_construct'])
        self.assertNotIn('workshop_ready', record)

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
        self.assertEqual((record['exit'], record['normal_quit']), (1, False))
        self.assertEqual(record['terminated_processes'], [12345, 2001, 2002])
        self.assertEqual(record['not_ours'], [9876])
        self.assertEqual(alive, {3001, 9876})

    def test_device_loss_aborts_the_steps_and_bounds_shutdown_but_keeps_evidence(self):
        clock, game = Clock(), FakeGame()
        log = self.root / 'garrysmod' / 'console.log'
        remix = self.root / 'rtx-remix' / 'logs' / 'remix-dxvk.log'
        reports = remix.parent / '.sentry-native' / 'reports'
        reports.mkdir(parents=True)

        def launch(*_, **__):
            log.write_text('Clientside Lua startup!\n', encoding='utf-8')
            remix.write_text('runtime started\n', encoding='utf-8')
            return game

        def sleep(seconds):
            clock.sleep(seconds)
            if clock.now >= 1002 and 'VK_ERROR_DEVICE_LOST' not in remix.read_text(encoding='utf-8'):
                with remix.open('a', encoding='utf-8') as handle:
                    handle.write('DxvkSubmissionQueue: Command submission failed: VK_ERROR_DEVICE_LOST\n')
                (reports / 'gpu.dmp').write_bytes(b'GPU crash evidence')

        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'console') as console, mock.patch.object(ps, 'screenshot') as shot, \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'modules_of', return_value=[]):
            record = ps.step_run(run_args(self.root, self.evidence, change_map='modern_house',
                                         mount_workshop=['123'], camera=[0] * 6, fps=30, lua=['unused.lua'],
                                         screenshots=1, settle=300))
        self.assertTrue(record['device_lost'])
        self.assertTrue(record['map_loaded'])
        self.assertIn('VK_ERROR_DEVICE_LOST', record['failed'])
        self.assertEqual(record['failure_exit_wait_seconds'], ps.FAILURE_EXIT_TIMEOUT)
        self.assertLessEqual(clock.now, 1002 + ps.FAILURE_EXIT_TIMEOUT + 3)
        self.assertTrue(game.killed)
        self.assertEqual(record['terminated_processes'], [game.pid])
        self.assertEqual(record['exit'], 1)
        self.assertFalse(record['normal_quit'])
        console.assert_not_called()
        shot.assert_not_called()
        step = self.evidence / 'run'
        self.assertEqual((step / 'console.log').read_text(encoding='utf-8'), 'Clientside Lua startup!\n')
        self.assertIn('VK_ERROR_DEVICE_LOST', (step / 'remix-dxvk.log').read_text(encoding='utf-8'))
        self.assertEqual((step / 'crash-reports' / 'reports-gpu.dmp').read_bytes(), b'GPU crash evidence')
        self.assertTrue((step / 'modules.json').exists())

    def test_watchdog_declines_a_live_crash_prompt_during_the_exit_grace(self):
        clock, game, answered, allow_prompt = Clock(), FakeGame(), threading.Event(), threading.Event()
        remix = self.root / 'rtx-remix' / 'logs' / 'remix-dxvk.log'
        reports = remix.parent / '.sentry-native' / 'reports'
        reports.mkdir(parents=True)
        dump = reports / 'gpu.dmp'

        def launch(*_, **kwargs):
            self.assertNotIn('RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES', kwargs['env'])
            (self.root / 'garrysmod' / 'console.log').write_text('Clientside Lua startup!\n', encoding='utf-8')
            remix.write_text('runtime started\n', encoding='utf-8')
            return game

        def decline(pid):
            self.assertEqual(pid, game.pid)
            if not allow_prompt.is_set():
                return 0
            dump.unlink()  # Remix deletes this run's report when the answer arrives.
            game.returncode = 0x60D0DEAD
            answered.set()
            return 1

        def sleep(seconds):
            clock.sleep(seconds)
            if clock.now >= 1001 and 'device loss' not in remix.read_text(encoding='utf-8'):
                remix.write_text('Exiting after GPU device loss\n', encoding='utf-8')
                dump.write_bytes(b'live crash')
            if allow_prompt.is_set():
                self.assertTrue(answered.wait(2))

        original_wait_exit = ps.wait_exit

        def wait_exit(process, seconds, check=None):
            if seconds == ps.FAILURE_EXIT_TIMEOUT:
                allow_prompt.set()  # the prompt appears only during the post-failure exit grace
            return original_wait_exit(process, seconds, check)

        with mock.patch.dict(os.environ, {'RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES': '1'}), \
                mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'WATCHDOG_INTERVAL', 0.001), \
                mock.patch.object(ps, 'wait_exit', side_effect=wait_exit), \
                mock.patch.object(ps, 'crash_prompts', side_effect=lambda pid: [99] if allow_prompt.is_set() else []), \
                mock.patch.object(ps, 'decline_crash_prompts', side_effect=decline), \
                mock.patch.object(ps, 'console') as console, mock.patch.object(ps, 'screenshot') as shot:
            record = ps.step_run(run_args(self.root, self.evidence, settle=300))
        self.assertFalse(game.killed)
        self.assertTrue(record['map_loaded'])
        self.assertEqual(record['exit'], 0x60D0DEAD)
        self.assertEqual(record['exit_hex'], '0x60D0DEAD')
        self.assertEqual(record['exit_name'], ps.EXIT_NAMES[0x60D0DEAD])
        self.assertEqual(record['declined_crash_prompts'], 1)
        self.assertEqual(record['crash_reports'], ['reports-gpu.dmp'])
        self.assertEqual((self.evidence / 'run' / 'crash-reports' / 'reports-gpu.dmp').read_bytes(), b'live crash')
        console.assert_not_called()
        shot.assert_not_called()

    def test_a_hung_window_fails_after_the_grace_without_console_or_capture(self):
        clock, game = Clock(), FakeGame()

        def launch(*_, **__):
            (self.root / 'garrysmod' / 'console.log').write_text('Clientside Lua startup!\n', encoding='utf-8')
            return game

        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', clock.sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'window_hung', return_value=True), \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'modules_of', return_value=[]), \
                mock.patch.object(ps, 'console') as console, mock.patch.object(ps, 'screenshot') as shot:
            record = ps.step_run(run_args(self.root, self.evidence, settle=300, screenshots=1))
        self.assertEqual(record['hung_seconds'], ps.HANG_GRACE)
        self.assertIn('hung for', record['failed'])
        self.assertNotIn('device_lost', record)
        self.assertEqual(record['failure_exit_wait_seconds'], ps.FAILURE_EXIT_TIMEOUT)
        self.assertLessEqual(clock.now, 1000 + ps.HANG_GRACE + ps.FAILURE_EXIT_TIMEOUT + 3)
        self.assertTrue(game.killed)
        console.assert_not_called()
        shot.assert_not_called()

    def test_main_keeps_the_failure_record_and_returns_failure(self):
        record = {'step': 'run', 'name': 'crash', 'failed': 'GPU device lost', 'device_lost': True}
        with mock.patch.object(ps, 'step_run', return_value=record), contextlib.redirect_stdout(io.StringIO()):
            code = ps.main(['--root', str(self.root), '--evidence', str(self.evidence), 'run', '--name', 'crash'])
        self.assertEqual(code, 1)
        history = json.loads((self.evidence / 'session.json').read_text(encoding='utf-8'))
        self.assertTrue(history[-1]['device_lost'])

    def test_the_hang_grace_option_reaches_the_run(self):
        graces = []

        def run(args):
            graces.append(args.hang_grace)
            return {'step': 'run', 'name': args.name}

        with mock.patch.object(ps, 'step_run', side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            for extra in ([], ['--hang-grace', '900']):
                ps.main(['--root', str(self.root), '--evidence', str(self.evidence), 'run', '--name', 'long', *extra])
        self.assertEqual(graces, [ps.HANG_GRACE, 900.0])

    def test_capture_timeout_uses_bounded_cleanup_and_still_collects_logs(self):
        clock, game = Clock(), FakeGame()

        def launch(*_, **__):
            (self.root / 'garrysmod' / 'console.log').write_text('Clientside Lua startup!\n', encoding='utf-8')
            return game

        with mock.patch.object(ps, 'game_processes', return_value=[]), \
                mock.patch.object(ps, 'terminate', return_value=[]), \
                mock.patch.object(ps.subprocess, 'Popen', side_effect=launch), \
                mock.patch.object(ps.time, 'sleep', clock.sleep), mock.patch.object(ps.time, 'monotonic', clock.monotonic), \
                mock.patch.object(ps, 'console_window', return_value=7), \
                mock.patch.object(ps, 'game_window', return_value=9), \
                mock.patch.object(ps, 'modules_of', return_value=[]), \
                mock.patch.object(ps, 'console') as console, \
                mock.patch.object(ps, 'screenshot', side_effect=ps.Failure('screenshot timed out after 5 s')):
            record = ps.step_run(run_args(self.root, self.evidence, screenshots=1))
        self.assertIn('screenshot timed out', record['failed'])
        self.assertEqual(record['failure_exit_wait_seconds'], ps.FAILURE_EXIT_TIMEOUT)
        self.assertTrue(game.killed)
        self.assertTrue((self.evidence / 'run' / 'console.log').is_file())
        console.assert_not_called()


class WatchdogTests(unittest.TestCase):
    def test_a_failed_dump_retry_does_not_damage_an_already_preserved_copy(self):
        base = scratch(self, 'poc-dump-retry-')
        source = base / 'game' / 'rtx-remix' / 'logs' / '.sentry-native' / 'reports'
        target = base / 'evidence'
        source.mkdir(parents=True)
        (source / 'gpu.dmp').write_bytes(b'complete dump')
        self.assertEqual(ps.keep_crash_reports(base / 'game', target), ['reports-gpu.dmp'])

        def interrupted_copy(src, dst):
            Path(dst).write_bytes(b'partial')
            raise OSError('dump is still being written')

        errors = []
        with mock.patch.object(ps.shutil, 'copy2', side_effect=interrupted_copy):
            self.assertEqual(ps.keep_crash_reports(base / 'game', target, errors), [])
        self.assertEqual((target / 'reports-gpu.dmp').read_bytes(), b'complete dump')
        self.assertEqual(sorted(p.name for p in target.iterdir()), ['reports-gpu.dmp'])
        self.assertTrue(any('still being written' in error for error in errors))

    def test_background_polling_continues_after_an_error_and_stops_when_the_game_exits(self):
        base, game, answered = scratch(self, 'poc-watchdog-'), FakeGame(), threading.Event()
        calls = []

        def decline(pid):
            calls.append(pid)
            if len(calls) == 1:
                raise OSError('temporary window lookup failure')
            if len(calls) == 3:
                game.quit()
                answered.set()
            return 1

        with mock.patch.object(ps, 'WATCHDOG_INTERVAL', 0.001), \
                mock.patch.object(ps, 'crash_prompts', return_value=[]), \
                mock.patch.object(ps, 'decline_crash_prompts', side_effect=decline):
            watchdog = ps.CrashPromptWatchdog(game, base / 'game', base / 'evidence')
            watchdog.start()
            try:
                self.assertTrue(answered.wait(2))
                watchdog.thread.join(2)
                self.assertFalse(watchdog.thread.is_alive())
            finally:
                watchdog.close()
        self.assertEqual(calls, [game.pid] * 3)
        self.assertEqual(watchdog.answered, 2)
        self.assertIn('temporary window lookup failure', watchdog.errors)

    def test_close_interrupts_the_watchdog_wait_without_waiting_for_another_tick(self):
        base, game, called = scratch(self, 'poc-watchdog-stop-'), FakeGame(), threading.Event()
        with mock.patch.object(ps, 'crash_prompts', return_value=[]), \
                mock.patch.object(ps, 'decline_crash_prompts', side_effect=lambda pid: called.set() or 1):
            watchdog = ps.CrashPromptWatchdog(game, base / 'game', base / 'evidence')
            watchdog.start()
            try:
                self.assertTrue(called.wait(2))
            finally:
                watchdog.close()
        self.assertFalse(watchdog.thread.is_alive())
        self.assertIsNone(game.poll())
        self.assertEqual(watchdog.answered, 1)

    def test_a_stuck_prompt_has_a_bounded_send_and_is_not_counted_as_answered(self):
        with mock.patch.object(ps, 'crash_prompts', return_value=[99]), \
                mock.patch.object(ps.user32, 'SendMessageTimeoutW', return_value=0) as send:
            self.assertEqual(ps.decline_crash_prompts(12345), 0)
        self.assertEqual([call.args[2] for call in send.call_args_list], [ps.IDNO, ps.IDOK])
        for call in send.call_args_list:
            self.assertEqual(call.args[4:6], (ps.SMTO_ABORTIFHUNG, 1000))


class HealthTests(unittest.TestCase):
    def setUp(self):
        self.log = scratch(self, 'poc-health-') / 'remix-dxvk.log'
        self.clock, self.record, self.game = Clock(), {}, FakeGame()

    def health(self, before=''):
        return ps.RunHealth(self.game, self.log, before, self.record)

    def test_device_loss_markers_in_a_new_log_are_detected_even_after_the_process_exits(self):
        self.game.returncode = 0x60D0DEAD
        for marker in ('VK_ERROR_DEVICE_LOST', 'Exiting after GPU device loss'):
            with self.subTest(marker=marker):
                self.log.write_text('error: ' + marker + '\n', encoding='utf-8')
                with self.assertRaisesRegex(ps.Failure, 'GPU device lost'):
                    self.health().check()
                self.assertTrue(self.record['device_lost'])
                self.assertEqual(self.record['device_lost_marker'], marker)

    def test_an_old_marker_is_ignored_but_new_appended_or_rewritten_markers_are_detected(self):
        before = 'previous run: VK_ERROR_DEVICE_LOST\n'
        health = self.health(before)
        with mock.patch.object(ps, 'console_window', return_value=None), \
                mock.patch.object(ps, 'game_window', return_value=None):
            for text in (before, before + 'new run is healthy\n'):
                self.log.write_bytes(text.encode('utf-8'))
                health.check()
                self.assertNotIn('device_lost', self.record)
            for text in (before + 'new run: VK_ERROR_DEVICE_LOST\n',
                         'new run\n' * 20 + 'Exiting after GPU device loss\n'):
                self.log.write_bytes(text.encode('utf-8'))
                with self.assertRaises(ps.Failure):
                    health.check()

    def test_a_short_map_stall_recovers_and_resets_the_continuous_hang_grace(self):
        health = self.health()
        hung = [True]
        with mock.patch.object(ps.time, 'monotonic', self.clock.monotonic), \
                mock.patch.object(ps.time, 'sleep', self.clock.sleep), \
                mock.patch.object(ps, 'window_hung', side_effect=lambda hwnd: hung[0]):
            health.check(7)
            self.clock.sleep(12)
            health.check(7)
            hung[0] = False
            health.before_window(7)
            hung[0] = True
            health.check(7)
            self.clock.sleep(ps.HANG_GRACE - 0.5)
            health.check(7)
            self.assertNotIn('hung_seconds', self.record)
            self.clock.sleep(0.5)
            with self.assertRaisesRegex(ps.Failure, f'hung for {ps.HANG_GRACE:.1f} s'):
                health.check(7)
        self.assertEqual(self.record['hung_seconds'], ps.HANG_GRACE)

    def test_a_longer_hang_grace_waits_out_a_long_load(self):
        health = ps.RunHealth(self.game, self.log, '', self.record, 900.0)
        with mock.patch.object(ps.time, 'monotonic', self.clock.monotonic), \
                mock.patch.object(ps.time, 'sleep', self.clock.sleep), \
                mock.patch.object(ps, 'window_hung', return_value=True):
            health.check(7)
            self.clock.sleep(899)
            health.check(7)
            self.assertNotIn('hung_seconds', self.record)
            self.clock.sleep(1)
            with self.assertRaisesRegex(ps.Failure, 'hung for 900.0 s'):
                health.check(7)

    def test_window_operations_wait_out_a_normal_load_instead_of_sending_to_a_hung_window(self):
        with mock.patch.object(ps.time, 'monotonic', self.clock.monotonic), \
                mock.patch.object(ps.time, 'sleep', self.clock.sleep), \
                mock.patch.object(ps, 'window_hung', side_effect=lambda hwnd: self.clock.now < 1012):
            self.health().before_window(7)
        self.assertEqual(self.clock.now, 1012)
        self.assertNotIn('hung_seconds', self.record)

    def test_console_retry_checks_health_after_a_ten_second_send_stalls(self):
        health, calls, hung = self.health(), [], [False]

        def send(*args):
            calls.append(args)
            self.clock.sleep(10)
            hung[0] = True
            return 0

        with mock.patch.object(ps.time, 'monotonic', self.clock.monotonic), \
                mock.patch.object(ps.time, 'sleep', self.clock.sleep), \
                mock.patch.object(ps, 'window_hung', side_effect=lambda hwnd: hung[0]), \
                mock.patch.object(ps.user32, 'SendMessageTimeoutW', side_effect=send):
            with self.assertRaisesRegex(ps.Failure, 'hung for'):
                ps.console(7, 'map modern_house', check=health.before_window)
        self.assertEqual(len(calls), 1)  # no retry once a continuous hang is confirmed
        self.assertEqual(self.clock.now, 1010 + ps.HANG_GRACE)  # the 10 s send, then the whole grace

    def test_window_hung_uses_the_nonblocking_windows_query(self):
        with mock.patch.object(ps.user32, 'IsHungAppWindow', side_effect=[1, 0]) as hung:
            self.assertTrue(ps.window_hung(7))
            self.assertFalse(ps.window_hung(7))
        self.assertEqual(hung.call_args_list, [mock.call(7), mock.call(7)])

    def test_a_temporarily_locked_log_does_not_disable_hang_detection(self):
        health = self.health()
        with mock.patch.object(ps, 'read_shared', side_effect=PermissionError('log locked')), \
                mock.patch.object(ps.time, 'monotonic', self.clock.monotonic), \
                mock.patch.object(ps, 'window_hung', return_value=True):
            health.check(7)
            self.clock.sleep(ps.HANG_GRACE)
            with self.assertRaisesRegex(ps.Failure, 'hung for'):
                health.check(7)
        self.assertIn('log locked', self.record['remix_log_read_error'])

    def test_known_exit_codes_have_names_even_when_windows_reports_a_signed_code(self):
        for code, meaning in ps.EXIT_NAMES.items():
            for reported in (code, code - 2**32):
                with self.subTest(code=reported):
                    record = {'exit': reported, 'normal_quit': True}
                    ps.describe_exit(record)
                    self.assertEqual(record['exit'], reported)
                    self.assertEqual(record['exit_hex'], f'0x{code:08X}')
                    self.assertEqual(record['exit_name'], meaning)
                    self.assertFalse(record['normal_quit'])
                    self.assertEqual(record.get('device_lost', False), code == 0x60D0DEAD)
        for code in (0, 1, None):
            record = {'exit': code}
            ps.describe_exit(record)
            self.assertNotIn('exit_name', record)


class ScreenshotTests(unittest.TestCase):
    def test_no_capture_or_console_send_is_attempted_on_a_known_hung_window(self):
        with mock.patch.object(ps, 'window_hung', return_value=True), \
                mock.patch.object(ps, 'capture_window') as capture, \
                mock.patch.object(ps.user32, 'SendMessageTimeoutW') as send:
            with self.assertRaisesRegex(ps.Failure, 'hung game window'):
                ps.screenshot(7, Path('unused.png'))
            self.assertFalse(ps.console(7, 'quit'))
        capture.assert_not_called()
        send.assert_not_called()

    def test_a_capture_that_freezes_after_the_check_times_out_and_never_writes_late(self):
        base = scratch(self, 'poc-capture-')
        release, finished = threading.Event(), threading.Event()
        image = mock.Mock()

        def capture(hwnd):
            try:
                release.wait(2)
                return image, {'method': 'fake PrintWindow'}
            finally:
                finished.set()

        with mock.patch.object(ps, 'window_hung', return_value=False), \
                mock.patch.object(ps, 'SCREENSHOT_TIMEOUT', 0.02), \
                mock.patch.object(ps, 'capture_window', side_effect=capture):
            try:
                with self.assertRaisesRegex(ps.Failure, 'screenshot timed out'):
                    ps.screenshot(7, base / 'late.png')
            finally:
                release.set()
                self.assertTrue(finished.wait(2))
        image.save.assert_not_called()
        self.assertFalse((base / 'late.png').exists())

    def test_a_completed_capture_is_saved_and_capture_errors_are_reported(self):
        destination = scratch(self, 'poc-capture-ok-') / 'shot.png'
        image = mock.Mock()
        with mock.patch.object(ps, 'window_hung', return_value=False), \
                mock.patch.object(ps, 'capture_window', return_value=(image, {'method': 'fake'})):
            self.assertEqual(ps.screenshot(7, destination), {'file': 'shot.png', 'method': 'fake'})
        image.save.assert_called_once_with(destination)
        with mock.patch.object(ps, 'window_hung', return_value=False), \
                mock.patch.object(ps, 'capture_window', side_effect=OSError('capture failed')):
            with self.assertRaisesRegex(ps.Failure, 'capture failed'):
                ps.screenshot(7, destination)


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
        self.assertNotIn('reshade', json.loads(self.config.read_text(encoding='utf-8'))['remix'])  # the loader's default
        code, record = main('--allow-local', 'b.gma', '--reshade', 'off', '--replace-config')
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(self.config.read_text(encoding='utf-8'))['remix'], {'enabled': True, 'reshade': 'off'})
        self.assertNotIn('diagnostics', json.loads(self.config.read_text(encoding='utf-8')))  # older loaders reject it
        code, record = main('--allow-local', 'b.gma', '--performance-tier', 'low', '--gpu-crash-dumps', 'next_start',
                            '--memory-telemetry', 'off', '--replace-config')
        self.assertEqual(code, 0)
        written = json.loads(self.config.read_text(encoding='utf-8'))
        self.assertEqual(written['remix'], {'enabled': True, 'performance_tier': 'low'})
        self.assertEqual(written['diagnostics'], {'gpu_crash_dumps': 'next_start', 'memory_telemetry': 'off'})
        code, record = main('--allow-local', 'b.gma', '--memory-profile', 'minimum', '--replace-config')  # loader 0.13.0
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(self.config.read_text(encoding='utf-8'))['remix'], {'enabled': True, 'memory_profile': 'minimum'})


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

    def test_relative_local_packages_that_exist_here_become_absolute(self):
        """R10: the loader reads a relative entry against the game root, so out\\pkg.gma deployed nothing."""
        folder = scratch(self, 'poc-session-local-')
        (folder / 'pkg.gma').write_bytes(b'GMAD')
        (folder / 'dev').mkdir()
        args = SimpleNamespace(allow_local=['pkg.gma', 'garrysmod/addons/x.gma'], allow_dev=['dev'], allow_workshop=[],
                               remix='on', require_insecure='yes')
        here = os.getcwd()
        os.chdir(folder)
        try:
            value, _ = ps.config_content(args)
        finally:
            os.chdir(here)
        self.assertEqual(value['allow']['local'], [str((folder / 'pkg.gma').resolve()), 'garrysmod/addons/x.gma'])
        self.assertEqual(value['allow']['dev_folders'], [str((folder / 'dev').resolve())])

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
