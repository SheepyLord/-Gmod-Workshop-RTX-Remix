"""Read Steam depot ContentManifest files and find the ones a Steam install uses.

A manifest lists every file of one depot version with its size, flags and SHA-1.
The Steam client caches them as <Steam>/depotcache/<depot>_<manifest>.manifest.
"""

import argparse
import hashlib
import os
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vdf  # noqa: E402

PAYLOAD_MAGIC = 0x71F617D0
METADATA_MAGIC = 0x1F4812BE

# EDepotFileFlag values that matter here.
FLAG_USERCONFIG = 0x1    # the user may change it; Steam only installs it when missing
FLAG_DIRECTORY = 0x40
FLAG_SYMLINK = 0x200

_NO_HASH = '0' * 40


@dataclass(frozen=True)
class ManifestFile:
    path: str        # relative, '/'-separated, as listed in the depot
    size: int
    flags: int
    sha1: str | None  # hex; None for directories and entries without a hash

    @property
    def is_dir(self):
        return bool(self.flags & FLAG_DIRECTORY)

    @property
    def is_userconfig(self):
        return bool(self.flags & FLAG_USERCONFIG)

    @property
    def is_symlink(self):
        return bool(self.flags & FLAG_SYMLINK)


@dataclass
class Manifest:
    source: str
    depot_id: int | None = None
    manifest_id: int | None = None
    filenames_encrypted: bool = False
    files: list[ManifestFile] = field(default_factory=list)


@dataclass
class InstallInfo:
    install: Path
    appid: str
    library: Path            # the steamapps directory holding the app manifest
    manifests: list[Path]    # cached depot manifests for the installed depots


def _varint(buf, pos):
    result = shift = 0
    while True:
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, pos
        shift += 7


def _fields(buf):
    """Yield (field number, value) for one protobuf message."""
    pos = 0
    while pos < len(buf):
        key, pos = _varint(buf, pos)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, pos = _varint(buf, pos)
        elif wire == 1:
            value, pos = buf[pos:pos + 8], pos + 8
        elif wire == 2:
            length, pos = _varint(buf, pos)
            value, pos = buf[pos:pos + length], pos + length
        elif wire == 5:
            value, pos = buf[pos:pos + 4], pos + 4
        else:
            raise ValueError(f'unsupported protobuf wire type {wire}')
        yield number, value


def safe_relpath(path):
    """Return a manifest path as a PurePosixPath, refusing absolute or escaping paths."""
    p = PurePosixPath(path.replace('\\', '/'))
    if not p.parts or p.is_absolute() or ':' in p.parts[0] or '..' in p.parts:
        raise ValueError(f'unsafe path in manifest: {path!r}')
    return p


def parse_manifest(path):
    data = Path(path).read_bytes()
    if len(data) < 8:
        raise ValueError(f'{path}: too short for a manifest')
    magic, length = struct.unpack_from('<II', data, 0)
    if magic != PAYLOAD_MAGIC:
        raise ValueError(f'{path}: not a ContentManifest (magic {magic:#010x})')
    manifest = Manifest(source=str(path))
    for number, value in _fields(data[8:8 + length]):
        if number != 1:
            continue
        name, size, flags, sha1 = None, 0, 0, None
        for n2, v2 in _fields(value):
            if n2 == 1:
                name = v2.decode('utf-8')
            elif n2 == 2:
                size = v2
            elif n2 == 3:
                flags = v2
            elif n2 == 5 and v2:
                sha1 = v2.hex()
        if name is None:
            raise ValueError(f'{path}: file entry without a name')
        if sha1 == _NO_HASH or flags & FLAG_DIRECTORY:
            sha1 = None
        manifest.files.append(ManifestFile(name.replace('\\', '/'), size, flags, sha1))
    offset = 8 + length
    if offset + 8 <= len(data):
        magic, length = struct.unpack_from('<II', data, offset)
        if magic == METADATA_MAGIC:
            for number, value in _fields(data[offset + 8:offset + 8 + length]):
                if number == 1:
                    manifest.depot_id = value
                elif number == 2:
                    manifest.manifest_id = value
                elif number == 4:
                    manifest.filenames_encrypted = bool(value)
    return manifest


def sha1_file(path, chunk=8 << 20):
    h = hashlib.sha1()
    with open(path, 'rb') as fh:
        for block in iter(lambda: fh.read(chunk), b''):
            h.update(block)
    return h.hexdigest()


def steam_root():
    """Steam client directory from the registry, or None."""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam') as key:
            value, _ = winreg.QueryValueEx(key, 'SteamPath')
        return Path(value)
    except (ImportError, OSError):
        return None


def locate_install(install, steam_dir=None):
    """Find the app manifest and cached depot manifests for a Steam-managed install.

    The install must sit at <library>/steamapps/common/<installdir>. Raises
    FileNotFoundError naming whatever is missing.
    """
    install = Path(install).resolve()
    library = install.parent.parent
    if install.parent.name.lower() != 'common' or library.name.lower() != 'steamapps':
        raise FileNotFoundError(f'{install} is not under <library>/steamapps/common/')
    for acf in sorted(library.glob('appmanifest_*.acf')):
        state = vdf.load(acf).get('AppState', {})
        if state.get('installdir', '').lower() != install.name.lower():
            continue
        steam_dir = Path(steam_dir) if steam_dir else steam_root()
        if steam_dir is None:
            raise FileNotFoundError('Steam directory not found; pass --steam-dir')
        manifests, missing = [], []
        for depot, info in state.get('InstalledDepots', {}).items():
            candidate = steam_dir / 'depotcache' / f"{depot}_{info.get('manifest')}.manifest"
            (manifests if candidate.is_file() else missing).append(candidate)
        if missing:
            raise FileNotFoundError('depot manifests not cached: ' + ', '.join(map(str, missing)))
        return InstallInfo(install, state.get('appid', ''), library, manifests)
    raise FileNotFoundError(f'no appmanifest_*.acf in {library} has installdir "{install.name}"')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('info', help='depot id, manifest id and totals of manifest files')
    p.add_argument('manifest', nargs='+')
    p = sub.add_parser('files', help='list the files of a manifest')
    p.add_argument('manifest')
    p = sub.add_parser('locate', help='find the cached manifests of a Steam install')
    p.add_argument('install')
    p.add_argument('--steam-dir')
    a = ap.parse_args(argv)

    if a.cmd == 'info':
        for path in a.manifest:
            m = parse_manifest(path)
            files = [f for f in m.files if not f.is_dir]
            print(f'{path}: depot {m.depot_id} manifest {m.manifest_id} '
                  f'files {len(files)} bytes {sum(f.size for f in files)} '
                  f'encrypted-names {m.filenames_encrypted}')
    elif a.cmd == 'files':
        for f in parse_manifest(a.manifest).files:
            kind = 'dir ' if f.is_dir else 'cfg ' if f.is_userconfig else 'file'
            print(f'{kind} {f.size:>12} {f.sha1 or "-":40} {f.path}')
    else:
        info = locate_install(a.install, a.steam_dir)
        print(f'appid {info.appid} library {info.library}')
        for path in info.manifests:
            print(path)
    return 0


if __name__ == '__main__':
    sys.exit(main())
