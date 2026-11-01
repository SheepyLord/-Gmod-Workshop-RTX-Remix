"""tools/qa/eye_white_patches.py on generated images: box means against an independent sRGB decode, the
ratio, --shift, --range, --json, folder inputs and the error exits. Scratch goes under out/tmp."""
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # eye_white_patches.py needs Pillow; without it these tests are skipped
    Image = None

REPO = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('eye_white_patches', REPO / 'tools' / 'qa' / 'eye_white_patches.py')
patches = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(patches)

SCLERA, SKIN, BACKGROUND = (200, 200, 205), (180, 160, 150), (40, 40, 40)


def luminance(rgb):
    """Rec. 709 luminance of an 8-bit sRGB colour, decoded independently of the script."""
    def decode(value):
        c = value / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * decode(rgb[0]) + 0.7152 * decode(rgb[1]) + 0.0722 * decode(rgb[2])


@unittest.skipUnless(Image, 'Pillow is not installed')
class EyeWhitePatchesTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out' / 'tmp'  # AGENTS.md rule 9
        scratch.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch, prefix='eye-white-patches-')
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def frame(self, name, shift=(0, 0), sclera=SCLERA, skin=SKIN, size=(1100, 800)):
        image = Image.new('RGB', size, BACKGROUND)
        for key, (x0, y0, x1, y1) in patches.DEFAULT_PATCHES.items():
            image.paste(skin if key == 'skin' else sclera, (x0 + shift[0], y0 + shift[1], x1 + shift[0], y1 + shift[1]))
        path = self.root / name
        image.save(path)
        return path

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = patches.main([str(a) for a in argv])
        return code, out.getvalue(), err.getvalue()

    def test_means_and_ratio_match_an_independent_decode(self):
        result = patches.measure(self.frame('shot-01-noon.png'), patches.DEFAULT_PATCHES)
        self.assertAlmostEqual(result['patches']['skin']['mean'], luminance(SKIN), places=12)
        self.assertAlmostEqual(result['sclera'], luminance(SCLERA), places=12)
        self.assertAlmostEqual(result['ratio'], luminance(SCLERA) / luminance(SKIN), places=12)
        self.assertEqual(result['patches']['skin']['std'], 0)
        self.assertEqual(set(result['sclera_ratios']), {'sclera_ul', 'sclera_lr'})

    def test_a_box_on_an_edge_shows_in_its_deviation(self):
        image = Image.new('RGB', (100, 100), (0, 0, 0))
        image.paste((255, 255, 255), (0, 0, 50, 100))
        mean, std = patches.patch_stats(image, (40, 0, 60, 10))
        self.assertAlmostEqual(mean, 0.5, places=12)
        self.assertAlmostEqual(std, 0.5, places=12)

    def test_shift_moves_every_box(self):
        path = self.frame('shot-01.png', shift=(11, 6))
        unshifted = patches.measure(path, patches.DEFAULT_PATCHES)
        shifted = patches.measure(path, patches.DEFAULT_PATCHES, (11, 6))
        self.assertNotAlmostEqual(unshifted['ratio'], shifted['ratio'], places=3)
        self.assertAlmostEqual(shifted['ratio'], luminance(SCLERA) / luminance(SKIN), places=12)
        self.assertEqual(shifted['patches']['skin']['box'], [1021, 666, 1051, 696])

    def test_folder_inputs_take_the_shots_in_order(self):
        run = self.root / 'run'
        run.mkdir()
        for name in ('shot-02-golden.png', 'shot-01-noon.png', 'screenshot-1.png'):
            self.frame(name).rename(run / name)
        self.assertEqual([p.name for p in patches.shots([run])], ['shot-01-noon.png', 'shot-02-golden.png'])

    def test_range_marks_shots_outside_and_exits_1(self):
        bright = self.frame('shot-01.png')
        dark = self.frame('shot-02.png', sclera=(60, 60, 60))
        code, out, _ = self.run_main(bright, dark, '--range', '0.8,2')
        self.assertEqual(code, 1)
        lines = out.splitlines()
        self.assertNotIn('OUTSIDE', lines[0])
        self.assertIn('OUTSIDE', lines[1])
        self.assertEqual(self.run_main(bright, '--range', '0.8,2')[0], 0)

    def test_json_output(self):
        path = self.frame('shot-01.png')
        code, out, _ = self.run_main(path, '--patch', 'sclera=905,622,920,636', '--patch', 'skin=1010,660,1040,690',
                                     '--json', '--range', '0,10')
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual(data['range'], [0, 10])
        self.assertEqual(data['outside'], [])
        result = data['results'][0]
        self.assertEqual(set(result['patches']), {'sclera', 'skin'})
        self.assertAlmostEqual(result['ratio'], luminance(SCLERA) / luminance(SKIN), places=12)

    def test_black_skin_gives_no_ratio(self):
        result = patches.measure(self.frame('shot-01.png', skin=(0, 0, 0)), patches.DEFAULT_PATCHES)
        self.assertIsNone(result['ratio'])
        self.assertEqual(self.run_main(self.root / 'shot-01.png', '--range', '0,100')[0], 1)

    def test_errors_exit_2(self):
        path = self.frame('shot-01.png', size=(1000, 800))  # the skin box ends at x 1040
        cases = [
            (path,),                                                   # a box outside the image
            (path, '--patch', 'skin=1,1,0,0', '--patch', 'sclera=1,1,2,2'),
            (path, '--patch', 'sclera=1,1,2,2'),                       # no skin box
            (path, '--patch', 'skin=1,1,2,2', '--patch', 'eye=3,3,4,4'),  # no sclera box
            (path, '--patch', 'skin'),
            (path, '--shift', '1'),
            (path, '--range', '2,1'),
            (self.root / 'missing',),
            (self.root,),                                              # a folder without shots
        ]
        for argv in cases:
            with self.subTest(argv=argv[1:]):
                code, out, err = self.run_main(*argv)
                self.assertEqual(code, 2)
                self.assertIn('eye_white_patches.py:', err)
                self.assertEqual(out, '')


if __name__ == '__main__':
    unittest.main()
