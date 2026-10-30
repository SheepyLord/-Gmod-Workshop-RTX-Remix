"""weather_presets.py on a small made-up fork (one field of each kind, twelve presets) and, when the
user's fork is on this machine, the committed table against it. Scratch goes under out/tmp."""
import tempfile
import unittest
from pathlib import Path

import weather_presets as wp

REPO = Path(__file__).resolve().parents[2]
SCRATCH = REPO / 'out' / 'tmp'
PRESETS = ['clear', 'partlyCloudy', 'overcast', 'hazy', 'foggy', 'drizzle', 'rainstorm', 'thunderstorm', 'snow',
           'blizzard', 'sandstorm', 'smoggy']

FIELD_LIST = '''#define WEATHER_PRESET_FIELD_LIST(X) \\
  /* Cloud */ \\
  X(float,   cloudDensity,     1.0f, WK_Scalar, "Clouds", "Look", "Density", 0.0f, 10.0f, 0.05f, "%.2f") \\
  X(float,   cloudWindDirection, 45.0f, WK_Angle, "Clouds", "Wind", "Wind Direction", 0.0f, 360.0f, 1.0f, "%.1f deg") \\
  X(Vector3, cloudColor, Vector3(0.89f, 0.92f, 1.0f), WK_Color, "Clouds", "Look", "Color", 0.0f, 1.5f, 0.01f, "%.2f") \\
  X(float,   transmittanceMeasurementDistanceMeters, 200.0f, WK_Extinction, "Volumetric Fog", "Medium", "Distance", 1.0f, 2000.0f, 5.0f, "%.0f") \\
  X(bool,    enableFogRemap, false, WK_Step, "Volumetric Fog", "Fog Remap", "Remap", 0.0f, 1.0f, 1.0f, "%.0f") \\
  X(float,   noiseFieldOctaves, 2.0f, WK_Scalar, "Volumetric Fog", "Heterogeneous", "Octaves", 1.0f, 8.0f, 1.0f, "%.0f") \\
  X(float,   volumetricAnisotropy, 0.0f, WK_Scalar, "Volumetric Fog", "Medium", "Anisotropy", -1.0f, 1.0f, 0.01f, "%.2f") \\
  X(float,   precipitationFallSpeed, 8.0f, WK_Scalar, "Precipitation", "Motion", "Fall Speed", 0.1f, 40.0f, 0.1f, "%.1f m/s")
'''


def preset(name, i):
    return (f'// {name}\n#define WEATHER_PRESET_VALUES_{name}(X) \\\n'
            f'  X(float, cloudDensity, {0.5 + i}f) \\\n'
            f'  X(float, cloudWindDirection, {10 * i}.0f) \\\n'
            f'  X(Vector3, cloudColor, Vector3(0.9f, 0.{i}f, 1.0f)) \\\n'
            f'  X(float, transmittanceMeasurementDistanceMeters, {100 * (i + 1)}.0f) \\\n'
            f'  X(bool, enableFogRemap, {"true" if i == 4 else "false"}) \\\n'
            '  /* the same in every preset */ \\\n'
            '  X(float, noiseFieldOctaves, 2.0f) \\\n'
            f'  X(float, volumetricAnisotropy, 0.{i}f) \\\n'
            f'  X(float, precipitationFallSpeed, {i + 1}.5f)\n\n')


def write_fork(root: Path, header_extra: str = '', declare_all: bool = True):
    render = root / 'src' / 'dxvk' / 'rtx_render'
    render.mkdir(parents=True)
    header = FIELD_LIST + '\n' + ''.join(preset(name, i) for i, name in enumerate(PRESETS)) + header_extra
    header += '#define DECLARE_ALL_WEATHER_PRESETS()   \\\n' + ' \\\n'.join(
        f'  DECLARE_WEATHER_PRESET({name})' for name in PRESETS) + '\n'
    (render / 'rtx_weather.h').write_text(header, encoding='utf-8')
    (render / 'rtx_weather.cpp').write_text('  void resolveLegacyWeatherOwnership(WeatherSnapshot& s) {\n'
                                            '    FALLBACK_IF_INVARIANT(enableFogRemap);\n'
                                            '    FALLBACK_IF_INVARIANT(noiseFieldOctaves);\n  }\n', encoding='utf-8')
    (render / 'rtx_atmosphere.h').write_text(
        'RTX_OPTION("rtx.atmosphere", float, cloudDensity, 4.0f, "d");\n'
        'RTX_OPTION("rtx.atmosphere", float, cloudWindDirection, 45.0f, "d");\n'
        'RTX_OPTION("rtx.atmosphere", Vector3, cloudColor, Vector3(1.0f, 1.0f, 1.0f), "d");\n', encoding='utf-8')
    volumetrics = ('RTX_OPTION_ARGS("rtx.volumetrics", float, transmittanceMeasurementDistanceMeters, 500.0f, "d", args.minValue = 0);\n'
                   'RTX_OPTION("rtx.volumetrics", bool, enableFogRemap, false, "d");\n'
                   'RTX_OPTION_ARGS("rtx.volumetrics", uint32_t, noiseFieldOctaves, 2.0f, "d", args.minValue = 1);\n')
    if declare_all:
        volumetrics += 'RTX_OPTION_ARGS("rtx.volumetrics", float, anisotropy, 0.05f, "d", args.minValue = -1);\n'
    (render / 'rtx_global_volumetrics.h').write_text(volumetrics, encoding='utf-8')
    (render / 'rtx_precipitation.h').write_text('RTX_OPTION("rtx.weather.precipitation", float, fallSpeed, 8.0f, "d");\n',
                                                encoding='utf-8')


class WeatherPresetsTests(unittest.TestCase):
    def fork(self, **changes) -> Path:
        SCRATCH.mkdir(parents=True, exist_ok=True)
        folder = tempfile.TemporaryDirectory(dir=SCRATCH, prefix='weather-presets-')
        self.addCleanup(folder.cleanup)
        write_fork(Path(folder.name), **changes)
        return Path(folder.name)

    def test_every_field_with_its_option_and_how_it_blends(self):
        data = wp.read_presets(self.fork())
        self.assertEqual(data['order'], PRESETS)
        fields = {f['name']: f for f in data['fields']}
        self.assertEqual(fields['cloudDensity']['option'], 'rtx.atmosphere.cloudDensity')
        self.assertEqual(fields['volumetricAnisotropy']['option'], 'rtx.volumetrics.anisotropy')
        self.assertEqual(fields['precipitationFallSpeed']['option'], 'rtx.weather.precipitation.fallSpeed')
        self.assertEqual({f['kind'] for f in data['fields']}, {'scalar', 'angle', 'color', 'extinction', 'step'})
        # The runtime takes over a conditional field only when the presets disagree on it: the fog remap
        # switch differs in one preset (owned), the octaves are the same in all twelve (left alone).
        self.assertTrue(fields['enableFogRemap']['owned'])
        self.assertFalse(fields['noiseFieldOctaves']['owned'])
        self.assertTrue(fields['noiseFieldOctaves']['integer'])
        self.assertEqual(data['presets']['hazy']['cloudColor'], [0.9, 0.3, 1.0])
        text = wp.generate(data, 'abc12345')
        self.assertIn('(dxvk-remix-gmod abc12345, rtx_weather.h SHA-256 ', text)
        self.assertIn('configuration too, are not here: noiseFieldOctaves.', text)
        self.assertIn('{ name = "transmittanceMeasurementDistanceMeters", option = '
                      '"rtx.volumetrics.transmittanceMeasurementDistanceMeters", kind = "extinction" },', text)
        self.assertIn('      cloudColor = { 0.9, 0.3, 1 },\n', text)
        self.assertIn('      enableFogRemap = true,\n', text)
        self.assertNotIn('noiseFieldOctaves =', text)

    def test_what_each_option_goes_back_to(self):
        # R3-009: the weather left to Remix puts back what Remix has without it: the package's classic
        # layer where it sets the option, else the runtime's default.
        fork = self.fork()
        layer = fork / 'classic.conf'
        layer.write_text('# a layer\nrtx.atmosphere.cloudDensity = 2.5\nrtx.atmosphere.unrelated = 1\n', encoding='utf-8')
        defaults = wp.read_presets(fork, layer)['defaults']
        self.assertEqual(defaults, {'rtx.atmosphere.cloudDensity': '2.5', 'rtx.atmosphere.cloudWindDirection': '45',
                                    'rtx.atmosphere.cloudColor': '1, 1, 1', 'rtx.volumetrics.enableFogRemap': 'False',
                                    'rtx.volumetrics.transmittanceMeasurementDistanceMeters': '500',
                                    'rtx.volumetrics.anisotropy': '0.05', 'rtx.weather.precipitation.fallSpeed': '8'})
        self.assertIn('    ["rtx.atmosphere.cloudColor"] = "1, 1, 1",\n', wp.generate(wp.read_presets(fork, layer), 'abc12345'))
        header = fork / 'src' / 'dxvk' / 'rtx_render' / 'rtx_atmosphere.h'
        header.write_text(header.read_text(encoding='utf-8').replace('4.0f', 'kDensity'), encoding='utf-8')
        with self.assertRaisesRegex(wp.SourceError, "defaults of \\['rtx.atmosphere.cloudDensity'\\]"):
            wp.read_presets(fork, layer)

    def test_check_tells_an_out_of_date_table(self):
        fork = self.fork()
        out = fork / 'out.lua'
        self.assertEqual(wp.main(['--fork', str(fork), '--out', str(out), '--check']), 1)
        self.assertEqual(wp.main(['--fork', str(fork), '--out', str(out)]), 0)
        self.assertEqual(wp.main(['--fork', str(fork), '--out', str(out), '--check']), 0)
        out.write_text(out.read_text(encoding='utf-8').replace('cloudDensity = 0.5', 'cloudDensity = 0.6'),
                       encoding='utf-8')
        self.assertEqual(wp.main(['--fork', str(fork), '--out', str(out), '--check']), 1)

    def test_a_field_without_a_declared_option_or_a_preset_value_is_refused(self):
        with self.assertRaisesRegex(wp.SourceError, 'rtx.volumetrics.anisotropy is not declared'):
            wp.read_presets(self.fork(declare_all=False))
        fork = self.fork()
        header = fork / 'src' / 'dxvk' / 'rtx_render' / 'rtx_weather.h'
        header.write_text(header.read_text(encoding='utf-8').replace('  X(float, precipitationFallSpeed, 7.5f)\n', '\n'),
                          encoding='utf-8')
        with self.assertRaisesRegex(wp.SourceError, "rainstorm: no value for \\['precipitationFallSpeed'\\]"):
            wp.read_presets(fork)

    @unittest.skipUnless((wp.FORK / wp.HEADER).is_file(), "the user's Remix fork is not on this machine")
    def test_the_committed_table_matches_the_fork(self):
        self.assertEqual(wp.main(['--check']), 0)


if __name__ == '__main__':
    unittest.main()
