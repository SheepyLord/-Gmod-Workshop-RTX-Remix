"""The Lua companion (companion/nativeloader) under LuaJIT, with the GMod functions it uses mocked:
the console summary, and M6's restart notice for a Workshop package Steam has updated since start-up.
Skipped when LuaJIT is not installed."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
COMPANION = REPO / 'companion' / 'nativeloader' / 'lua' / 'autorun' / 'client' / 'nativeloader.lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe']
                                          if p.is_file()), None)


def lua_value(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return '"' + (value.replace('\\', '\\\\').replace('"', '\\"')
                      .replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')) + '"'
    if isinstance(value, list):
        return '{' + ','.join(lua_value(v) for v in value) + '}'
    return '{' + ','.join('[' + lua_value(k) + ']=' + lua_value(v) for k, v in value.items()) + '}'


HARNESS = r'''
CLIENT = true
local out, notices = {}, {}
function MsgN(text) out[#out + 1] = text end
local files = FILES
file = { Exists = function(path) return files[path] ~= nil end, Read = function(path) return files[path] end }
util = { JSONToTable = function(text) return TABLES[text] end }
steamworks = { FileInfo = function(id, callback) callback(WORKSHOP[id]) end }
notification = { AddLegacy = function(text) notices[#notices + 1] = text end }
NOTIFY_HINT = 3
timer = { Create = function() end, Simple = function() end }
concommand = { Add = function() end }
hook = { Add = function() end }
istable = function(value) return type(value) == "table" end
isfunction = function(value) return type(value) == "function" end
if API then RemixLight = { CreateSphere = function() end }; RemixConfig = {} end
dofile(COMPANION)
for _, line in ipairs(out) do print("OUT " .. line) end
for _, line in ipairs(notices) do print("NOTICE " .. line) end
'''


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class CompanionTests(unittest.TestCase):
    def run_companion(self, status, workshop, api=False):
        text = json.dumps(status)
        with tempfile.TemporaryDirectory(dir=REPO / 'out' / 'tmp') as scratch:
            script = Path(scratch) / 'harness.lua'
            script.write_text('FILES = ' + lua_value({'native-loader/status.json': text}) + '\n'
                              'TABLES = ' + lua_value({text: status}) + '\n'
                              'WORKSHOP = ' + lua_value(workshop) + '\n'
                              'API = ' + lua_value(api) + '\n'
                              'COMPANION = ' + lua_value(str(COMPANION)) + '\n' + HARNESS, encoding='utf-8')
            done = subprocess.run([LUAJIT, str(script)], capture_output=True, text=True, timeout=30)
        self.assertEqual(done.returncode, 0, done.stderr)
        return done.stdout.splitlines()

    def status(self, packages):
        return {'schema': 1, 'loader_version': '0.2.0', 'utc': '2099-01-01T00:00:00.000Z', 'process_id': 1,
                'deployment': {'outcome': 'unchanged', 'generation': 2}, 'activation': {'outcome': 'active', 'reason': 'runtime x'},
                'session': {'cvars': 2, 'cvars_exec': 'nativeloader_session.cfg', 'recorded': 1, 'notes': []},
                'packages': packages, 'errors': []}

    def test_a_newer_workshop_version_asks_for_a_restart_once(self):
        lines = self.run_companion(self.status([{'id': 'rtx-remix-runtime', 'version': '1.0.0', 'source': 'workshop',
                                                  'label': '123', 'time_updated': 100}]), {'123': {'updated': 200}})
        self.assertTrue(any('newer Workshop version' in line for line in lines if line.startswith('OUT')), lines)
        self.assertEqual(len([line for line in lines if line.startswith('NOTICE')]), 1, lines)
        self.assertTrue(any('session variables: 2 set by nativeloader_session.cfg' in line for line in lines), lines)

    def test_the_deployed_version_or_a_local_package_says_nothing(self):
        lines = self.run_companion(self.status([
            {'id': 'rtx-remix-runtime', 'version': '1.0.0', 'source': 'workshop', 'label': '123', 'time_updated': 200},
            {'id': 'rtx-fixes', 'version': '1.0.0', 'source': 'local', 'label': 'C:/fixes.gma', 'time_updated': None}]),
            {'123': {'updated': 200}})
        self.assertFalse([line for line in lines if line.startswith('NOTICE') or 'newer Workshop version' in line], lines)

    def test_steams_float_rounded_time_of_the_deployed_version_says_nothing(self):
        # steamworks.FileInfo returns times rounded to a 32-bit float (128 s steps today): the
        # Evernight and March 7th item, deployed at 1793444836, came back as 1793444864, and the restart
        # notice came at every start (2026-10-31). A version more than one step later is still announced.
        same = self.run_companion(self.status([{'id': 'evernight-march7th-rtx', 'version': '1.0.0', 'source': 'workshop',
                                                 'label': '3830769477', 'time_updated': 1793444836}]),
                                  {'3830769477': {'updated': 1793444864}})
        self.assertFalse([line for line in same if line.startswith('NOTICE') or 'newer Workshop version' in line], same)
        later = self.run_companion(self.status([{'id': 'evernight-march7th-rtx', 'version': '1.0.0', 'source': 'workshop',
                                                  'label': '3830769477', 'time_updated': 1793444836}]),
                                   {'3830769477': {'updated': 1793445120}})
        self.assertEqual(len([line for line in later if line.startswith('NOTICE')]), 1, later)

    def test_the_status_says_whether_the_remix_api_is_ready(self):
        status = self.status([])
        ready = self.run_companion(status, {}, api=True)
        self.assertIn('OUT [nativeloader] Remix API: ready (RemixLight, RemixConfig)', ready)
        missing = self.run_companion(status, {}, api=False)
        self.assertTrue(any(line.startswith('OUT [nativeloader] Remix API: not available') for line in missing), missing)

    def test_the_status_says_what_reshade_did(self):
        # ADR 0028: loader 0.5.0 reports ReShade under activation; an older loader's status has no such field.
        status = self.status([])
        self.assertFalse([line for line in self.run_companion(status, {}) if 'reshade' in line], status)
        status['activation']['reshade'] = {'outcome': 'active', 'reason': 'ReShade from gmod-rtx-remix 1.0.0',
                                           'package': 'gmod-rtx-remix', 'settings': 'migrated'}
        self.assertIn('OUT [nativeloader] reshade: active (ReShade from gmod-rtx-remix 1.0.0), settings migrated in '
                      'native-loader\\reshade', self.run_companion(status, {}))
        status['activation']['reshade'] = {'outcome': 'off', 'reason': 'remix.reshade is "off"', 'package': 'gmod-rtx-remix',
                                           'settings': ''}
        self.assertIn('OUT [nativeloader] reshade: off (remix.reshade is "off")', self.run_companion(status, {}))

    def test_every_companion_lua_file_compiles(self):
        files = sorted((REPO / 'companion' / 'nativeloader' / 'lua').rglob('*.lua'))
        self.assertGreaterEqual(len(files), 6)
        for path in files:
            # loadfile only compiles the file; nothing of it runs (GMod's functions are not there).
            done = subprocess.run([LUAJIT, '-e', 'assert(loadfile([==[' + str(path) + ']==]))'], capture_output=True,
                                  text=True, timeout=30)
            self.assertEqual(done.returncode, 0, f'{path.name}: {done.stderr}')


if __name__ == '__main__':
    unittest.main()
