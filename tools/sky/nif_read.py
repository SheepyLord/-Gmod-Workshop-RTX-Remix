"""Reads the shapes of a Skyrim LE NIF (20.2.0.7, user version 12, BS 83) far
enough to bake its sky textures: node transforms, NiTriShapeData vertices, UVs and triangles, and the
texture each shape's sky/effect shader uses. Usage: python -I tools/sky/nif_read.py <file.nif> [<out.json>]"""
import json
import struct
import sys


class Reader:
    def __init__(self, data, pos=0):
        self.d, self.p = data, pos

    def u8(self): v = self.d[self.p]; self.p += 1; return v
    def u16(self): v = struct.unpack_from('<H', self.d, self.p)[0]; self.p += 2; return v
    def u32(self): v = struct.unpack_from('<I', self.d, self.p)[0]; self.p += 4; return v
    def i32(self): v = struct.unpack_from('<i', self.d, self.p)[0]; self.p += 4; return v
    def f32(self): v = struct.unpack_from('<f', self.d, self.p)[0]; self.p += 4; return v
    def floats(self, n): v = struct.unpack_from(f'<{n}f', self.d, self.p); self.p += 4 * n; return list(v)
    def sized(self): n = self.u32(); s = self.d[self.p:self.p + n]; self.p += n; return s.decode('latin-1')
    def short(self): n = self.u8(); s = self.d[self.p:self.p + n]; self.p += n; return s.rstrip(b'\0').decode('latin-1')


def read(path):
    data = open(path, 'rb').read()
    end = data.index(b'\n')
    header = data[:end].decode('latin-1')
    r = Reader(data, end + 1)
    version = r.u32()
    r.u8()  # endian
    user = r.u32()
    nblocks = r.u32()
    bs = r.u32()
    r.short(); r.short(); r.short()  # author, process script, export script
    ntypes = r.u16()
    types = [r.sized() for _ in range(ntypes)]
    index = [r.u16() for _ in range(nblocks)]
    sizes = [r.u32() for _ in range(nblocks)]
    nstrings = r.u32()
    r.u32()  # max string length
    strings = [r.sized() for _ in range(nstrings)]
    ngroups = r.u32()
    r.p += 4 * ngroups
    blocks, pos = [], r.p
    for i in range(nblocks):
        blocks.append((types[index[i]], pos, sizes[i]))
        pos += sizes[i]
    info = {'header': header, 'version': hex(version), 'user': user, 'bs': bs, 'blocks': []}

    def name_of(k):
        return strings[k] if 0 <= k < len(strings) else None

    def av_object(b):
        # NiObjectNET: name (string index), extra data list, controller; NiAVObject (BS 83): uint flags,
        # translation, rotation (3x3, rows), scale, collision object.
        name = name_of(b.i32())
        n = b.u32(); b.p += 4 * n
        b.i32()
        flags = b.u32()
        t = b.floats(3)
        m = b.floats(9)
        s = b.f32()
        b.i32()
        return {'name': name, 'flags': flags, 'translation': t, 'rotation': m, 'scale': s}

    for i, (kind, start, size) in enumerate(blocks):
        b = Reader(data, start)
        entry = {'index': i, 'type': kind}
        if kind in ('NiNode', 'BSFadeNode', 'BSMultiBoundNode'):
            entry.update(av_object(b))
            n = b.u32()
            entry['children'] = [b.i32() for _ in range(n)]
        elif kind == 'NiTriShape':
            entry.update(av_object(b))
            entry['data'] = b.i32()
            b.i32()  # skin instance
            nmat = b.u32(); b.p += 8 * nmat
            b.i32(); b.u8()  # active material, dirty flag
            entry['shader'] = b.i32()
            entry['alpha'] = b.i32()
        elif kind == 'NiTriShapeData':
            b.i32()  # group id
            nv = b.u16()
            b.u8(); b.u8()  # keep, compress flags
            has_v = b.u8()
            verts = b.floats(3 * nv) if has_v else []
            vflags = b.u16()
            b.u32()  # material CRC (BS > 0)
            has_n = b.u8()
            if has_n:
                b.p += 12 * nv
                if vflags & 4096:
                    b.p += 24 * nv
            b.floats(4)  # center, radius
            has_c = b.u8()
            if has_c:
                b.p += 16 * nv
            nuv = vflags & 1
            uvs = b.floats(2 * nv) if nuv else []
            b.u16()  # consistency
            b.i32()  # additional data
            ntri = b.u16()
            b.u32()  # num triangle points
            has_t = b.u8()
            tris = [b.u16() for _ in range(3 * ntri)] if has_t else []
            entry.update({'vertices': nv, 'v': verts, 'uv': uvs, 'triangles': ntri, 't': tris, 'vector_flags': vflags})
        elif kind in ('BSSkyShaderProperty', 'BSEffectShaderProperty', 'BSLightingShaderProperty'):
            # Keep any texture-looking strings inside the block.
            chunk = data[start:start + size]
            entry['textures'] = sorted(set(s.decode('latin-1') for s in __import__('re').findall(rb'[A-Za-z0-9_\\/ .-]{4,}\.dds', chunk)))
        info['blocks'].append(entry)
    return info


if __name__ == '__main__':
    info = read(sys.argv[1])
    print(info['header'], info['version'], 'user', info['user'], 'bs', info['bs'])
    for e in info['blocks']:
        extra = ''
        if 'vertices' in e:
            extra = f"verts {e['vertices']} tris {e['triangles']} uv {bool(e['uv'])} flags {e['vector_flags']}"
        elif 'textures' in e:
            extra = str(e['textures'])
        elif 'translation' in e:
            extra = f"name {e['name']} t {[round(x, 2) for x in e['translation']]} s {e['scale']:.3f} data {e.get('data')} shader {e.get('shader')} children {e.get('children')}"
        print(e['index'], e['type'], extra)
    if len(sys.argv) > 2:
        json.dump(info, open(sys.argv[2], 'w'))
