"""Make a smaller block-compressed 2D DDS by keeping mip 1 onward byte for byte.

Usage: python tools/sky/drop_top_mip.py SOURCE.dds OUTPUT.dds
See drop_top_mip.py.md for supported formats, validation and side effects.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys


class DdsError(ValueError):
    pass


def layout(data):
    """Validate a single 2D BC mip chain, returning header size, dimensions and mip byte sizes."""
    if len(data) < 128 or data[:4] != b'DDS ':
        raise DdsError('not a DDS header')
    if struct.unpack_from('<I', data, 4)[0] != 124 or struct.unpack_from('<I', data, 76)[0] != 32:
        raise DdsError('invalid DDS header size')
    flags, height, width, _, depth, count = struct.unpack_from('<6I', data, 8)
    if (flags & 0x81007 != 0x81007 or (count > 1 and not flags & 0x20000)
            or not struct.unpack_from('<I', data, 80)[0] & 4):
        raise DdsError('expected a compressed DDS with an explicit mip count and linear size')
    if (not width or not height or width & (width - 1) or height & (height - 1)
            or not 1 <= count <= max(width, height).bit_length()):
        raise DdsError('invalid power-of-two dimensions or mip count')
    if depth not in (0, 1) or struct.unpack_from('<I', data, 112)[0]:
        raise DdsError('volumes and cubemaps are unsupported')
    fourcc = data[84:88]
    header_size = 128
    if fourcc == b'DX10':
        if len(data) < 148:
            raise DdsError('truncated DX10 header')
        fmt, dimension, misc, array_size, _ = struct.unpack_from('<5I', data, 128)
        if dimension != 3 or misc & 4 or array_size != 1:
            raise DdsError('expected one DX10 2D texture, without a cubemap or array')
        if fmt in (70, 71, 72, 79, 80, 81):  # BC1, BC4 (typeless, UNORM, SRGB/SNORM)
            block_size = 8
        elif fmt in (73, 74, 75, 76, 77, 78, 82, 83, 84, 94, 95, 96, 97, 98, 99):
            block_size = 16  # BC2, BC3, BC5, BC6H, BC7
        else:
            raise DdsError('unsupported DXGI block format %d' % fmt)
        header_size = 148
    elif fourcc in (b'DXT1', b'ATI1', b'BC4U', b'BC4S'):
        block_size = 8
    elif fourcc in (b'DXT3', b'DXT5', b'ATI2', b'BC5U', b'BC5S'):
        block_size = 16
    else:
        raise DdsError('unsupported DDS FourCC %r' % fourcc)
    sizes = [max(1, (max(1, width >> i) + 3) // 4)
             * max(1, (max(1, height >> i) + 3) // 4) * block_size for i in range(count)]
    if len(data) != header_size + sum(sizes):
        raise DdsError('truncated mip chain or trailing bytes')
    if struct.unpack_from('<I', data, 20)[0] != sizes[0]:
        raise DdsError('linear size does not match mip 0')
    return header_size, width, height, sizes


def drop_top_mip(source):
    header_size, width, height, sizes = layout(source)
    if len(sizes) < 2:
        raise DdsError('at least two mips are required')
    header = bytearray(source[:header_size])
    struct.pack_into('<4I', header, 12, max(1, height // 2), max(1, width // 2), sizes[1],
                     struct.unpack_from('<I', header, 24)[0])
    struct.pack_into('<I', header, 28, len(sizes) - 1)
    if len(sizes) == 2:
        struct.pack_into('<I', header, 8, struct.unpack_from('<I', header, 8)[0] & ~0x20000)
        struct.pack_into('<I', header, 108, struct.unpack_from('<I', header, 108)[0] & ~0x400008)
    return bytes(header) + source[header_size + sizes[0]:]


def verify(source, result):
    """Check the resulting header and every retained compressed block, including source mip 1."""
    header, width, height, sizes = layout(source)
    new_header, new_width, new_height, new_sizes = layout(result)
    if ((new_header, new_width, new_height, new_sizes) !=
            (header, max(1, width // 2), max(1, height // 2), sizes[1:])
            or result[header:] != source[header + sizes[0]:]):
        raise DdsError('output differs from source mip 1 onward')
    return {'width': new_width, 'height': new_height, 'mips': len(new_sizes),
            'payload_bytes': sum(new_sizes), 'dropped_bytes': sizes[0],
            'mip1_sha256': hashlib.sha256(source[header + sizes[0]:header + sizes[0] + sizes[1]]).hexdigest(),
            'sha256': hashlib.sha256(result).hexdigest()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args(argv)
    try:
        source = args.source.read_bytes()
        result = drop_top_mip(source)
        verify(source, result)
        # Exclusive creation refuses an existing file, including the source itself.
        with args.output.open('xb') as target:
            target.write(result)
        summary = verify(source, args.output.read_bytes())
    except (OSError, DdsError) as error:
        print('drop_top_mip: %s' % error, file=sys.stderr)
        return 1
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
