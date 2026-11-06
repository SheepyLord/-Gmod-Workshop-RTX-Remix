"""Run the production transient effect observer against bounded engine and Remix contracts."""
from pathlib import Path
import subprocess
import unittest
from test_mmd_alpha import LUAJIT, ROOT


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class EffectCategoryTests(unittest.TestCase):
    def test_session_observer(self):
        for scenario in ("normal", "off", "server", "no_api", "changes", "wrappers", "retry", "bounded", "late_hash", "hash_budget", "color_helper", "packed_flags"):
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(Path(__file__).with_name("effect_categories_harness.lua")),
                                         str(ROOT / "companion/nativeloader/lua/autorun/_nativeloader_effect_categories.lua"),
                                         scenario], capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS " + scenario, result.stdout)
