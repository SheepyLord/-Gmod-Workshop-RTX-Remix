"""Check that the built x64 bootstrap imports only KERNEL32, using only the standard library."""
import struct
import sys
from pathlib import Path


def imports(path):
    data = Path(path).read_bytes()

    def unpack(fmt, offset):
        return struct.unpack_from('<' + fmt, data, offset)

    if data[:2] != b'MZ':
        raise ValueError('not a PE image')
    pe, = unpack('I', 0x3c)
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('invalid PE signature')
    machine, sections = unpack('HH', pe + 4)
    optional_size, = unpack('H', pe + 20)
    optional = pe + 24
    magic, = unpack('H', optional)
    if machine != 0x8664 or magic != 0x20b:
        raise ValueError('expected AMD64 PE32+')
    image_base, = unpack('Q', optional + 24)
    headers, = unpack('I', optional + 60)
    table = optional + optional_size

    def offset(rva):
        if rva < headers:
            return rva
        for i in range(sections):
            size, start, raw_size, raw = unpack('IIII', table + i * 40 + 8)
            if start <= rva < start + max(size, raw_size):
                if rva - start >= raw_size:
                    raise ValueError('import RVA outside raw section')
                return raw + rva - start
        raise ValueError('unmapped import RVA')

    def name(rva):
        start = offset(rva)
        return data[start:data.index(b'\0', start)].decode('ascii').lower()

    result = set()
    for index, width, name_index in ((1, 20, 3), (13, 32, 1)):
        rva, size = unpack('II', optional + 112 + index * 8)
        if not rva:
            continue
        start = offset(rva)
        for at in range(start, start + size, width):
            fields = unpack('I' * (width // 4), at)
            if not any(fields):
                break
            name_rva = fields[name_index]
            if index == 13 and not fields[0] & 1:
                name_rva -= image_base
            result.add(name(name_rva))
        else:
            raise ValueError('unterminated import descriptor list')
    return result


if __name__ == '__main__':
    actual = imports(sys.argv[1])
    if actual != {'kernel32.dll'}:
        sys.exit('unexpected bootstrap imports: ' + ', '.join(sorted(actual)))
    print('winmm imports only KERNEL32.dll (static and delay-load directories checked)')
