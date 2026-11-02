"""Feature-off comparisons use linear luminance in identical boxes and preserve black controls."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
try:
    from PIL import Image
except ImportError:
    Image = None

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('eye_patches', ROOT / 'tools/qa/eye_white_patches.py')
patches = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(patches)


@unittest.skipUnless(Image, 'Pillow is not installed')
class EyeComparisonTests(unittest.TestCase):
    def test_control_stays_zero_while_eye_changes(self):
        scratch = ROOT / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            old, new = Path(temp) / 'off.png', Path(temp) / 'on.png'
            image = Image.new('RGB', (4, 2), (80, 80, 80))
            image.save(old)
            image.putpixel((0, 0), (160, 160, 160))
            image.save(new)
            report = patches.compare_patches(new, old, {'sclera': (0, 0, 1, 1), 'face_control': (2, 0, 4, 2)})['patches']
            self.assertAlmostEqual(report['sclera']['mean_delta'], patches.LINEAR[160] - patches.LINEAR[80])
            self.assertEqual(report['face_control']['mean_absolute_delta'], 0)
            self.assertEqual(report['face_control']['relative_mean_delta'], 0)
            Image.new('RGB', (1, 1)).save(new)
            with self.assertRaises(patches.PatchError):
                patches.compare_patches(new, old, {'sclera': (0, 0, 1, 1)})


if __name__ == '__main__':
    unittest.main()
