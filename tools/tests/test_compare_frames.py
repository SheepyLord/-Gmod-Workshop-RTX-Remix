import contextlib
import io
import json
import math
import random
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

import compare_frames

try:
    from PIL import Image
except ImportError:  # compare_frames.py needs Pillow; without it these tests are skipped
    Image = None

REPO = Path(__file__).resolve().parents[2]


def pixels(image):
    width, height = image.size
    data = image.tobytes()
    return [[tuple(data[(y * width + x) * 3:(y * width + x) * 3 + 3]) for x in range(width)] for y in range(height)]


def reference_blocks(image, size):
    """Block means the slow way: [(r, g, b)] row by row."""
    px = pixels(image)
    out = []
    for by in range(image.height // size):
        for bx in range(image.width // size):
            block = [px[y][x] for y in range(by * size, (by + 1) * size) for x in range(bx * size, (bx + 1) * size)]
            out.append(tuple(sum(p[c] for p in block) / len(block) for c in range(3)))
    return out


def reference_percentile(values, q):
    """numpy.percentile's default (linear) method on a list."""
    values = sorted(values)
    position = q / 100 * (len(values) - 1)
    low = math.floor(position)
    high = min(low + 1, len(values) - 1)
    return values[low] + (values[high] - values[low]) * (position - low)


@unittest.skipUnless(Image, 'Pillow is not installed')
class CompareFramesTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out' / 'tmp'  # AGENTS.md rule 9
        scratch.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch, prefix='compare-frames-')
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def save(self, name, image):
        path = self.root / name
        image.save(path)
        return path

    def run_tool(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = compare_frames.main([*map(str, args)])
        return code, out.getvalue(), err.getvalue()

    def pair(self):
        """70x66 images: 2x2 whole blocks of 32 plus a margin the measure crops away. b differs from a
        in block (1, 0) by (30, 60, 90) and in the margin."""
        a = Image.new('RGB', (70, 66), (10, 20, 30))
        b = a.copy()
        b.paste((40, 80, 120), (32, 0, 64, 32))
        b.paste((255, 255, 255), (64, 0, 70, 66))
        b.paste((255, 255, 255), (0, 64, 70, 66))
        return self.save('a.png', a), self.save('b.png', b)

    def test_block_diff_crops_to_whole_blocks(self):
        a, b = self.pair()
        code, out, err = self.run_tool(a, b, '--json')
        self.assertEqual(code, 0, err)
        result = json.loads(out)
        self.assertEqual((result['block'], result['blocks'], result['masked']), (32, 4, 0))
        self.assertAlmostEqual(result['block_diff'], (30 + 60 + 90) / 12)
        self.assertEqual(result['reference']['mean_rgb'], [10.0, 20.0, 30.0])
        self.assertEqual(set(result['reference']['luminance'].values()), {18.596})  # 0.2126*10 + 0.7152*20 + 0.0722*30
        n = 70 * 66
        counts = {(10, 20, 30): 4096 - 1024, (40, 80, 120): 1024, (255, 255, 255): n - 4096}
        mean = [round(float(Fraction(sum(c[i] * k for c, k in counts.items()), n)), 3) for i in range(3)]
        self.assertEqual(result['image']['mean_rgb'], mean)
        self.assertEqual(result['image']['luminance'], {'p5': 18.596, 'p50': 18.596, 'p95': 255.0, 'p99.5': 255.0})
        self.assertEqual((result['image']['width'], result['image']['height']), (70, 66))
        self.assertIsNone(result['threshold'])
        self.assertIsNone(result['over_threshold'])

    def test_identical_images_and_text_output(self):
        a, _ = self.pair()
        code, out, err = self.run_tool(a, a)
        self.assertEqual(code, 0, err)
        self.assertIn('block_diff 0.0000 over 4 blocks of 32x32 (0 masked)', out)
        self.assertTrue(out.startswith('reference  70x66  mean RGB 10.00 20.00 30.00  luminance p5 18.60'), out)

    def test_masks_and_threshold(self):
        a, b = self.pair()
        result = json.loads(self.run_tool(a, b, '--json', '--mask', '40,5,41,6')[1])
        self.assertEqual((result['masked'], result['block_diff']), (1, 0.0))
        result = json.loads(self.run_tool(a, b, '--json', '--mask', '0,0,33,1', '--mask', '500,500,600,600')[1])
        self.assertEqual(result['masked'], 2)  # blocks (0, 0) and (1, 0); the second mask is outside
        self.assertEqual(self.run_tool(a, b, '--threshold', '20')[0], 0)
        code, out, _ = self.run_tool(a, b, '--threshold', '10')
        self.assertEqual(code, 1)
        self.assertIn('threshold  10: OVER', out)
        code, out, _ = self.run_tool(a, b, '--threshold', '10', '--json')
        self.assertEqual((code, json.loads(out)['over_threshold']), (1, True))
        self.assertEqual(json.loads(self.run_tool(a, b, '--json', '--block', '16')[1])['blocks'], 16)

    def test_errors_exit_2(self):
        a, _ = self.pair()
        other = self.save('other.png', Image.new('RGB', (64, 64)))
        tiny = self.save('tiny.png', Image.new('RGB', (8, 8)))
        not_image = self.root / 'not.png'
        not_image.write_bytes(b'not an image')
        for args in ([a, other], [tiny, tiny], [a, not_image], [a, self.root / 'missing.png'], [a, a, '--mask', '0,0,70,66']):
            code, _, err = self.run_tool(*args)
            self.assertEqual(code, 2, args)
            self.assertTrue(err.startswith('error: '), err)
        for bad in (['--mask', '1,2,3'], ['--mask', '5,0,5,10'], ['--block', '0']):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
                compare_frames.main([str(a), str(a), *bad])
            self.assertEqual(raised.exception.code, 2)

    def test_random_images_match_the_slow_computation(self):
        rng = random.Random(7)
        size = (75, 49)
        images = []
        for name in ('r1.png', 'r2.png'):
            image = Image.frombytes('RGB', size, bytes(rng.randrange(256) for _ in range(size[0] * size[1] * 3)))
            images.append(Image.open(self.save(name, image)).convert('RGB'))
        for block in (32, 16, 7):
            fast, across, down = compare_frames.block_means(images[0], block)
            self.assertEqual((across, down), (size[0] // block, size[1] // block))
            for got, want in zip(fast, reference_blocks(images[0], block)):
                for g, w in zip(got, want):
                    self.assertAlmostEqual(g, w, places=4)
            slow = [abs(x - y) for p, q in zip(reference_blocks(images[0], block), reference_blocks(images[1], block))
                    for x, y in zip(p, q)]
            other, _, _ = compare_frames.block_means(images[1], block)
            self.assertAlmostEqual(compare_frames.block_diff(fast, other, set()), sum(slow) / len(slow), places=4)
        luminance = [0.2126 * r + 0.7152 * g + 0.0722 * b for row in pixels(images[0]) for r, g, b in row]
        mean, percentiles = compare_frames.image_stats(images[0])
        for q in compare_frames.PERCENTILES:
            self.assertAlmostEqual(percentiles['p%g' % q], reference_percentile(luminance, q), places=9)
        for c in range(3):
            self.assertAlmostEqual(mean[c], sum(p[c] for row in pixels(images[0]) for p in row) / (size[0] * size[1]))


if __name__ == '__main__':
    unittest.main()
