"""Validate explicit, hash-pinned pending runtime additions without weakening packaged provenance."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools'))
import check_repo


class PendingRuntimePatchTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(prefix='pending-runtime-', dir=scratch)
        self.root = Path(self.tmp.name)
        self.runtime = self.root / 'runtime'
        (self.runtime / 'patches').mkdir(parents=True)
        self.old = 'patches/0033-old.patch'
        self.new = 'patches/0040-new.patch'
        (self.runtime / self.old).write_bytes(b'old')
        (self.runtime / self.new).write_bytes(b'new')
        digest = lambda value: hashlib.sha256(value).hexdigest()
        self.base = {'commit': 'base', 'submodules': {}, 'clones': {},
                     'packaged': {'commit': 'base', 'submodules': {}, 'clones': {},
                                  'files': {self.old: digest(b'old')}},
                     'pending_patches': {'why': 'integration imports once', 'files': {self.new: digest(b'new')}}}

    def tearDown(self):
        self.tmp.cleanup()

    def check(self):
        (self.runtime / 'base.json').write_text(json.dumps(self.base), encoding='utf-8')
        return check_repo.check_runtime_record(self.root)

    def test_only_declared_new_patch_is_pending(self):
        self.assertEqual(self.check(), [])
        (self.runtime / self.new).write_bytes(b'changed')
        self.assertTrue(self.check())
        (self.runtime / self.new).unlink()
        self.assertTrue(self.check())

    def test_existing_packaged_patch_cannot_be_exempted(self):
        self.base['pending_patches']['files'][self.old] = hashlib.sha256(b'changed').hexdigest()
        (self.runtime / self.old).write_bytes(b'changed')
        self.assertTrue(self.check())

    def test_undeclared_addition_and_source_setting_fail(self):
        (self.runtime / 'patches/0041-extra.patch').write_bytes(b'extra')
        self.assertTrue(self.check())
        (self.runtime / 'patches/0041-extra.patch').unlink()
        self.base['commit'] = 'different'
        self.assertTrue(self.check())

    def test_no_empty_malformed_or_stale_records(self):
        for value in ({}, {'why': 'x', 'files': {}}, {'why': '', 'files': {self.new: 'bad'}},
                      {'why': 'x', 'files': {'../escape.patch': '0' * 64}}, 'skip'):
            self.base['pending_patches'] = value
            self.assertTrue(self.check(), value)

    def test_imported_patch_requires_pending_record_to_be_cleared(self):
        self.base['packaged']['files'].update(self.base['pending_patches']['files'])
        self.assertTrue(self.check())
        del self.base['pending_patches']
        self.assertEqual(self.check(), [])


if __name__ == '__main__':
    unittest.main()
