"""Check the field-game launch policy without querying or changing a real process."""
import unittest
import sys

if sys.platform != "win32":
    raise unittest.SkipTest("The activity gate uses the Windows process APIs")

import game_activity


class GameActivityTests(unittest.TestCase):
    def test_gate(self):
        for field, unknown, foreground, idle, expected in (
            ([], [], 12, 0, False), ([10], [], 10, 3600, True),
            ([10], [], 12, 599.999, True), ([10], [], 12, 600, False),
            ([10], [], 12, 3600, False), ([], [20], 12, 3600, True),
        ):
            with self.subTest(field=field, unknown=unknown, foreground=foreground, idle=idle):
                self.assertEqual(game_activity.busy(field, unknown, foreground, idle), expected)


if __name__ == "__main__":
    unittest.main()
