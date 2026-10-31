import contextlib
import io
from pathlib import Path
import struct
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools/sky'))
import drop_top_mip as dds


# Independent fixture format table: (FourCC, DXGI format, bytes per 4x4 block).
# Include every variant accepted by the tool, without using its layout() to make expected sizes.
FORMATS = (
    (b'DXT1', None, 8), (b'DXT3', None, 16), (b'DXT5', None, 16),
    (b'ATI1', None, 8), (b'ATI2', None, 16),
    (b'BC4U', None, 8), (b'BC4S', None, 8),
    (b'BC5U', None, 16), (b'BC5S', None, 16),
    *((b'DX10', fmt, 8) for fmt in (70, 71, 72, 79, 80, 81)),  # BC1, BC4
    *((b'DX10', fmt, 16) for fmt in (73, 74, 75, 76, 77, 78, 82, 83, 84,
                                   94, 95, 96, 97, 98, 99)),  # BC2/3/5/6H/7
)


def fixture(width=16, height=8, count=5, fourcc=b'DXT5', fmt=98, block=16):
    sizes = [max(1, (max(1, width >> i) + 3) // 4)
             * max(1, (max(1, height >> i) + 3) // 4) * block for i in range(count)]
    header = bytearray(148 if fourcc == b'DX10' else 128)
    header[:4] = b'DDS '
    struct.pack_into('<7I', header, 4, 124, 0xa1007, height, width, sizes[0], 1, count)
    struct.pack_into('<2I4s', header, 76, 32, 4, fourcc)
    struct.pack_into('<I', header, 108, 0x401008)
    if fourcc == b'DX10':
        struct.pack_into('<5I', header, 128, fmt, 3, 0, 1, 0)
    payload = b''.join(bytes([i + 1]) * size for i, size in enumerate(sizes))
    return bytes(header) + payload, sizes, len(header)


class DropTopMipTests(unittest.TestCase):
    def test_legacy_and_dx10_mips_are_kept_exactly(self):
        for fourcc, fmt, block in FORMATS:
            with self.subTest(fourcc=fourcc, fmt=fmt, block=block):
                source, sizes, header = fixture(fourcc=fourcc, fmt=fmt, block=block)
                self.assertEqual(sizes, [8 * block, 2 * block, block, block, block])
                self.assertEqual(dds.layout(source), (header, 16, 8, sizes))
                self.assertEqual(struct.unpack_from('<I', source, 20)[0], 8 * block)
                result = dds.drop_top_mip(source)
                self.assertEqual(result[header:], source[header + sizes[0]:])
                self.assertEqual(result[header:header + sizes[1]], bytes([2]) * sizes[1])
                self.assertEqual(struct.unpack_from('<4I', result, 12), (4, 8, 2 * block, 1))
                self.assertEqual(struct.unpack_from('<I', result, 28)[0], 4)
                self.assertEqual(result[32:header], source[32:header])
                info = dds.verify(source, result)
                self.assertEqual((info['payload_bytes'], info['dropped_bytes']), (sum(sizes[1:]), sizes[0]))

    def test_each_format_refuses_a_wrong_block_linear_size(self):
        for fourcc, fmt, block in FORMATS:
            with self.subTest(fourcc=fourcc, fmt=fmt):
                source, _, _ = fixture(fourcc=fourcc, fmt=fmt, block=block)
                changed = bytearray(source)
                struct.pack_into('<I', changed, 20, 8 * (24 - block))  # the other block size
                with self.assertRaisesRegex(dds.DdsError, 'linear size'):
                    dds.drop_top_mip(changed)

    def test_small_mips_still_have_one_block_and_last_mip_clears_caps(self):
        for fourcc, fmt, block in FORMATS:
            with self.subTest(fourcc=fourcc, fmt=fmt):
                source, sizes, header = fixture(width=2, height=2, count=2,
                                               fourcc=fourcc, fmt=fmt, block=block)
                self.assertEqual(sizes, [block, block])
                result = dds.drop_top_mip(source)
                self.assertEqual(result[header:], bytes([2]) * block)
                self.assertEqual(struct.unpack_from('<3I', result, 12), (1, 1, block))
                self.assertFalse(struct.unpack_from('<I', result, 8)[0] & 0x20000)
                self.assertFalse(struct.unpack_from('<I', result, 108)[0] & 0x400008)
                self.assertEqual(dds.verify(source, result)['mips'], 1)
                with self.assertRaises(dds.DdsError):
                    dds.drop_top_mip(result)

    def test_refuses_bad_headers_unsupported_images_and_wrong_lengths(self):
        source, _, _ = fixture()
        bad = [b'', source[:100], source[:-1], source + b'x', fixture(count=1)[0]]
        for offset, value in [(4, 123), (76, 31), (16, 15), (12, 0), (28, 20), (24, 2),
                              (112, 0x200), (20, 1), (80, 0), (8, 0)]:
            changed = bytearray(source)
            struct.pack_into('<I', changed, offset, value)
            bad.append(changed)
        bad.append(fixture(fourcc=b'RGBA')[0])
        dx10, _, _ = fixture(fourcc=b'DX10')
        bad.append(dx10[:140])
        for offset, value in [(128, 28), (132, 4), (136, 4), (140, 2)]:
            changed = bytearray(dx10)
            struct.pack_into('<I', changed, offset, value)
            bad.append(changed)
        for data in bad:
            with self.subTest(header=bytes(data[:32])), self.assertRaises(dds.DdsError):
                dds.drop_top_mip(data)

    def test_verification_catches_changed_retained_data(self):
        source, _, _ = fixture()
        result = bytearray(dds.drop_top_mip(source))
        result[-1] ^= 1
        with self.assertRaises(dds.DdsError):
            dds.verify(source, result)

    def test_cli_refuses_overwrites_and_leaves_source_untouched(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            source, output = Path(folder) / 'source.dds', Path(folder) / 'output.dds'
            data = fixture()[0]
            source.write_bytes(data)
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(dds.main([str(source), str(output)]), 0)
                self.assertEqual(dds.main([str(source), str(output)]), 1)
                self.assertEqual(dds.main([str(source), str(source)]), 1)
            self.assertEqual(source.read_bytes(), data)
            dds.verify(data, output.read_bytes())


if __name__ == '__main__':
    unittest.main()
