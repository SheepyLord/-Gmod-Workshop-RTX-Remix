"""Audit PMX expression meanings, mine synonyms, and build the importer's reviewed lookup data."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import struct
import unicodedata

# Japanese identities, meaning, expected character side, canonical Source name,
# whether bilateral geometry is required. Side is a statement about the standard
# motion name; candidates always get their actual side from their own geometry.
STANDARDS = [
    ('まばたき', 'blink', 'both', 'blink', True),
    ('笑い', 'blink_smile', 'both', 'eyes_blink_smile', True),
    ('ウィンク|ウインク', 'blink_smile', 'left', 'eye_blink_happy_left', True),
    ('ウィンク右|ウインク右', 'blink_smile', 'right', 'eye_blink_happy_right', True),
    ('ウィンク２|ウインク２', 'blink', 'left', 'eye_blink_left', True),
    ('ウィンク２右|ウインク２右|ｳｨﾝｸ２右', 'blink', 'right', 'eye_blink_right', True),
    ('はぅ', 'squeeze', 'both', 'eyes_sqeeze', True),
    ('なごみ', 'peaceful', 'both', 'eyes_peaceful', True),
    ('じと目|ジト目', 'stare', 'both', 'eyes_stare', True),
    ('びっくり', 'surprised', 'both', 'eyes_surprised', True),
    ('キリッ|ｷﾘｯ', 'sharp', 'both', 'eyes_sharp', True),
    ('なぬ！|なぬ', 'funny', 'both', 'eyes_lower_upper', True),
    ('瞳小', 'pupil_small', 'both', 'eyes_pupil_small', True),
    ('瞳大', 'pupil_big', 'both', 'eyes_pupil_big', True),
    ('見開き', 'enlarge', 'both', 'eyes_enlarge', True),
    ('目尻上げ', 'outer_upper', 'both', 'eyes_outer_upper', True),
    ('目尻下げ', 'outer_lower', 'both', 'eyes_outer_lower', True),
    ('真面目', 'brow_serious', 'both', 'brows_serious', False),
    ('困る', 'brow_worry', 'both', 'brows_worry', False),
    ('にこり', 'brow_happy', 'both', 'brows_cheerful', False),
    ('怒り', 'brow_angry', 'both', 'brows_angry', False),
    ('上', 'brow_up', 'both', 'brows_up', False),
    ('下', 'brow_down', 'both', 'brows_down', False),
    ('平行', 'brow_flat', 'both', 'brows_flat', False),
    ('眉寄せ', 'brow_close', 'both', 'brows_close', False),
    ('あ', 'mouth_a', 'both', 'mouth_a', False),
    ('い', 'mouth_i', 'both', 'mouth_i', False),
    ('う', 'mouth_u', 'both', 'mouth_u', False),
    ('え', 'mouth_e', 'both', 'mouth_e', False),
    ('お', 'mouth_o', 'both', 'mouth_o', False),
    ('ああ', 'mouth_aa', 'both', 'mouth_aa', False),
    ('ワ', 'mouth_wa', 'both', 'mouth_wa', False),
    ('ん', 'mouth_n', 'both', 'mouth_n', False),
    ('にやり', 'mouth_grin', 'both', 'mouth_smug', False),
    ('口角上げ', 'mouth_smile', 'both', 'mouth_up', False),
    ('口角下げ', 'mouth_sad', 'both', 'mouth_down', False),
    ('口横広げ', 'mouth_wide', 'both', 'mouth_widen', False),
    ('口横狭め', 'mouth_narrow', 'both', 'mouth_narrow', False),
    ('▲', 'mouth_triangle', 'both', 'mouth_tri', False),
    ('∧|への字', 'mouth_caret', 'both', 'mouth_closed_tri', False),
    ('ω', 'mouth_cat', 'both', 'mouth_cat', False),
    ('ω□', 'mouth_cat_open', 'both', 'mouth_cat_square', False),
    ('ぺろっ|舌出し', 'tongue_out', 'both', 'mouth_tongue_out', False),
    ('照れ', 'blush', 'both', 'misc_blush', False),
    ('赤面', 'face_red', 'both', 'face_red', False),
    ('青ざめ', 'pale', 'both', 'misc_unwell', False),
    ('涙', 'tears', 'both', 'misc_tears', False),
    ('星目', 'eye_stars', 'both', 'eyes_star_eye', True),
]
CANONICAL_ALIASES = {'eye_blink_happy': '笑い', 'eyes_blink_happy': '笑い',
                     'eyes_calm': 'なごみ', 'eyes_squeeze': 'はぅ', 'eyes_slant': 'キリッ',
                     'brows_happy': 'にこり', 'mouth_grin': 'にやり', 'mouth_smile': '口角上げ',
                     'mouth_sad': '口角下げ', 'mouth_triangle': '▲', 'mouth_caret': '∧',
                     'mouth_cat_open': 'ω□', 'misc_uppershy': '照れ'}
LEGACY_SOURCES = {'なごみ': 'eyes_calm', 'にこり': 'brows_happy', 'にやり': 'mouth_grin',
                  'はぅ': 'eyes_peaceful', 'ぺろっ': 'mouth_lick', 'ん': 'mouth_neutral',
                  'ジト目': 'eyes_staring', '下': 'brows_lower', '口角上げ': 'mouth_grin_2',
                  '口角下げ': 'mouth_sad', '照れ': 'misc_uppershy', '笑い': 'eye_blink_happy',
                  'ｷﾘｯ': 'eyes_slant', 'キリッ': 'eyes_slant'}


def nfkc(name):
    return unicodedata.normalize('NFKC', name)


def shape(morph):
    left = morph.get('left')
    return 'unknown' if left is None else 'left' if left >= .8 else 'right' if left <= .2 else 'both'


def standard_table(models):
    standards, canonical, normalized = {}, {}, {}
    for names, meaning, side, source, eye in STANDARDS:
        entry = dict(meaning=meaning, side=side, source=source, eye=eye,
                     sided=eye or meaning.startswith('brow_'))
        for name in names.split('|'):
            standards[name] = entry
            normalized[nfkc(name)] = entry
        canonical[source] = entry
    for model in models:
        for morph in model.get('morphs', []):
            if nfkc(morph['name']) in normalized:
                standards[morph['name']] = normalized[nfkc(morph['name'])]
    for source, name in CANONICAL_ALIASES.items():
        canonical[source] = standards[name]
    return standards, canonical


def mine_groups(models, standards):
    evidence = defaultdict(Counter)
    recipes = Counter()
    for model in models:
        morphs = {m['name']: m for m in model.get('morphs', [])}
        for m in model.get('morphs', []):
            meaning = standards.get(m['name'])
            children = m.get('children', [])
            if not meaning or not children:
                continue
            recipes[(m['name'], tuple((n, w) for n, w in children))] += 1
            # A single unit-weight child is the same morph. A pair of unit-weight
            # opposite-sided children is the complete bilateral expression. Do
            # not turn one part of a larger recipe into an alleged synonym.
            if any(w != 1 or n not in morphs for n, w in children):
                continue
            if len(children) == 1 or (len(children) == 2 and meaning['side'] == 'both'
                    and {shape(morphs[n]) for n, _ in children} == {'left', 'right'}):
                for name, _ in children:
                    if name not in standards:
                        evidence[name][meaning['meaning']] += 1
    return evidence, recipes


def read_vectors(path):
    """Minimal bounded PMX reader: morph-indexed sparse vertex displacement vectors."""
    data = Path(path).read_bytes()
    p = 0

    def read(fmt):
        nonlocal p
        value = struct.unpack_from('<' + fmt, data, p)
        p += struct.calcsize('<' + fmt)
        return value[0] if len(value) == 1 else value

    def skip(n):
        nonlocal p
        if n < 0 or p + n > len(data):
            raise ValueError('invalid PMX span')
        p += n

    def count():
        n = read('i')
        if not 0 <= n <= 12000000:
            raise ValueError('invalid PMX count')
        return n

    def text():
        skip(count())

    def index(width, unsigned=False):
        return read({1: 'B' if unsigned else 'b', 2: 'H' if unsigned else 'h',
                     4: 'I' if unsigned else 'i'}[width])

    if data[:4] != b'PMX ':
        raise ValueError('not PMX')
    skip(8)
    gn = read('B')
    _, uv, vs, ts, ms, bs, mrs, rs = read('8B')
    skip(gn - 8)
    for _ in range(4):
        text()
    for _ in range(count()):
        skip(32 + 16 * uv)
        deform = read('B')
        skip({0: bs, 1: bs * 2 + 4, 2: bs * 4 + 16, 3: bs * 2 + 40,
              4: bs * 4 + 16}[deform] + 4)
    skip(count() * vs)
    for _ in range(count()):
        text()
    for _ in range(count()):
        text(); text()
        skip(66 + 2 * ts)
        skip(ts if read('B') == 0 else 1)
        text(); skip(4)
    for _ in range(count()):
        text(); text(); skip(12 + bs + 4)
        flags = read('H')
        skip(bs if flags & 1 else 12)
        if flags & 0x300: skip(bs + 4)
        if flags & 0x400: skip(12)
        if flags & 0x800: skip(24)
        if flags & 0x2000: skip(4)
        if flags & 0x20:
            skip(bs + 8)
            for _ in range(count()):
                skip(bs)
                if read('B'): skip(24)
    out = []
    for _ in range(count()):
        text(); text(); skip(1)
        kind, n = read('B'), count()
        vectors = {}
        if kind == 1:
            for _ in range(n):
                vi = index(vs, True)
                delta = read('3f')
                if any(delta): vectors[vi] = delta
        else:
            skip(n * {0: mrs + 4, 2: bs + 28, 3: vs + 16, 4: vs + 16,
                      5: vs + 16, 6: vs + 16, 7: vs + 16, 8: ms + 113,
                      9: mrs + 4, 10: rs + 25}[kind])
        out.append(vectors)
    return out


def similarity(a, b):
    aa = sum(sum(x*x for x in d) for d in a.values())
    bb = sum(sum(x*x for x in d) for d in b.values())
    if aa <= 1e-12 or bb <= 1e-12:
        return 0., 0.
    dot = sum(sum(x*y for x, y in zip(v, b[i])) for i, v in a.items() if i in b)
    return dot / (aa*bb)**.5, (aa/bb)**.5


def mine_offsets(models, standards, limit):
    evidence, samples, failures = defaultdict(Counter), [], []
    # Spread the sample over model families, not adjacent files/costume copies.
    candidates = sorted((m for m in models if 'morphs' in m),
                        key=lambda m: hashlib.sha256(m['path'].encode()).digest())
    for model in candidates:
        if len(samples) >= limit:
            break
        morphs = model['morphs']
        targets = [m for m in morphs if m['name'] in standards and m['type'] == 1 and m['panel'] in (1, 2, 3)]
        others = [m for m in morphs if m['name'] not in standards and m['type'] == 1 and m['panel'] in (1, 2, 3)]
        if not targets or not others:
            continue
        try:
            vectors = read_vectors(model['path'])
            for a in targets:
                for b in others:
                    # Require the same facial panel, measured side, and nearly
                    # identical offsets at unit weight, not merely common vertices.
                    if a['panel'] != b['panel'] or shape(a) != shape(b):
                        continue
                    cosine, scale = similarity(vectors[a['i']], vectors[b['i']])
                    if cosine >= .995 and .95 <= scale <= 1.05:
                        evidence[b['name']][standards[a['name']]['meaning']] += 1
            samples.append(model['path'])
        except (OSError, ValueError, KeyError, struct.error) as e:
            failures.append(dict(path=model['path'], error=str(e)))
    return evidence, samples, failures


def resolve(model, name, table):
    if any(m['name'] == name for m in model.get('morphs', [])):
        return 'name'
    standard = table['standard'].get(name)
    if not standard:
        return 'unresolved'
    sides = set()
    for m in model.get('morphs', []):
        candidate = (table['standard'].get(m['name']) or table['aliases'].get(m['name'])
                     or table['canonical'].get(m['name']) or table['canonical'].get(m['name'].lower()))
        if candidate and candidate['meaning'] == standard['meaning']:
            sides.add(shape(m) if standard['sided'] else 'both')
    if (standard['side'] == 'both' and ('both' in sides or {'left', 'right'} <= sides)
            or standard['side'] in ('left', 'right') and standard['side'] in sides):
        return 'meaning'
    return 'unresolved'


def audit(models, offset_limit=0, motion_names=None):
    standards, canonical = standard_table(models)
    groups, recipes = mine_groups(models, standards)
    offsets, samples, failures = mine_offsets(models, standards, offset_limit)
    evidence = defaultdict(Counter)
    for source in (groups, offsets):
        for name, counts in source.items(): evidence[name].update(counts)
    aliases, rejected = {}, {}
    for name, counts in sorted(evidence.items()):
        # Ambiguity is evidence against automatic mapping. Three corroborating
        # corpus observations are required to generalize a new synonym.
        if len(counts) == 1 and sum(counts.values()) >= 3:
            aliases[name] = {'meaning': next(iter(counts)), 'observations': sum(counts.values())}
        else:
            rejected[name] = dict(counts)
    table = dict(version=2, standard=standards, canonical=canonical, aliases=aliases, legacy=LEGACY_SOURCES)
    statistics = {}
    for name in sorted({nfkc(n) for n in standards} | set(aliases)):
        # One record per normalized name per model. Costume variants remain
        # separate models; duplicate controllers within a PMX do not inflate it.
        rows = [next((m for m in model.get('morphs', []) if nfkc(m['name']) == name), None) for model in models]
        rows = [m for m in rows if m is not None]
        if rows:
            statistics[name] = dict(count=len(rows), sides=dict(Counter(shape(m) for m in rows)),
                                    panels=dict(Counter(str(m['panel']) for m in rows)))
    names = motion_names or [n.split('|')[0] for n, *_ in STANDARDS]
    counts = Counter(resolve(model, name, table) for model in models if 'morphs' in model for name in names)
    total = sum(counts.values())
    report = dict(models=len(models), readable=sum('morphs' in m for m in models),
                  names=names, pairs=total, coverage=dict(counts),
                  coverage_percent={k: round(v*100/total, 3) for k, v in counts.items()},
                  statistics=statistics, group_synonyms={n: dict(c) for n, c in groups.items()},
                  offset_synonyms={n: dict(c) for n, c in offsets.items()},
                  offset_samples=samples, offset_failures=failures, rejected=rejected,
                  recipes=[dict(name=n, children=c, models=k) for (n, c), k in recipes.most_common()])
    return table, report


def cp932_table():
    out = {}
    for i in range(256):
        for raw in ([bytes([i])] + [bytes([i, j]) for j in range(256)] if 0x81 <= i <= 0x9f or 0xe0 <= i <= 0xfc else [bytes([i])]):
            try:
                text = raw.decode('cp932')
                if len(text) == 1:
                    out[str(int.from_bytes(raw, 'big'))] = text
            except UnicodeDecodeError:
                pass
    return out


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf8')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--corpus', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--data', type=Path, help='staged data_static/mmd_vmd_npc (never packages/)')
    ap.add_argument('--sample-offsets', type=int, default=24)
    ap.add_argument('--motion', type=Path, help='imported motion JSON for corpus coverage')
    args = ap.parse_args()
    if args.data and 'packages' in args.data.resolve().parts:
        ap.error('stage under out/ and import with tools/inputs.py')
    models = [json.loads(l) for l in args.corpus.read_text(encoding='utf8').splitlines() if l]
    motion = json.loads(args.motion.read_text(encoding='utf8')) if args.motion else None
    names = list(dict.fromkeys(m.get('m', m.get('mmd', '')) for m in motion.get('flexes', []))) if motion else None
    table, report = audit(models, max(0, args.sample_offsets), names)
    write_json(args.out, report)
    if args.data:
        write_json(args.data / 'morph_semantics.json', table)
        write_json(args.data / 'cp932.json', cp932_table())
    print(json.dumps({k: report[k] for k in ('models', 'readable', 'pairs', 'coverage', 'coverage_percent')}, indent=2))
    print(f"{len(table['aliases'])} accepted synonyms, {len(report['offset_samples'])} offset samples")


if __name__ == '__main__':
    main()
