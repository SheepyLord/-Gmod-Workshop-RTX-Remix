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
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
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
timer = { Create = function() end }
concommand = { Add = function() end }
dofile(COMPANION)
for _, line in ipairs(out) do print("OUT " .. line) end
for _, line in ipairs(notices) do print("NOTICE " .. line) end
'''


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class CompanionTests(unittest.TestCase):
    def run_companion(self, status, workshop):
        text = json.dumps(status)
        with tempfile.TemporaryDirectory(dir=REPO / 'out' / 'tmp') as scratch:
            script = Path(scratch) / 'harness.lua'
            script.write_text('FILES = ' + lua_value({'native-loader/status.json': text}) + '\n'
                              'TABLES = ' + lua_value({text: status}) + '\n'
                              'WORKSHOP = ' + lua_value(workshop) + '\n'
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


if __name__ == '__main__':
    unittest.main()
