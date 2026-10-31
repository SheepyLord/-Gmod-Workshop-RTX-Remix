"""Exercise the Lua request protocol with a small GMod API stub.

Run with `python tests/test_transport.py` when `lupa` is available. The tests
use lupa's LuaJIT runtime when it has one, since GMod runs LuaJIT 2.1.
"""

import json
import unittest
from pathlib import Path

try:
    from lupa.luajit21 import LuaRuntime, lua_type
except ImportError:
    from lupa import LuaRuntime, lua_type


ADDON = Path(__file__).resolve().parents[1] / "addon/lua/autorun/client/rtx_debug.lua"

API_STUB = r"""
function isstring(v) return type(v)=='string' end
function isnumber(v) return type(v)=='number' end
function istable(v) return type(v)=='table' end
function isfunction(v) return type(v)=='function' end
function IsValid(v) return false end
unpack = unpack or table.unpack
table.maxn = table.maxn or function(t)
    local n = 0
    for k in pairs(t) do if type(k) == 'number' and k > n then n = k end end
    return n
end
restored = 0
RTXDebug = {
    Status = function() return {version='test',process_id=1234} end,
    RestoreAll = function() restored = restored + 1 return {complete=true} end,
    Engine = {
        World = function() return {map='gm_construct'} end,
        Fail = function() return nil, 'engine unavailable' end,
        Raise = function() error('boom', 0) end,
        Count = function(...) return {n=select('#', ...), third=select(3, ...)} end,
    },
    Lua = {
        Global = function() return {ok=false, value=1} end,
    },
    Secret = { Thing = function() return true end },
}
"""


class TransportTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.files = {}
        self.markers = []
        self.errors = []
        self.hooks = {}

        def to_lua(value):
            if isinstance(value, dict):
                return self.lua.table_from({key: to_lua(item) for key, item in value.items()})
            if isinstance(value, list):
                return self.lua.table_from({index: to_lua(item) for index, item in enumerate(value, 1)})
            return value

        def to_python(value):
            if lua_type(value) != "table":
                return value
            items = {key: to_python(item) for key, item in value.items()}
            if items and all(isinstance(key, int) for key in items):
                if set(items) == set(range(1, len(items) + 1)):
                    return [items[index] for index in range(1, len(items) + 1)]
            return items

        def decode(raw):
            try:
                return to_lua(json.loads(raw))
            except (TypeError, ValueError):
                return None

        def hook_add(event, name, fn):
            self.hooks.setdefault(event, {})[name] = fn

        file_api = self.lua.table()
        file_api.CreateDir = lambda path: None
        file_api.Read = lambda path, realm: self.files.get(path)
        file_api.Write = lambda path, contents: self.files.__setitem__(path, contents)
        self.lua.globals().file = file_api

        util_api = self.lua.table()
        util_api.JSONToTable = decode
        util_api.TableToJSON = lambda value, pretty=False: json.dumps(to_python(value))
        self.lua.globals().util = util_api

        hook_api = self.lua.table()
        hook_api.Add = hook_add
        self.lua.globals().hook = hook_api

        self.lua.globals().require = lambda name: True
        self.lua.globals().MsgN = self.markers.append
        self.lua.globals().ErrorNoHalt = self.errors.append
        self.lua.globals().SysTime = lambda: 123.0
        self.lua.execute(API_STUB)
        self.lua.execute(ADDON.read_text(encoding="utf-8"))

    def write_request(self, request_id, body):
        self.files[f"rtx_debug/requests/{request_id}.json"] = body

    def result(self, request_id):
        return json.loads(self.files[f"rtx_debug/results/{request_id}.json"])

    def request(self, request_id, method, args=None):
        self.write_request(request_id, json.dumps({"id": request_id, "method": method, "args": args or []}))
        self.lua.globals().RTXDebug.DispatchRequest(request_id)
        return self.result(request_id)

    def test_success_and_completion_marker(self):
        result = self.request("world_1", "Engine.World")
        self.assertTrue(result["ok"])
        self.assertEqual(result["result"]["map"], "gm_construct")
        self.assertEqual(result["protocol"], 1)
        self.assertEqual(result["process_id"], 1234)
        self.assertEqual(self.markers[-1], "[RTXDebug] DONE world_1")

    def test_nil_and_message_is_top_level_error(self):
        result = self.request("fail_1", "Engine.Fail")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "engine unavailable")

    def test_lua_error_is_top_level_error(self):
        result = self.request("raise_1", "Engine.Raise")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "boom")

    def test_table_with_ok_false_is_data(self):
        result = self.request("global_1", "Lua.Global", ["client", "x"])
        self.assertTrue(result["ok"])
        self.assertEqual(result["result"], {"ok": False, "value": 1})

    def test_top_level_methods(self):
        self.assertEqual(self.request("status_1", "Status")["result"]["version"], "test")
        self.assertTrue(self.request("restore_1", "RestoreAll")["ok"])
        self.assertEqual(self.lua.globals().restored, 1)

    def test_process_binding_rejects_another_client(self):
        self.write_request('wrong_pid', json.dumps({'method': 'RestoreAll', 'process_id': 5678}))
        self.lua.globals().RTXDebug.DispatchRequest('wrong_pid')
        result = self.result('wrong_pid')
        self.assertFalse(result['ok'])
        self.assertEqual(result['error'], 'request belongs to another process')
        self.assertEqual(result['process_id'], 1234)
        self.assertEqual(self.lua.globals().restored, 0)

    def test_process_binding_accepts_selected_client(self):
        self.write_request('right_pid', json.dumps({'method': 'Status', 'process_id': 1234}))
        self.lua.globals().RTXDebug.DispatchRequest('right_pid')
        self.assertTrue(self.result('right_pid')['ok'])

    def test_only_api_methods_resolve(self):
        for index, method in enumerate(["DispatchRequest", "Engine.World.extra", "Engine.9World",
                                        "Secret.Thing", "_G.print", "Engine.", 42]):
            result = self.request(f"bad_{index}", method)
            self.assertFalse(result["ok"], method)
            self.assertEqual(result["error"], "unknown method or invalid args")

    def test_null_arguments_keep_positions(self):
        result = self.request("count_1", "Engine.Count", [1, None, 3])
        self.assertTrue(result["ok"])
        self.assertEqual(result["result"], {"n": 3, "third": 3})

    def test_missing_request_gets_error_result(self):
        self.lua.globals().RTXDebug.DispatchRequest("missing_1")
        result = self.result("missing_1")
        self.assertFalse(result["ok"])
        self.assertEqual(self.markers[-1], "[RTXDebug] DONE missing_1")

    def test_mismatched_id_is_rejected(self):
        self.write_request("mine_1", json.dumps({"id": "other", "method": "Engine.World"}))
        self.lua.globals().RTXDebug.DispatchRequest("mine_1")
        self.assertEqual(self.result("mine_1")["error"], "invalid JSON request or mismatched id")

    def test_oversized_request_is_rejected(self):
        self.write_request("big_1", " " * (1024 * 1024 + 1))
        self.lua.globals().RTXDebug.DispatchRequest("big_1")
        self.assertEqual(self.result("big_1")["error"], "request exceeds 1 MiB")

    def test_invalid_id_is_rejected(self):
        self.assertFalse(self.lua.globals().RTXDebug.DispatchRequest("../outside"))
        self.assertFalse(any("outside" in path for path in self.files))

    def test_shutdown_hook_restores_everything(self):
        shutdown = self.hooks["ShutDown"]["RTXDebug.RestoreAll"]
        shutdown()
        self.assertEqual(self.lua.globals().restored, 1)
        self.assertEqual(self.errors, [])


class LoadFailureTest(unittest.TestCase):
    def test_failed_require_stops_the_addon(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        errors = []
        lua.globals().ErrorNoHalt = errors.append
        lua.execute("function require(name) error('module not found: ' .. name, 0) end")
        lua.execute(ADDON.read_text(encoding="utf-8"))
        self.assertEqual(errors, ["[RTXDebug] require failed: module not found: rtxdebug\n"])
        self.assertIsNone(lua.globals().RTXDebug)


if __name__ == "__main__":
    unittest.main()
