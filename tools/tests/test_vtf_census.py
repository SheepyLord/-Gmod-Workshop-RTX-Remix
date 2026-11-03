"""Validate declared VTF sizes and supported shapes using generated headers."""
import struct
import unittest

import vtf_census


class VtfCensusTests(unittest.TestCase):
    def header(self):
        header = bytearray(80)
        header[:4] = b"VTF\0"
        struct.pack_into("<III", header, 4, 7, 2, 80)
        struct.pack_into("<HHIH", header, 16, 4096, 2048, 0, 1)
        struct.pack_into("<I", header, 52, 0)
        header[56] = 1
        struct.pack_into("<H", header, 63, 1)
        return header

    def test_exact_size_and_mips(self):
        header = self.header()
        self.assertEqual(vtf_census.rgba_header(header, 80 + 4096 * 2048 * 4)["logical_bytes"], 33554432)
        header[56] = 3
        self.assertEqual(vtf_census.rgba_header(header, 80 + (4096 * 2048 + 2048 * 1024 + 1024 * 512) * 4)["mips"], 3)

    def test_unsupported_and_invalid_stay_unknown(self):
        good = self.header()
        size = 80 + 4096 * 2048 * 4
        self.assertIsNone(vtf_census.rgba_header(good, size - 1))
        self.assertIsNone(vtf_census.rgba_header(good, size + 1))
        for offset, value in ((8, 5), (17, 0), (24, 2), (52, 15), (56, 0), (63, 2)):
            bad = good.copy()
            bad[offset] = value
            with self.subTest(offset=offset):
                self.assertIsNone(vtf_census.rgba_header(bad, size))


if __name__ == "__main__":
    unittest.main()
