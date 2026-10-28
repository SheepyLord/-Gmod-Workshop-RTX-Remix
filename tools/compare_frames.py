"""Compares two screenshots of the same view with the user's block-difference measure: the mean
absolute difference, over all blocks and channels, of the mean RGB of every 32x32 block (0-255 scale;
about 1 between repeated captures, 1.5-3.6 close, 16-26 broken). Also reports each image's mean RGB
and luminance percentiles. Needs Pillow.

Usage: python tools/compare_frames.py REFERENCE IMAGE [--block 32] [--mask x0,y0,x1,y1] [--threshold N] [--json]
See compare_frames.py.md for the options, outputs and exit codes."""

import argparse
import bisect
import itertools
import json
import math
import sys
from array import array

PERCENTILES = (5, 50, 95, 99.5)
LUMA = (2126, 7152, 722)  # Rec. 709 weights x 10,000: the luminance of 8-bit RGB is an exact integer / 10,000


class CompareError(Exception):
    pass


def load(path):
    """The image as 8-bit RGB (alpha dropped)."""
    try:
        from PIL import Image
    except ImportError:
        raise CompareError('compare_frames.py needs Pillow (python -m pip install Pillow)')
    try:
        with Image.open(path) as image:
            return image.convert('RGB')
    except (OSError, ValueError, Image.DecompressionBombError) as err:
        raise CompareError('%s: %s' % (path, err))


def block_means(image, size):
    """([(r, g, b) mean of every size x size block, row by row], blocks across, blocks down), the
    image cropped from the top left to whole blocks."""
    across, down = image.width // size, image.height // size
    if not across or not down:
        return [], across, down
    channels = [array('f', band.convert('F').reduce(size).tobytes())
                for band in image.crop((0, 0, across * size, down * size)).split()]
    return list(zip(*channels)), across, down


def masked_blocks(masks, size, across, down):
    """Row-by-row indices of the blocks that intersect a mask (x0 <= x < x1, y0 <= y < y1)."""
    out = set()
    for x0, y0, x1, y1 in masks:
        for row in range(y0 // size, min(down, (y1 - 1) // size + 1)):
            for col in range(x0 // size, min(across, (x1 - 1) // size + 1)):
                out.add(row * across + col)
    return out


def block_diff(a, b, excluded):
    """Mean absolute difference over every channel of every block not excluded, or None."""
    total, count = 0.0, 0
    for index, (pa, pb) in enumerate(zip(a, b)):
        if index not in excluded:
            total += abs(pa[0] - pb[0]) + abs(pa[1] - pb[1]) + abs(pa[2] - pb[2])
            count += 3
    return total / count if count else None


def image_stats(image):
    """Mean R, G, B and the luminance percentiles (linear between the two nearest ranks, as numpy's
    default) over every pixel, from the image's colour counts."""
    pixels = image.width * image.height
    sums = [0, 0, 0]
    histogram = {}
    for count, (r, g, b) in image.getcolors(pixels):
        sums[0] += count * r
        sums[1] += count * g
        sums[2] += count * b
        y = LUMA[0] * r + LUMA[1] * g + LUMA[2] * b
        histogram[y] = histogram.get(y, 0) + count
    values = sorted(histogram)
    cumulative = list(itertools.accumulate(histogram[v] for v in values))

    def ranked(k):  # the k-th smallest luminance, from 0
        return values[bisect.bisect_right(cumulative, k)]

    percentiles = {}
    for q in PERCENTILES:
        position = q / 100 * (pixels - 1)
        low = math.floor(position)
        a, b = ranked(low), ranked(min(low + 1, pixels - 1))
        percentiles['p%g' % q] = (a + (b - a) * (position - low)) / 10000
    return [s / pixels for s in sums], percentiles


def describe(path, image):
    mean, percentiles = image_stats(image)
    return {'path': path, 'width': image.width, 'height': image.height, 'mean_rgb': [round(v, 3) for v in mean],
            'luminance': {k: round(v, 3) for k, v in percentiles.items()}}


def compare(reference_path, image_path, size=32, masks=()):
    reference, image = load(reference_path), load(image_path)
    if reference.size != image.size:
        raise CompareError('the images differ in size: %dx%d and %dx%d' % (reference.size + image.size))
    a, across, down = block_means(reference, size)
    b, _, _ = block_means(image, size)
    excluded = masked_blocks(masks, size, across, down)
    diff = block_diff(a, b, excluded)
    if diff is None:
        raise CompareError('no blocks to compare: the images are smaller than %dx%d, or every block is masked'
                           % (size, size))
    return {
        'reference': describe(reference_path, reference),
        'image': describe(image_path, image),
        'block': size,
        'blocks': across * down,
        'masked': len(excluded),
        'block_diff': diff,
    }


def rectangle(text):
    try:
        x0, y0, x1, y1 = (int(v) for v in text.split(','))
    except ValueError:
        raise argparse.ArgumentTypeError('%s: expected x0,y0,x1,y1 in whole pixels' % text)
    if min(x0, y0) < 0 or x1 <= x0 or y1 <= y0:
        raise argparse.ArgumentTypeError('%s: expected 0 <= x0 < x1 and 0 <= y0 < y1' % text)
    return x0, y0, x1, y1


def positive(text):
    value = int(text)
    if value < 1:
        raise argparse.ArgumentTypeError('must be at least 1')
    return value


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='backslashreplace')
    ap = argparse.ArgumentParser(description='Compare two screenshots of the same view (block difference).')
    ap.add_argument('reference', help='reference image (PNG, JPEG, ...)')
    ap.add_argument('image', help='image to compare, the same size')
    ap.add_argument('--block', type=positive, default=32, help='block size in pixels (default 32)')
    ap.add_argument('--mask', type=rectangle, action='append', default=[], metavar='x0,y0,x1,y1',
                    help='leave out the blocks this pixel rectangle touches (end exclusive; repeatable)')
    ap.add_argument('--threshold', type=float, help='exit 1 when block_diff is above this')
    ap.add_argument('--json', action='store_true', help='print the result as JSON')
    args = ap.parse_args(argv)
    try:
        result = compare(args.reference, args.image, args.block, args.mask)
    except CompareError as err:
        print('error: %s' % err, file=sys.stderr)
        return 2
    over = None if args.threshold is None else result['block_diff'] > args.threshold
    result.update(block_diff=round(result['block_diff'], 4), threshold=args.threshold, over_threshold=over)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        for key in ('reference', 'image'):
            d = result[key]
            print('%-10s %dx%d  mean RGB %.2f %.2f %.2f  luminance %s  %s' % (
                key, d['width'], d['height'], *d['mean_rgb'],
                ' '.join('%s %.2f' % (k, v) for k, v in d['luminance'].items()), d['path']))
        print('block_diff %.4f over %d blocks of %dx%d (%d masked)' % (
            result['block_diff'], result['blocks'] - result['masked'], args.block, args.block, result['masked']))
        if over is not None:
            print('threshold  %g: %s' % (args.threshold, 'OVER' if over else 'within'))
    return 1 if over else 0


if __name__ == '__main__':
    sys.exit(main())
