"""Exercise evidence completeness and exact byte accounting without a game."""
import json
import unittest

import vram_census as census


def line(**row):
    return "[RTX Allocation] " + json.dumps(row) + "\n"


class VramCensusTests(unittest.TestCase):
    def test_existing_telemetry_without_game_input(self):
        body = "time_utc,usedAppTextureBytes,unavailable\n2026-11-03T01:30:00Z,14380545024,\n2026-11-03T01:40:00Z,14380545025,\nunfinished"
        result = census.telemetry(body, census.utc_time("2026-11-03T01:35:00Z"))
        self.assertTrue(result["truncated_tail_omitted"])
        self.assertEqual(result["samples"], [{"time_utc": "2026-11-03T01:40:00Z", "usedAppTextureBytes": 14380545025, "unavailable": None}])
        for broken in ("not_a_header\n", "time_utc,x\n2026-11-03T01:30:00Z,-1\n",
                       "time_utc,x\n2026-11-03T01:30:00,2\n", "time_utc,x\n2026-11-03T01:30:00Z,1,2\n"):
            with self.subTest(broken=broken), self.assertRaises(ValueError):
                census.telemetry(broken)

    def snapshot(self, size=13 * 1024**3 + 17, local=True):
        return (line(event="begin", frame=8, groups=1, records=1, whole_frame=False) +
                line(event="group", frame=8, category=2, device_local=local, count=1, bytes=size) +
                line(event="end", frame=8))

    def test_exact_bytes_and_locality(self):
        value = census.summarize_allocations(census.allocations(self.snapshot())[0])
        self.assertEqual(value["device_local_categories"], {"app_textures": 13 * 1024**3 + 17})
        host = census.summarize_allocations(census.allocations(self.snapshot(local=False))[0])
        self.assertEqual(host["device_local_categories"], {})

    def test_incomplete_or_mixed_samples_fail(self):
        good = self.snapshot()
        for body in (good[:good.rfind("[RTX Allocation]")], good.replace('"groups": 1', '"groups": 2'),
                     good.replace('"frame": 8', '"frame": 9', 1),
                     good.replace('"whole_frame": false', '"whole_frame": true'),
                     good.replace('"count": 1', '"count": 0'), good + line(event="end", frame=8)):
            with self.subTest(body=body), self.assertRaises(ValueError):
                census.allocations(body)

    def test_multiple_snapshots(self):
        self.assertEqual(len(census.allocations(self.snapshot() * 2)), 2)

    def test_source_completeness(self):
        body = 'R12_PROBE base {"textures":1}\nR12_TEXTURE base {"Name":"mmd/t/a","Size":123}\n'
        self.assertEqual(census.source_snapshots(body)["base"]["textures"][0]["Size"], 123)
        with self.assertRaises(ValueError):
            census.source_snapshots(body.split("R12_TEXTURE")[0])
        with self.assertRaises(ValueError):
            census.source_snapshots('R12_PROBE base {"textures":0,"truncated":true}\n')


if __name__ == "__main__":
    unittest.main()
