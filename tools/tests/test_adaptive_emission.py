"""Offline regression tests for rpai eye emission, published-layer edits and packaging."""
import contextlib
import hashlib
import importlib.util
import io
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
SKILL = REPO / 'skills' / 'mmd-remix-pbr'
sys.path.insert(0, str(SKILL / 'tool'))
from rpai import cli, config, dds, usda


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, SKILL / 'scripts' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


edit = load_script('set_adaptive_emission')
package = load_script('package_characters')


def layer_bytes(*materials):
    blocks = '\n\n'.join(usda.material_block(*m) for m in materials)
    return ('#usda 1.0\nover "RootNode"\n{\n    over "Looks"\n    {\n'
            + blocks + '\n    }\n}\n').encode('utf-8')


EMITTING = ('0123456789ABCDEF', {'emissive': '../textures/eyes.dds'}, 0, 0.6)
UNLIT = ('FEDCBA9876543210', {'roughness': '../textures/cloth.dds'}, 0, 0)


class ScratchTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch, prefix='c16-content-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path


class WriterTests(ScratchTests):
    def test_writer_adds_once_beside_unchanged_fallback_and_not_without_map(self):
        block = usda.material_block(*EMITTING, emissive_adaptive_intensity=10 / 3)
        self.assertEqual(block.count('float inputs:emissive_adaptive_intensity ='), 1)
        self.assertIn('float inputs:emissive_intensity = 0.6\n'
                      '                float inputs:emissive_adaptive_intensity = 3.33333333', block)
        plain = usda.material_block(*UNLIT)
        self.assertEqual(usda.material_block(*UNLIT, emissive_adaptive_intensity=2), plain)
        self.assertNotIn('emissive_adaptive_intensity', usda.material_block(*EMITTING))

    def test_writer_rejects_unrepresentable_inputs(self):
        for value in (-1, math.inf, math.nan, 65505):
            with self.subTest(value=value), self.assertRaises(ValueError):
                usda.material_block(*EMITTING, emissive_adaptive_intensity=value)
        self.assertIn('= 65504', usda.material_block(*EMITTING, emissive_adaptive_intensity=65504))
        self.assertIn('inputs:emissive_adaptive_intensity = 0',
                      usda.material_block(*EMITTING, emissive_adaptive_intensity=0))

    def test_layer_keeps_old_tuple_api_and_new_input(self):
        path = self.root / 'models' / 'test.usda'
        materials = [(EMITTING[0], EMITTING[1], 0.6), (UNLIT[0], UNLIT[1], 0, None),
                     (EMITTING[0], EMITTING[1], 0.6, None, 10 / 3)]
        usda.write_model_layer(path, materials, 0, 'test')
        self.assertEqual(path.read_text().count('float inputs:emissive_adaptive_intensity ='), 1)

    def test_mid_exposure_preserves_class_weights_for_different_atlases(self):
        # compose normalises the map by its largest class weight S, then publish restores S*I: at
        # exposure 1 (L 0.18) every class and atlas gets the same factor over its old fixed level.
        ratio = config.Settings().emissive_adaptive_intensity
        self.assertEqual(ratio, 25.0)  # ADR 0069: 4.5x the old level at exposure 1
        for weight, scale, level in ((0.025, 0.6, 1), (0.025, 0.04, 0.7), (0.04, 0.04, 1), (0.6, 0.6, 1)):
            colour = 0.8
            texel = colour * weight / scale
            fixed = texel * scale * level
            adaptive = texel * (scale * level * ratio) * 0.18
            self.assertAlmostEqual(adaptive, 4.5 * fixed)

    def publish(self, generated, multiplier=None):
        settings = config.Settings(emissive_intensity=0.7)
        if multiplier is not None:
            settings.emissive_adaptive_intensity = multiplier
        png = self.write('work/eyes.png', b'generated fixture; no image decoder needed')
        for info in generated.values():
            info['maps'] = {kind: str(png) for kind in info['maps']}
        hashes = {key: {'use': [f'{i:016X}', f'{i + 10:016X}']}
                  for i, key in enumerate(generated, start=1)}
        ctx = SimpleNamespace(key='model', settings=settings, args=SimpleNamespace(no_prune=True),
                              asset=SimpleNamespace(asset_id='abc'),
                              read=lambda name: generated if name == 'generated.json' else {'textures': hashes},
                              mod_dir=lambda: self.root / 'mod')

        def encode(jobs, **kwargs):
            for source, dest, kind in jobs:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(b'DDS fixture ' + kind.encode())

        with patch.object(dds, 'encode', side_effect=encode), contextlib.redirect_stdout(io.StringIO()):
            cli.cmd_publish(ctx)
        return (self.root / 'mod' / 'models' / 'model.usda').read_text()

    def test_publish_uses_cached_eye_classes_and_keeps_other_emitters_fixed(self):
        generated = {
            'eyes': {'emissive_scale': 0.6, 'classes': {'face': 0.8, 'sclera': 0.1}, 'maps': {'emissive': ''}},
            'iris': {'emissive_scale': 0.04, 'classes': {'eye': 0.2}, 'maps': {'emissive': ''}},
            'light': {'emissive_scale': 0.6, 'classes': {'highlight': 0.1}, 'maps': {'emissive': ''}},
            'gem': {'emissive_scale': 0.3, 'classes': {'gem': 1}, 'maps': {'emissive': ''}},
            'no-map': {'emissive_scale': 0.6, 'classes': {'eye': 1}, 'maps': {'roughness': ''}},
            'no-classes': {'emissive_scale': 0.6, 'maps': {'emissive': ''}},
            'tiny-eye': {'emissive_scale': 0.6, 'classes': {'eye': 0.0}, 'maps': {'emissive': ''}},
        }
        text = self.publish(generated)
        self.assertEqual(text.count('float inputs:emissive_adaptive_intensity ='), 8)  # two hashes per sheet
        self.assertEqual(text.count('emissive_adaptive_intensity = 10.5\n'), 6)  # 0.6 * 0.7 * 25
        self.assertEqual(text.count('emissive_adaptive_intensity = 0.7\n'), 2)  # 0.04 * 0.7 * 25
        self.assertIn('float inputs:emissive_intensity = 0.42', text)

    def test_publish_zero_disables_adaptation(self):
        text = self.publish({'eyes': {'emissive_scale': 0.6, 'classes': {'eye': 1},
                                     'maps': {'emissive': ''}}}, multiplier=0)
        self.assertEqual(text.count('emissive_adaptive_intensity = 0'), 2)
        self.assertIn('emissive_intensity = 0.42', text)

    def test_setting_and_cli_option_override_without_regeneration(self):
        setting = self.write('settings.json', b'{"emissive_adaptive_intensity": 2}')
        self.assertEqual(config.Settings.load([setting]).emissive_adaptive_intensity, 2)
        with patch.object(cli, 'Context') as context, patch.object(cli, 'cmd_publish') as publish:
            cli.main(['publish', 'fixture.pmx', '--emissive-adaptive-intensity', '4'])
        self.assertEqual(context.call_args.args[0].emissive_adaptive_intensity, 4)
        publish.assert_called_once_with(context.return_value)
        for value in ('-1', 'nan', 'inf'):
            with self.subTest(value=value), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as err:
                cli.main(['publish', 'fixture.pmx', '--emissive-adaptive-intensity', value])
            self.assertEqual(err.exception.code, 2)


class EditTests(ScratchTests):
    def run_edit(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = edit.main(['--mod', str(self.root), *map(str, args)])
        return code, out.getvalue(), err.getvalue()

    def test_add_update_idempotence_and_non_emissive_bytes(self):
        original = layer_bytes(EMITTING, UNLIT)
        added, changed = edit.update_layer(original, 3)
        self.assertEqual(changed, ['mat_0123456789ABCDEF'])
        line = b'                float inputs:emissive_adaptive_intensity = 3\n'
        self.assertEqual(added.replace(line, b''), original)
        updated, changed = edit.update_layer(added, 4.25)
        self.assertEqual(updated.replace(b' = 4.25\n', b' = 3\n'), added)
        self.assertEqual(updated.count(b'inputs:emissive_adaptive_intensity'), 1)
        self.assertEqual(edit.update_layer(updated, 4.25), (updated, []))
        self.assertEqual(edit.update_layer(original, 0)[0].count(b'emissive_adaptive_intensity = 0'), 1)

    def test_crlf_bom_comments_and_literal_braces_are_preserved(self):
        original = b'\xef\xbb\xbf' + layer_bytes(EMITTING, UNLIT).replace(b'\n', b'\r\n')
        original = original.replace(b'over "RootNode"', b'# unmatched { is a comment\r\nover "RootNode"')
        original = original.replace(b'float inputs:emissive_intensity = 0.6',
                                    b'string note = "quoted } and @not-an-asset@"\r\n'
                                    b'                float inputs:emissive_intensity = 0.6  # keep me')
        result, _ = edit.update_layer(original, 10 / 3)
        added = b'                float inputs:emissive_adaptive_intensity = 3.33333333\r\n'
        self.assertEqual(result.replace(added, b''), original)
        result = result.replace(b' = 3.33333333\r\n', b'  =  3.33333333   # keep too\r\n')
        updated, _ = edit.update_layer(result, 2)
        self.assertEqual(updated.replace(b'  =  2   # keep too', b'  =  3.33333333   # keep too'), result)

    def test_only_shader_with_map_changes_not_other_shader_in_same_material(self):
        original = layer_bytes(EMITTING)
        extra = usda.material_block(*UNLIT).encode().split(b'            over "Shader"', 1)[1]
        extra = b'            over "Unused"' + extra.rsplit(b'        }', 1)[0]
        original = original.replace(b'        }\n    }', extra + b'        }\n    }')
        result, _ = edit.update_layer(original, 1)
        self.assertEqual(result.count(b'emissive_adaptive_intensity'), 1)
        self.assertIn(extra, result)

    def test_no_map_and_commented_map_untouched(self):
        plain = layer_bytes(UNLIT).replace(b'asset inputs:reflectionroughness_texture',
                                         b'# asset inputs:emissive_mask_texture')
        self.assertEqual(edit.update_layer(plain, 1), (plain, []))
        blocked = layer_bytes(EMITTING).replace(b'@../textures/eyes.dds@', b'None')
        self.assertEqual(edit.update_layer(blocked, 1), (blocked, []))

    def test_def_prims_and_implicit_fallback(self):
        data = layer_bytes(EMITTING).replace(b'over "mat_', b'def Material "mat_').replace(
            b'over "Shader"', b'def Shader "Shader"')
        data = data.replace(b'                float inputs:emissive_intensity = 0.6\n', b'')
        edited, changed = edit.update_layer(data, 3)
        self.assertEqual(changed, ['mat_0123456789ABCDEF'])
        self.assertEqual(edited.replace(b'                float inputs:emissive_adaptive_intensity = 3\n', b''), data)
        with self.assertRaisesRegex(ValueError, 'needs one float'):
            edit.update_layer(data, 2, multiply_fallback=True)

    def test_multiplier_preserves_per_material_normalisation(self):
        small = ('AAAAAAAAAAAAAAAA', EMITTING[1], 0, 0.04)
        edited, changed = edit.update_layer(layer_bytes(EMITTING, small), 1 / 0.18, multiply_fallback=True)
        self.assertEqual(len(changed), 2)
        self.assertIn(b'emissive_adaptive_intensity = 3.33333333', edited)
        self.assertIn(b'emissive_adaptive_intensity = 0.222222222', edited)
        self.assertEqual(edit.update_layer(edited, 1 / 0.18, multiply_fallback=True), (edited, []))

    def test_dry_run_changes_no_bytes_timestamps_or_files(self):
        self.write('models/eyes.usda', layer_bytes(EMITTING, UNLIT))
        self.write('mod.usda', b'#usda 1.0\n')
        self.write('textures/eyes.dds', b'DDS fixture')
        def snapshot():
            return {p.relative_to(self.root).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns)
                    for p in self.root.rglob('*') if p.is_file()}
        before = snapshot()
        code, out, err = self.run_edit('--value', 3, '--dry-run')
        self.assertEqual(code, 0, err)
        self.assertIn('would change 1 material(s) in 1 layer(s)', out)
        self.assertEqual(snapshot(), before)
        self.assertEqual(self.run_edit('--value', 3)[0], 0)
        after = snapshot()
        self.assertEqual(after['mod.usda'][0], before['mod.usda'][0])
        self.assertEqual(after['textures/eyes.dds'], before['textures/eyes.dds'])
        self.assertIn('changed 0 material(s)', self.run_edit('--value', 3)[1])
        self.assertEqual(snapshot(), after)

    def test_preflight_rejects_bad_layer_without_partial_edit(self):
        original = layer_bytes(EMITTING)
        self.write('models/a.usda', original)
        bad = original.replace(b'float inputs:emissive_intensity = 0.6',
                               b'float inputs:emissive_intensity = 0.6\n'
                               b'                float inputs:emissive_adaptive_intensity = 1\n'
                               b'                float inputs:emissive_adaptive_intensity = 2')
        self.write('models/z.usda', bad)
        self.assertEqual(self.run_edit('--value', 3)[0], 1)
        self.assertEqual((self.root / 'models/a.usda').read_bytes(), original)
        self.assertEqual((self.root / 'models/z.usda').read_bytes(), bad)
        with self.assertRaisesRegex(ValueError, 'unbalanced'):
            edit.update_layer(original[:-3], 3)

    def test_cli_range_errors_write_nothing(self):
        original = self.write('models/a.usda', layer_bytes(EMITTING)).read_bytes()
        for value in ('-1', 'nan', 'inf', '65505'):
            with self.subTest(value=value), self.assertRaises(SystemExit) as err:
                self.run_edit('--value', value)
            self.assertEqual(err.exception.code, 2)
        self.assertEqual(self.run_edit('--multiplier', 65504)[0], 0)
        # The fallback is unchanged; 0.6*65504 fits but a larger multiplier does not.
        before = (self.root / 'models/a.usda').read_bytes()
        self.assertEqual(self.run_edit('--multiplier', 200000)[0], 1)
        self.assertEqual((self.root / 'models/a.usda').read_bytes(), before)
        self.assertIn(b'emissive_intensity = 0.6', original)


class PackageTests(ScratchTests):
    def test_package_keeps_both_emission_inputs_and_dds_bytes(self):
        game = self.root / 'game'
        mod = game / 'rtx-remix' / 'mods' / 'fixture'
        source, _ = edit.update_layer(layer_bytes(EMITTING, UNLIT), 10 / 3)
        source = b'\xef\xbb\xbf' + source.replace(b'\n', b'\r\n')
        self.write('game/rtx-remix/mods/fixture/models/model.usda', source)
        self.write('game/rtx-remix/mods/fixture/textures/eyes.dds', b'DDS eyes')
        self.write('game/rtx-remix/mods/fixture/textures/cloth.dds', b'DDS cloth')
        self.write('work/work/model/generated.json', b'{"sheet": {"maps": {}}}')
        self.write('work/work/model/hashes.json', b'{"textures": {}}')
        dest = self.root / 'package'
        with patch.object(package, 'RPAI_HOME', self.root / 'work'), contextlib.redirect_stdout(io.StringIO()):
            package.main(['--dest', str(dest), '--game-root', str(game), '--mod', 'fixture',
                          '--character', 'test=model', '--no-tool', '--no-raw'])
        packed = dest / 'remix_mod' / 'fixture'
        self.assertEqual((packed / 'models/model.usda').read_bytes(), source)
        for texture in ('eyes.dds', 'cloth.dds'):
            self.assertEqual(hashlib.sha256((packed / 'textures' / texture).read_bytes()).hexdigest(),
                             hashlib.sha256((mod / 'textures' / texture).read_bytes()).hexdigest())
        self.assertIn('@./models/model.usda@', (packed / 'mod.usda').read_text())
        self.assertIn('emissive_adaptive_intensity', (dest / 'README.md').read_text())
        self.assertEqual(json.loads((dest / 'package.json').read_text())['test']['dds_files'], 2)


if __name__ == '__main__':
    unittest.main()
