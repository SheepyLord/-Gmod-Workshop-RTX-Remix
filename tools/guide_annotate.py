"""Makes the RTX Remix guide's pictures from real in-game captures: crops each capture (never scales
it) and draws numbered badges with arrows that point at the exact control, as the spec in
tools/guide_pictures.json says. See guide_annotate.py.md.

  python tools/guide_annotate.py --shots <captures> [--only NAME ...] [--out <folder>]
  python tools/guide_annotate.py --grid <capture.png> [--crop x0,y0,x1,y1] --to <grid.png>
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
SPEC = TOOLS / 'guide_pictures.json'
OUT = REPO / 'companion' / 'nativeloader' / 'materials' / 'nativeloader' / 'guide'


class SpecError(Exception):
    pass


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    for name in (('arialbd.ttf', 'segoeuib.ttf') if bold else ('arial.ttf', 'segoeui.ttf')):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def find_capture(shots: Path, pattern: str) -> Path:
    matches = sorted(shots.glob(pattern))
    if not matches:
        raise SpecError(f'no capture matches {pattern} in {shots}')
    return matches[-1]


def nearest_on_box(box, point):
    """The point of the rectangle's edge nearest to `point` (outside the box)."""
    x0, y0, x1, y1 = box
    px, py = point
    return min(max(px, x0), x1), min(max(py, y0), y1)


def arrow_end(badge, target, box):
    if box:
        return nearest_on_box(box, badge)
    return target


def check(name, spec, size, style):
    """Problems a reader would see: a crop off the capture, a badge off the crop, over its target or over
    another badge, an arrow too short to read."""
    problems = []
    x0, y0, x1, y1 = spec['crop']
    if not (0 <= x0 < x1 <= size[0] and 0 <= y0 < y1 <= size[1]):
        problems.append(f'{name}: crop {spec["crop"]} is outside the {size[0]}x{size[1]} capture')
    radius = style['radius']
    centres = []
    for number, badge in enumerate(spec['badges'], 1):
        bx, by = badge['at']
        if not (x0 + radius <= bx <= x1 - radius and y0 + radius <= by <= y1 - radius):
            problems.append(f'{name} badge {number}: {badge["at"]} is not inside the crop')
        box = badge.get('box')
        target = badge.get('target') or (box and ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2))
        if not target:
            problems.append(f'{name} badge {number}: needs a target or a box')
            continue
        if box:
            ex, ey = nearest_on_box(box, (bx, by))
            if box[0] - radius - 2 < bx < box[2] + radius + 2 and box[1] - radius - 2 < by < box[3] + radius + 2:
                problems.append(f'{name} badge {number}: it covers its box {box}')
        else:
            ex, ey = target
        if math.hypot(ex - bx, ey - by) < radius + 12:
            problems.append(f'{name} badge {number}: too close to what it points at')
        for other, (ox, oy) in enumerate(centres, 1):
            if math.hypot(ox - bx, oy - by) < 2 * radius + 4:
                problems.append(f'{name} badges {other} and {number} overlap')
        centres.append((bx, by))
    return problems


def draw_arrow(draw, start, end, style, radius):
    """A line from the badge's edge to `end`, with a head at `end`: dark outline, then the colour."""
    sx, sy = start
    ex, ey = end
    angle = math.atan2(ey - sy, ex - sx)
    sx, sy = sx + math.cos(angle) * radius, sy + math.sin(angle) * radius
    head, spread = style['head'], 0.45
    left = (ex - head * math.cos(angle - spread), ey - head * math.sin(angle - spread))
    right = (ex - head * math.cos(angle + spread), ey - head * math.sin(angle + spread))
    base = (ex - head * 0.8 * math.cos(angle), ey - head * 0.8 * math.sin(angle))
    width = style['arrow']
    draw.line([(sx, sy), base], fill=tuple(style['outline']), width=width + 4)
    draw.polygon([(ex, ey), left, right], fill=tuple(style['outline']))
    draw.line([(sx, sy), base], fill=tuple(style['color']), width=width)
    # The head, a little smaller than its outline.
    inner = 0.72
    cx, cy = (ex + left[0] + right[0]) / 3, (ey + left[1] + right[1]) / 3
    shrink = lambda p: (cx + (p[0] - cx) * inner, cy + (p[1] - cy) * inner)  # noqa: E731
    draw.polygon([shrink((ex, ey)), shrink(left), shrink(right)], fill=tuple(style['color']))


def draw_badge(draw, centre, number, style):
    x, y = centre
    r = style['radius']
    draw.ellipse([x - r - 2, y - r - 2, x + r + 2, y + r + 2], fill=tuple(style['outline']))
    draw.ellipse([x - r, y - r, x + r, y + r], fill=tuple(style['color']))
    draw.text((x, y + 1), str(number), fill=tuple(style['number']), font=font(style['font']), anchor='mm')


def render(spec, shots: Path, style) -> Image.Image:
    source = find_capture(shots, spec['capture'])
    capture = Image.open(source).convert('RGB')
    problems = check(spec['name'], spec, capture.size, style)
    if problems:
        raise SpecError('\n'.join(problems))
    x0, y0, x1, y1 = spec['crop']
    image = capture.crop((x0, y0, x1, y1))
    draw = ImageDraw.Draw(image)
    shift = lambda p: (p[0] - x0, p[1] - y0)  # noqa: E731
    # Boxes and arrows first, badges on top, so no line crosses a number.
    for badge in spec['badges']:
        box = badge.get('box')
        if box:
            bx0, by0, bx1, by1 = shift(box[:2]) + shift(box[2:])
            draw.rounded_rectangle([bx0 - 1, by0 - 1, bx1 + 1, by1 + 1], radius=4, outline=tuple(style['outline']), width=4)
            draw.rounded_rectangle([bx0, by0, bx1, by1], radius=3, outline=tuple(style['color']), width=2)
        target = badge.get('target')
        end = arrow_end(badge['at'], target, box)
        draw_arrow(draw, shift(badge['at']), shift(end), style, style['radius'] + 2)
    for number, badge in enumerate(spec['badges'], 1):
        draw_badge(draw, shift(badge['at']), number, style)
    return image


def save(image: Image.Image, path: Path, style) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Baseline JPEG, no chroma subsampling: coloured UI text stays sharp.
    image.save(path, 'JPEG', quality=style['quality'], subsampling=0, optimize=True, progressive=False)
    return path.stat().st_size


def load_spec(path: Path):
    data = json.loads(path.read_text(encoding='utf-8'))
    style = data['style']
    pictures = data['pictures']
    for name, spec in pictures.items():
        spec['name'] = name
        for key in ('capture', 'crop', 'badges'):
            if key not in spec:
                raise SpecError(f'{name}: no {key}')
    return style, pictures


def grid(capture: Path, crop, to: Path, step: int = 50) -> None:
    """A copy of a capture (or of a crop of it) with a labelled grid in capture pixels, for writing specs."""
    image = Image.open(capture).convert('RGB')
    x0, y0 = 0, 0
    if crop:
        x0, y0, x1, y1 = crop
        image = image.crop(crop)
    draw = ImageDraw.Draw(image)
    small = font(11, bold=False)
    for x in range((x0 // step + 1) * step, x0 + image.width, step):
        draw.line([(x - x0, 0), (x - x0, image.height)], fill=(255, 0, 255) if x % (step * 2) == 0 else (0, 200, 255), width=1)
        draw.text((x - x0 + 2, 2), str(x), fill=(255, 0, 255), font=small)
    for y in range((y0 // step + 1) * step, y0 + image.height, step):
        draw.line([(0, y - y0), (image.width, y - y0)], fill=(255, 0, 255) if y % (step * 2) == 0 else (0, 200, 255), width=1)
        draw.text((2, y - y0 + 2), str(y), fill=(255, 0, 255), font=small)
    to.parent.mkdir(parents=True, exist_ok=True)
    image.save(to)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--spec', type=Path, default=SPEC, help='the pictures (default tools/guide_pictures.json)')
    parser.add_argument('--shots', type=Path, help='the folder the captures are in (capture patterns are relative to it)')
    parser.add_argument('--out', type=Path, default=OUT, help='where the JPEGs go (default the guide folder)')
    parser.add_argument('--only', nargs='*', help='make only these pictures')
    parser.add_argument('--grid', type=Path, help='write a gridded copy of this capture instead (with --to)')
    parser.add_argument('--crop', type=lambda text: [int(v) for v in text.split(',')], help='with --grid: x0,y0,x1,y1')
    parser.add_argument('--to', type=Path, help='with --grid: the PNG to write')
    args = parser.parse_args(argv)
    if args.grid:
        if not args.to:
            parser.error('--grid needs --to')
        grid(args.grid, args.crop, args.to)
        print('wrote', args.to)
        return 0
    if not args.shots:
        parser.error('--shots is needed')
    try:
        style, pictures = load_spec(args.spec)
        names = args.only or list(pictures)
        total, failed = 0, []
        for name in names:
            if name not in pictures:
                raise SpecError(f'{name} is not in {args.spec}')
            try:
                image = render(pictures[name], args.shots, style)
            except SpecError as error:
                failed.append(str(error))
                continue
            size = save(image, args.out / f'{name}.jpg', style)
            total += size
            note = '' if size <= style['max_bytes'] else f'  OVER {style["max_bytes"]:,} bytes'
            if note:
                failed.append(f'{name}: {size:,} bytes, more than {style["max_bytes"]:,}')
            print(f'{name}.jpg  {image.width}x{image.height}  {len(pictures[name]["badges"])} badges  {size:,} bytes{note}')
        print(f'{len(names) - len(failed)} pictures, {total:,} bytes')
    except (SpecError, OSError, ValueError, KeyError) as error:
        print(f'guide_annotate: {error}', file=sys.stderr)
        return 1
    if failed:
        print('guide_annotate: ' + '\n'.join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
