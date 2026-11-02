"""R10 expression binding, corpus-derived tables, overflow playback and NPC map readiness."""
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

import mmd_morph_corpus as corpus

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / 'packages/character-motion-importer/mmd_vmd_npc'
HOTLOADER = REPO / 'packages/model-hotloader/mmd_hotloader/lua/mmdhl'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


def lua(value):
    if value is None: return 'nil'
    if isinstance(value, bool): return str(value).lower()
    if isinstance(value, str):
        return '"' + ''.join(('\\%03d' % ord(c)) if ord(c) < 32 else '\\\\' if c == '\\' else '\\"' if c == '"' else c for c in value) + '"'
    if isinstance(value, (int, float)): return str(value)
    if isinstance(value, list): return '{' + ','.join(map(lua, value)) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'


def pmx_fixture(cycle=False, cancel=False, partial=False):
    pack = lambda fmt, *v: struct.pack('<' + fmt, *v)
    text = lambda s: pack('i', len(s.encode('utf-16-le'))) + s.encode('utf-16-le')
    out = bytearray(b'PMX ' + pack('fB8B', 2., 8, 0, 0, 1, 1, 1, 1, 1, 1))
    out += b''.join(text(s) for s in ('fixture', '', '', ''))
    out += pack('i', 2)
    for x in (1., -1.): out += pack('8fBBf', x, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1.)
    out += pack('iii', 0, 0, 1)  # zero indices/textures, one material
    out += text('fixture') + text('') + pack('11fB5fbbBBB', *([0.] * 11), 0, *([0.] * 5), -1, -1, 0, 1, 0)
    out += text('') + pack('ii', 0, 0)  # zero faces, zero bones
    out += pack('i', 4)
    for name, vertex in (('Left', 0), ('Right', 1)):
        out += text(name) + text('') + pack('BBiB3f', 2, 1, 1, vertex, 0., -1., 0.)
    children = [(2 if cycle else 0, 1.), (3 if partial else 1, 1.)]
    if cancel: children.append((0, -1.))
    out += text('Both') + text('') + pack('BBi', 2, 0, len(children))
    for child, weight in children: out += pack('bf', child, weight)
    out += text('Material') + text('') + pack('BBibB28f', 4, 8, 1, -1, 1, *([0.] * 28))
    return bytes(out)


class CorpusTests(unittest.TestCase):
    def test_measured_sides_and_shipped_table(self):
        fixture = json.loads(Path(__file__).with_name('mmd_morph_statistics.json').read_text(encoding='utf8'))
        table = json.loads((ADDON / 'data_static/mmd_vmd_npc/morph_semantics.json').read_text(encoding='utf8'))
        self.assertEqual(fixture['models'], 1225)
        self.assertEqual(fixture['statistics']['笑い']['sides']['both'], 999)
        self.assertEqual(fixture['statistics']['ウィンク']['sides']['left'], 971)
        self.assertEqual(fixture['statistics']['EL_Happy_l_CLO']['sides']['right'], 345)
        self.assertEqual(table['standard']['笑い']['side'], 'both')
        self.assertEqual(table['standard']['笑い']['source'], 'eyes_blink_smile')
        self.assertEqual(table['standard']['はぅ']['source'], 'eyes_sqeeze')
        self.assertEqual(table['standard']['なごみ']['source'], 'eyes_peaceful')
        for name, meaning in fixture['accepted_aliases'].items():
            self.assertEqual(table['aliases'][name]['meaning'], meaning)
        for alias in table['aliases'].values(): self.assertGreaterEqual(alias['observations'], 3)
        self.assertEqual(table['aliases']['EL_Happy_l_CLO']['meaning'], 'blink_smile')
        # Side is deliberately absent from mined aliases; the model supplies it.
        self.assertNotIn('side', table['aliases']['EL_Happy_l_CLO'])

    def test_group_mining_does_not_confuse_parts_with_whole_expressions(self):
        standard = {'笑い': {'meaning': 'blink_smile', 'side': 'both'}}
        def model(children):
            return {'morphs': [{'name': '笑い', 'children': children},
                              {'name': 'A', 'left': 1.}, {'name': 'B', 'left': 0.}]}
        evidence, _ = corpus.mine_groups([model([('A', 1), ('B', 1)])], standard)
        self.assertEqual(evidence['A']['blink_smile'], 1)
        evidence, _ = corpus.mine_groups([model([('A', 1), ('B', .5)])], standard)
        self.assertFalse(evidence)
        evidence, _ = corpus.mine_groups([model([('A', 1), ('B', 1), ('A', .1)])], standard)
        self.assertFalse(evidence)

    def test_offset_similarity_checks_direction_and_unit_weight(self):
        a = {0: (0., -1., 0.), 1: (1., 0., 0.)}
        self.assertEqual(corpus.similarity(a, a), (1., 1.))
        self.assertLess(corpus.similarity(a, {i: tuple(-x for x in v) for i, v in a.items()})[0], 0)
        self.assertEqual(corpus.similarity(a, {i: tuple(2*x for x in v) for i, v in a.items()})[1], .5)

    def test_cp932_is_complete_and_width_sensitive(self):
        table = json.loads((ADDON / 'data_static/mmd_vmd_npc/cp932.json').read_text(encoding='utf8'))
        self.assertEqual(table, corpus.cp932_table())
        self.assertNotEqual('ｳｨﾝｸ２右'.encode('cp932'), 'ウィンク２右'.encode('cp932'))


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class LuaMorphTests(unittest.TestCase):
    def test_production_matcher_importer_and_actor_lifecycle(self):
        data_root = ADDON / 'data_static/mmd_vmd_npc'
        data = {k: json.loads((data_root / f).read_text(encoding='utf8')) for k, f in (
            ('semantics', 'morph_semantics.json'), ('aliases', 'flex_mapping_table.json'), ('cp932', 'cp932.json'))}
        data.update(rawA='SmileA', rawB='SmileB', longVMD='123456789012345', longDecoded='123456789012345')
        core = (ADDON / 'lua/mmd_vmd_npc/sh_core.lua').read_text(encoding='utf8')
        data['bindingCode'] = core[core.index('-- R10 PMX binding helpers'):core.index('-- End R10 PMX binding helpers.')]
        carrier = (HOTLOADER / 'carrier.lua').read_text(encoding='utf8')
        data['geometryCode'] = carrier[carrier.index('-- R10 PMX geometry helpers'):carrier.index('-- End R10 PMX geometry helpers.')]
        autorun = (HOTLOADER.parent / 'autorun/mmdhl.lua').read_text(encoding='utf8')
        data['mountCode'] = autorun[autorun.index('local mountedPackages={}'):autorun.index('function mmdhl.Decode(')]
        data['cacheCode'] = ('local function trim(v) return string.Trim(v) end\n'
                             + next(line for line in core.splitlines() if line.startswith('MMDVMDNPC.BuiltFormat =')) + '\n'
                             + core[core.index('function MMDVMDNPC.NormalizeMotionID('):core.index('function MMDVMDNPC.Chat(')])
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='morphs-', dir=scratch) as tmp:
            tmp = Path(tmp)
            fixture = tmp / 'fixture.lua'
            fixture.write_text('return ' + lua(data), encoding='utf8')
            cases = [('matcher', ''), ('actor', ''), ('mount', '')]
            for name, content in [('valid.pmx', pmx_fixture()), ('invalid-cycle.pmx', pmx_fixture(True)),
                                  ('cancel.pmx', pmx_fixture(cancel=True)), ('partial.pmx', pmx_fixture(partial=True)),
                                  ('invalid-truncated.pmx', pmx_fixture()[:85])]:
                path = tmp / name
                path.write_bytes(content)
                cases.append(('geometry', str(path)))
            for mode, pmx in cases:
                with self.subTest(mode=mode, pmx=Path(pmx).name):
                    result = subprocess.run([LUAJIT, str(Path(__file__).with_name('mmd_morph_harness.lua')),
                                             mode, str(ADDON / 'lua/mmd_vmd_npc'), str(HOTLOADER),
                                             str(fixture), pmx], cwd=REPO, capture_output=True,
                                            encoding='utf8', errors='replace', timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('PASS ' + mode, result.stdout)


if __name__ == '__main__':
    unittest.main()
