"""Catalogue audit counts are derived from the production Lua matcher and shared texture facts."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import json

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('eye_catalogue', ROOT / 'tools/qa/eye_white_catalogue.py')
catalogue = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalogue)


@unittest.skipUnless(Path(catalogue.luajit_path()).is_file(), 'LuaJIT is not installed')
class EyeCatalogueTests(unittest.TestCase):
    def test_lua_literal_preserves_quotes_controls_and_unicode(self):
        self.assertEqual(catalogue.classify([('顔（白目）', ''), ('unknown "\\\n', 'Eye White'),
                                              ('目白框', 'EyeWhite'), ('Face', '')]), [True, True, False, False])

    def test_audit_counts_surfaces_models_and_shared_atlases(self):
        report = catalogue.audit([
            {'id': 'one', 'materials': [{'name': '白目', 'shared': ['颜']}, {'name': '眼白右'}, {'name': '颜'}]},
            {'id': 'two', 'materials': [{'name': '目影'}, {'name': 'eye_back'}]}])
        self.assertEqual((report['models'], report['materials'], report['hit_models'], report['hit_materials'],
                          report['shared_texture_hit_models'], report['models_without_named_eye_white']), (2, 5, 1, 2, 1, 1))
        self.assertEqual(report['near_misses_for_review'][0]['name'], 'eye_back')

    def test_library_enriches_shared_facts_without_writing_input(self):
        scratch = ROOT / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            path = Path(temp) / 'id/manifest.json'
            path.parent.mkdir()
            path.write_text(json.dumps({'materials': [{'name': '白目', 'base': 'face.png'},
                                                      {'name': '颜', 'base': 'face.png'}]}), encoding='utf-8')
            before = path.read_bytes(), path.stat().st_mtime_ns
            models = catalogue.library_models(temp)
            self.assertEqual(models[0]['materials'][0]['shared'], ['颜'])
            self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)


if __name__ == '__main__':
    unittest.main()
