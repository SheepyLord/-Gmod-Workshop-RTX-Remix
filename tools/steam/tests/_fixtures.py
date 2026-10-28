"""Builders for synthetic Steam ContentManifest files used by the tests."""

import hashlib
import struct
import tempfile
from pathlib import Path

from steam_manifest import FLAG_DIRECTORY, METADATA_MAGIC, PAYLOAD_MAGIC

END_MAGIC = 0x32C415AB
REPO = Path(__file__).resolve().parents[3]
SCRATCH = REPO / 'out' / 'tmp'  # AGENTS.md rule 9, whoever runs the tests and whatever TEMP says


def scratch_folder(prefix):
    """A TemporaryDirectory under the repo's out/tmp (created if missing)."""
    SCRATCH.mkdir(parents=True, exist_ok=True)
    return tempfile.TemporaryDirectory(dir=SCRATCH, prefix=prefix)


def _varint(n):
    out = bytearray()
    while True:
        b, n = n & 0x7F, n >> 7
        out.append(b | 0x80 if n else b)
        if not n:
            return bytes(out)


def _field(number, payload):
    """Encode a varint field (int payload) or a length-delimited field (bytes payload)."""
    if isinstance(payload, int):
        return _varint(number << 3) + _varint(payload)
    return _varint(number << 3 | 2) + _varint(len(payload)) + payload


def entry(path, data=None, flags=0, sha=None):
    """One file entry; data=None makes a directory entry. sha overrides the stored hash bytes."""
    if data is None:
        flags |= FLAG_DIRECTORY
    return path, data, flags, sha


def build_manifest(entries, depot_id=4002, manifest_id=7341198560151933050, encrypted=False):
    payload = b''
    for path, data, flags, sha in entries:
        msg = _field(1, path.encode()) + _field(2, 0 if data is None else len(data)) + _field(3, flags)
        if sha is not None:
            msg += _field(5, sha)
        elif data is not None:
            msg += _field(5, hashlib.sha1(data).digest())
        payload += _field(1, msg)
    meta = _field(1, depot_id) + _field(2, manifest_id) + _field(4, int(encrypted))
    return (struct.pack('<II', PAYLOAD_MAGIC, len(payload)) + payload
            + struct.pack('<II', METADATA_MAGIC, len(meta)) + meta + struct.pack('<I', END_MAGIC))


def write_tree(root, files):
    """Create files under root from a {relative path: bytes} mapping."""
    for rel, data in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
