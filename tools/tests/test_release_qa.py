"""tools/qa/release_qa.py without a game: the session command lines for the field and the PoC, the pass
rules on session records and probe output, and --evaluate-only on a recorded evidence folder. Nothing is
launched; scratch goes under out/tmp."""
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRATCH = REPO / 'out' / 'tmp'  # AGENTS.md rule 9
SPEC = importlib.util.spec_from_file_location('release_qa', REPO / 'tools' / 'qa' / 'release_qa.py')
qa = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(qa)

GOOD_RECORD = {'step': 'run', 'map_loaded': True, 'normal_quit': True, 'exit': 0, 'lua_errors': 0,
               'activation': {'outcome': 'active', 'reason': 'runtime x'}, 'status_errors': [], 'lua_shots_done': True,
               'lua_shots': [{'label': 'spawn'}]}
GOOD_SESSION_CONSOLE = '\n'.join([
    'NL_QA_GUARD {"errors":0,"version":2,"cleanup_errors":0,"blocked":0,"enabled":true,"installation":"early"}',
    'NL_QA_PARTS {"map":"gm_construct"}',
    'NL_QA_WEAPON gmod_tool',
    '[nativeloader] Toolgun screen {"texture":"gmodtoolgunscreen","triangles":2,"captures":360,"draws":180}',
    'NL_QA_GUARD_AFTER_TOOLGUN {"blocked":0,"errors":0,"cleanup":0}',
    'NL_SHOT_DONE', ''])
MAP_GLASS_CONSOLE = ('NL_GLASS panes 50 func_breakable 50 shards 0\nNL_GLASS before shards 0\n'
                     'NL_GLASS after_first pane_valid false shards 36\nNL_GLASS after_more shards 36\nNL_GLASS done\n')


class CommandTests(unittest.TestCase):
    def test_field_sessions_mount_the_workshop_and_keep_the_games_window_settings(self):
        command = qa.session_command('session', root=Path('G'), evidence=Path('E'), step='01-session', field=True,
                                     extra=['-insecure', '-tickrate', '120'])
        self.assertIn('--allow-steam-managed', command)
        for part in ('--workshop', '--no-window', '--menu-shot', '--addons'):
            self.assertIn(part, command)
        self.assertEqual(command[-3:], ['--extra=-insecure', '--extra=-tickrate', '--extra=120'])
        self.assertNotIn('mat_queue_mode 2', command)  # the field has the user's own setting
        glass = qa.session_command('map-glass', root=Path('G'), evidence=Path('E'), step='03-map-glass', field=True, extra=[])
        self.assertEqual(glass[glass.index('--map') + 1], 'modern_house')
        self.assertIn('sv_cheats 1', glass)
        self.assertNotIn('--menu-shot', glass)

    def test_poc_sessions_mount_only_the_map_and_queue_rendering(self):
        command = qa.session_command('map-glass', root=Path('G'), evidence=Path('E'), step='03-map-glass', field=False, extra=[])
        self.assertNotIn('--allow-steam-managed', command)
        self.assertNotIn('--workshop', command)
        self.assertEqual(command[command.index('--map') + 1], 'gm_construct')
        self.assertEqual(command[command.index('--mount-workshop') + 1], qa.MODERN_HOUSE_MAP_ITEM)
        self.assertEqual(command[command.index('--change-map') + 1], 'modern_house')
        self.assertIn('mat_queue_mode 2', command)
        self.assertTrue(command[command.index('--lua') + 1].endswith('map_glass_probe.lua'))
        spawnmenu = qa.session_command('spawnmenu', root=Path('G'), evidence=Path('E'), step='02-spawnmenu', field=False, extra=[])
        self.assertNotIn('sv_cheats 1', spawnmenu)


class RuleTests(unittest.TestCase):
    def test_a_good_record_passes_and_a_crash_does_not(self):
        self.assertEqual(qa.check_record(GOOD_RECORD), [])
        crashed = dict(GOOD_RECORD, normal_quit=False, exit=3221225477, lua_shots_done=False)
        problems = qa.check_record(crashed)
        self.assertTrue(any('no normal quit (exit 3221225477)' in p for p in problems), problems)
        self.assertTrue(any('NL_SHOT_DONE' in p for p in problems), problems)
        vanilla = dict(GOOD_RECORD, activation={'outcome': 'vanilla', 'reason': 'no runtime'})
        self.assertTrue(any('not active' in p for p in qa.check_record(vanilla)))
        self.assertEqual(qa.check_record({'failed': 'a game from this install is running'}),
                         ['the session step failed: a game from this install is running'])

    def test_session_probe_rules(self):
        self.assertEqual(qa.check_probe('session', GOOD_SESSION_CONSOLE), [])
        broken = GOOD_SESSION_CONSOLE.replace('"draws":180}', '"draws":0,"error":"boom"}')
        self.assertTrue(any('toolgun' in p for p in qa.check_probe('session', broken)))
        errors = GOOD_SESSION_CONSOLE.replace('{"blocked":0,"errors":0,"cleanup":0}', '{"blocked":0,"errors":2,"cleanup":0}')
        self.assertTrue(any('after the toolgun' in p for p in qa.check_probe('session', errors)))
        self.assertTrue(any('no render guard' in p for p in qa.check_probe('session', 'NL_QA_GUARD {"missing":true}\n')))

    def test_spawnmenu_and_glass_rules(self):
        self.assertEqual(qa.check_probe('spawnmenu', 'NL_QA_TABS ["#spawnmenu.content_tab"]\n'), [])
        self.assertEqual(qa.check_probe('spawnmenu', 'NL_QA_TABS []\nNL_QA_TAB_MISSING motion_importer\n'),
                         ['spawn menu tab not found: motion_importer'])
        self.assertEqual(qa.check_probe('map-glass', MAP_GLASS_CONSOLE), [])
        unbroken = MAP_GLASS_CONSOLE.replace('pane_valid false shards 36', 'pane_valid true shards 0')
        self.assertTrue(any('did not break' in p for p in qa.check_probe('map-glass', unbroken)))
        self.assertTrue(any('no glass pane' in p for p in qa.check_probe('map-glass', 'NL_GLASS no glass pane found\n')))
        spawned = 'NL_GLASS spawned 1 1.0 2.0 3.0\nNL_GLASS after_shot shards 9\nNL_GLASS done\n'
        self.assertEqual(qa.check_probe('spawned-glass', spawned), [])
        self.assertTrue(any('did not break' in p for p in
                            qa.check_probe('spawned-glass', spawned.replace('shards 9', 'shards 1'))))


class SettingsTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        folder = tempfile.TemporaryDirectory(dir=SCRATCH, prefix='release-qa-settings-')
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)

    def write(self, name, text):
        path = self.folder / name
        path.write_text(text, encoding='utf-8')
        return path

    def test_config_cfg_fails_only_on_the_guarded_keys(self):
        # The game rewrites config.cfg at every quit; only mat_queue_mode, which a session switches
        # for a moment (R4-28), must come back.
        before = self.write('b.cfg', 'unbindall\nbind "F1" "gm_showhelp"\nmat_queue_mode "2"\nfps_max "300"\n')
        after = self.write('a.cfg', 'unbindall\nbind "F1" "gm_showhelp"\nmat_queue_mode "0"\nfps_max "200"\nnew_cvar "1"\n')
        change = qa.settings_changes(before, after, qa.GUARDED_CONFIG_KEYS)
        self.assertEqual(change['changed'], {'mat_queue_mode': ['2', '0'], 'fps_max': ['300', '200']})
        self.assertEqual(change['added'], {'new_cvar': '1'})
        self.assertEqual(change['problems'], ["mat_queue_mode: '2' -> '0'"])
        restored = self.write('r.cfg', 'unbindall\nbind "F1" "gm_showhelp"\nmat_queue_mode "2"\nfps_max "200"\n')
        self.assertEqual(qa.settings_changes(before, restored, qa.GUARDED_CONFIG_KEYS)['problems'], [])

    def test_client_vdf_reports_new_keys_and_fails_on_changed_values(self):
        # An add-on's new convar adds a key (reported); a changed value is a setting the run changed.
        before = self.write('b.vdf', '"CVars"\n{\n\t"gm_demo_icon"\t\t"1"\n\t"pp_bloom_passes"\t\t"4"\n}\n')
        added = self.write('a.vdf', '"CVars"\n{\n\t"gm_demo_icon"\t\t"1"\n\t"pp_bloom_passes"\t\t"4"\n'
                                    '\t"mmd_vmd_npc_stage_jumps"\t\t"100"\n}\n')
        change = qa.settings_changes(before, added)
        self.assertEqual(change['added'], {'"mmd_vmd_npc_stage_jumps"': '100'})
        self.assertEqual(change['problems'], [])
        edited = self.write('e.vdf', '"CVars"\n{\n\t"gm_demo_icon"\t\t"0"\n}\n')
        problems = qa.settings_changes(before, edited)['problems']
        self.assertEqual(problems, ['"gm_demo_icon": \'1\' -> \'0\'', '"pp_bloom_passes": \'4\' -> None'])
        # R5: a slider writing a convar back in the engine's %f form changes nothing.
        hour = self.write('h.vdf', '"CVars"\n{\n\t"nativeloader_sky_hour"\t\t"0.00"\n\t"skin"\t\t"x"\n}\n')
        rewritten = self.write('r.vdf', '"CVars"\n{\n\t"nativeloader_sky_hour"\t\t"0.000000"\n\t"skin"\t\t"x"\n}\n')
        self.assertEqual(qa.settings_changes(hour, rewritten)['changed'], {})
        moved = self.write('m.vdf', '"CVars"\n{\n\t"nativeloader_sky_hour"\t\t"2.130000"\n\t"skin"\t\t"y"\n}\n')
        self.assertEqual(sorted(qa.settings_changes(hour, moved)['changed']), ['"nativeloader_sky_hour"', '"skin"'])


class EvaluateOnlyTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        folder = tempfile.TemporaryDirectory(dir=SCRATCH, prefix='release-qa-')
        self.addCleanup(folder.cleanup)
        self.evidence = Path(folder.name)

    def record(self, step, console, **changes):
        (self.evidence / step).mkdir()
        (self.evidence / step / 'console.log').write_text(console, encoding='utf-8')
        return dict(GOOD_RECORD, name=step, **changes)

    def test_the_latest_run_of_each_session_is_checked_and_summarized(self):
        history = [self.record('01-session', GOOD_SESSION_CONSOLE, normal_quit=False),
                   self.record('02-session', GOOD_SESSION_CONSOLE),
                   self.record('03-map-glass', MAP_GLASS_CONSOLE)]
        (self.evidence / 'session.json').write_text(json.dumps(history), encoding='utf-8')
        with redirect_stdout(io.StringIO()):
            code = qa.main(['--root', str(self.evidence), '--evidence', str(self.evidence), '--evaluate-only',
                            '--only', 'session,map-glass'])
        summary = json.loads((self.evidence / 'qa-summary.json').read_text(encoding='utf-8'))
        self.assertEqual(code, 0, summary)
        self.assertEqual([s['step'] for s in summary['sessions']], ['02-session', '03-map-glass'])
        self.assertTrue(summary['passed'])

    def test_a_missing_or_failed_session_fails_the_summary(self):
        history = [self.record('01-spawnmenu', 'NL_QA_TABS []\n', exit=3221225477, normal_quit=False,
                               crash_reports=['reports-x.dmp'])]
        (self.evidence / 'session.json').write_text(json.dumps(history), encoding='utf-8')
        with redirect_stdout(io.StringIO()):
            code = qa.main(['--root', str(self.evidence), '--evidence', str(self.evidence), '--evaluate-only',
                            '--only', 'spawnmenu,spawned-glass'])
        summary = json.loads((self.evidence / 'qa-summary.json').read_text(encoding='utf-8'))
        self.assertEqual(code, 1)
        spawnmenu, glass = summary['sessions']
        self.assertTrue(any('crash minidumps' in p for p in spawnmenu['problems']), spawnmenu)
        self.assertEqual(glass['problems'], ['no recorded run'])


if __name__ == '__main__':
    unittest.main()
