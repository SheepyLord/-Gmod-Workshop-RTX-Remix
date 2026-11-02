"""Eye whites against the skin in the screenshots of eye_white_probe.lua: the linear luminance of named
pixel boxes in every shot, and the ratio of the sclera boxes' mean to the skin box. Needs Pillow.

Usage: python tools/qa/eye_white_patches.py RUN_OR_PNG... [--patch NAME=x0,y0,x1,y1 ...] [--shift dx,dy]
       [--range LOW,HIGH] [--json]
See eye_white_patches.py.md for the default boxes, outputs and exit codes."""

import argparse
import json
import math
import sys
from pathlib import Path

# Robin (3829892354's pack) in a 1920x1080 frame of the probe, with the player placed as the .md shows.
DEFAULT_PATCHES = {
    'sclera_ul': (905, 622, 920, 636),
    'sclera_lr': (966, 722, 976, 742),
    'skin': (1010, 660, 1040, 690),
}
LUMA = (0.2126, 0.7152, 0.0722)  # Rec. 709 weights on linear RGB


class PatchError(Exception):
    pass


def srgb_to_linear(value):
    c = value / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


LINEAR = [srgb_to_linear(v) for v in range(256)]


def parse_box(text):
    try:
        x0, y0, x1, y1 = (int(part) for part in text.split(','))
    except ValueError:
        raise PatchError(f'{text!r}: expected x0,y0,x1,y1 (integers)')
    if x0 < 0 or y0 < 0 or x1 <= x0 or y1 <= y0:
        raise PatchError(f'{text!r}: needs 0 <= x0 < x1 and 0 <= y0 < y1')
    return x0, y0, x1, y1


def parse_patches(items):
    patches = {}
    for item in items:
        name, sep, box = item.partition('=')
        if not sep or not name:
            raise PatchError(f'{item!r}: expected NAME=x0,y0,x1,y1')
        patches[name] = parse_box(box)
    if 'skin' not in patches or not any(name.startswith('sclera') for name in patches):
        raise PatchError('the patches need one named skin and at least one whose name starts with sclera')
    return patches


def patch_stats(image, box):
    """Mean and standard deviation of the linear luminance in box (x0 <= x < x1, y0 <= y < y1)."""
    x0, y0, x1, y1 = box
    if x1 > image.width or y1 > image.height:
        raise PatchError(f'box {box} is outside the {image.width}x{image.height} image')
    data = image.crop(box).tobytes()
    values = [LUMA[0] * LINEAR[data[i]] + LUMA[1] * LINEAR[data[i + 1]] + LUMA[2] * LINEAR[data[i + 2]]
              for i in range(0, len(data), 3)]
    mean = sum(values) / len(values)
    return mean, math.sqrt(sum((v - mean) ** 2 for v in values) / len(values))


def measure(path, patches, shift=(0, 0)):
    try:
        from PIL import Image
    except ImportError:
        raise PatchError('eye_white_patches.py needs Pillow (python -m pip install Pillow)')
    with Image.open(path) as source:
        image = source.convert('RGB')
    dx, dy = shift
    stats = {}
    for name, (x0, y0, x1, y1) in patches.items():
        box = (x0 + dx, y0 + dy, x1 + dx, y1 + dy)
        if box[0] < 0 or box[1] < 0:
            raise PatchError(f'patch {name} shifted to {box} leaves the image')
        mean, std = patch_stats(image, box)
        stats[name] = {'box': list(box), 'mean': mean, 'std': std}
    skin = stats['skin']['mean']
    sclera = [name for name in patches if name.startswith('sclera')]
    per_patch = {name: stats[name]['mean'] / skin if skin > 0 else None for name in sclera}
    eye = sum(stats[name]['mean'] for name in sclera) / len(sclera)
    return {'shot': str(path), 'patches': stats, 'sclera': eye, 'skin': skin,
            'ratio': eye / skin if skin > 0 else None, 'sclera_ratios': per_patch}


def compare_patches(path, baseline, patches, shift=(0, 0)):
    """Linear luminance changes in identical fixed boxes, including a face control outside the eyes."""
    from PIL import Image
    with Image.open(path) as src, Image.open(baseline) as ref:
        image, reference = src.convert('RGB'), ref.convert('RGB')
    if image.size != reference.size:
        raise PatchError('comparison images must have identical dimensions')
    changes = {}
    dx, dy = shift
    for name, (x0, y0, x1, y1) in patches.items():
        box = x0 + dx, y0 + dy, x1 + dx, y1 + dy
        if box[0] < 0 or box[1] < 0 or box[2] > image.width or box[3] > image.height:
            raise PatchError(f'comparison box {box} leaves the image')
        current = image.crop(box).tobytes()
        old = reference.crop(box).tobytes()
        differences, old_values = [], []
        for i in range(0, len(current), 3):
            a = sum(LUMA[c] * LINEAR[current[i + c]] for c in range(3))
            b = sum(LUMA[c] * LINEAR[old[i + c]] for c in range(3))
            differences.append(a - b)
            old_values.append(b)
        delta = sum(differences) / len(differences)
        mean = sum(old_values) / len(old_values)
        changes[name] = {'mean_delta': delta, 'relative_mean_delta': delta / mean if mean > 0 else None,
                         'mean_absolute_delta': sum(map(abs, differences)) / len(differences)}
    return {'baseline': str(baseline), 'patches': changes}


def shots(paths):
    found = []
    for item in paths:
        path = Path(item)
        if path.is_dir():
            found += sorted(path.glob('shot-*.png'))
        elif path.is_file():
            found.append(path)
        else:
            raise PatchError(f'{item}: no such run folder or image')
    if not found:
        raise PatchError('no shot-*.png in the given folders')
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('inputs', nargs='+', help='run folders (their shot-*.png) or PNG files')
    parser.add_argument('--patch', action='append', default=[], metavar='NAME=x0,y0,x1,y1',
                        help='a pixel box (repeatable; replaces the defaults): skin and one or more sclera*')
    parser.add_argument('--shift', default='0,0', metavar='dx,dy', help='move every box by this many pixels')
    parser.add_argument('--range', metavar='LOW,HIGH', help='exit 1 when a shot\'s ratio is outside it')
    parser.add_argument('--json', action='store_true', help='print the results as JSON')
    parser.add_argument('--baseline', type=Path, help='compare fixed boxes with this feature-off PNG (same camera/condition)')
    args = parser.parse_args(argv)
    try:
        patches = parse_patches(args.patch) if args.patch else dict(DEFAULT_PATCHES)
        try:
            shift = tuple(int(v) for v in args.shift.split(','))
            if len(shift) != 2:
                raise ValueError
        except ValueError:
            raise PatchError(f'--shift {args.shift!r}: expected dx,dy (integers)')
        bounds = None
        if args.range:
            try:
                bounds = tuple(float(v) for v in args.range.split(','))
                if len(bounds) != 2 or not bounds[0] <= bounds[1]:
                    raise ValueError
            except ValueError:
                raise PatchError(f'--range {args.range!r}: expected LOW,HIGH with LOW <= HIGH')
        results = [measure(path, patches, shift) for path in shots(args.inputs)]
        if args.baseline:
            for result in results:
                result['comparison'] = compare_patches(result['shot'], args.baseline, patches, shift)
    except PatchError as error:
        print(f'eye_white_patches.py: {error}', file=sys.stderr)
        return 2
    outside = [r for r in results if bounds and (r['ratio'] is None or not bounds[0] <= r['ratio'] <= bounds[1])]
    if args.json:
        print(json.dumps({'results': results, 'range': list(bounds) if bounds else None,
                          'outside': [r['shot'] for r in outside]}, indent=1))
    else:
        for r in results:
            parts = '  '.join(f"{name} {s['mean']:.4f}+-{s['std']:.4f}" for name, s in r['patches'].items())
            ratio = 'n/a' if r['ratio'] is None else f"{r['ratio']:.2f}"
            each = ' '.join('n/a' if v is None else f'{v:.2f}' for v in r['sclera_ratios'].values())
            flag = '  OUTSIDE' if r in outside else ''
            print(f"{r['shot']}: ratio {ratio} ({each})  {parts}{flag}")
    return 1 if outside else 0


if __name__ == '__main__':
    sys.exit(main())
