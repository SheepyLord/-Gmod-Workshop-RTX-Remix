"""Merges Remix config files into the one defaults layer a runtime package ships (ADR 0021). Later
files win key by key, so passing the classic install's dxvk.conf, rtx.conf and user.conf in that order
reproduced its precedence (user.conf over rtx.conf over dxvk.conf) in a single file; the shipped layer
(packages/runtime/layers/classic_remix_defaults.conf) is now regenerated from itself. A few options are
pinned whatever the files say (PINNED). Reads only its inputs; writes the one output file."""
import argparse
import re
import sys
from pathlib import Path


def read_conf(path: Path) -> dict:
    """`key = value` lines in file order; '#' comments and blank lines skipped; a repeated key keeps
    its first position and its last value, as the runtime's parser does."""
    values = {}
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        text = line.strip()
        if not text or text.startswith('#') or '=' not in text:
            continue
        key, value = text.split('=', 1)
        values[key.strip()] = value.strip()
    return values


HASH = re.compile(r'^-?0x[0-9A-Fa-f]+$')


def hash_tokens(value: str):
    """The tokens of a texture-hash set (`0x..` adds, `-0x..` removes), or None for any other value."""
    tokens = [t.strip() for t in value.split(',') if t.strip()]
    return tokens if tokens and all(HASH.match(t) for t in tokens) else None


def merge(paths: list[Path]) -> tuple[dict, dict]:
    """Later files win, except texture-hash sets (rtx.*Textures and the like): Remix combines those
    across layers, each stronger layer adding its hashes and removing its `-0x..` ones. They are
    combined the same way here, keeping the net removals as `-` tokens."""
    merged, origin, sets = {}, {}, {}
    for path in paths:
        for key, value in read_conf(path).items():
            tokens = hash_tokens(value)
            if tokens is not None and (key in sets or key not in merged):
                adds, removes = sets.setdefault(key, ({}, {}))
                for token in tokens:
                    digest = token.lstrip('-').lower()
                    if token.startswith('-'):
                        adds.pop(digest, None)
                        removes[digest] = token.lstrip('-')
                    else:
                        removes.pop(digest, None)
                        adds[digest] = token
                merged[key] = ', '.join(list(adds.values()) + ['-' + h for h in removes.values()])
            else:
                sets.pop(key, None)
                merged[key] = value
            origin[key] = path.name
    return merged, origin


# Options that depend on the player's GPU, which the classic install (an RTX 5090's) cannot decide for
# everyone (ADR 0037): frame generation stays off, and a player who turns DLSS-G on gets one generated
# frame (2x), which RTX 40 supports. DLSS-G at 3x crashed RTX 30, RTX 40 and AMD GPUs at start, and Remix's
# menu hides the multiplier where multi-frame generation is unsupported, so it could not be changed.
GPU_DEPENDENT = {'rtx.frameGenerationType': '0', 'rtx.dlfg.enable': 'False', 'rtx.dlfg.maxInterpolatedFrames': '1'}

# Shared player texture captures also affect arms, NPCs and ragdolls. First-person proxies own
# private texture categories instead (ADR 0043).
PLAYER_CATEGORIES = {'rtx.playerModelTextures': '', 'rtx.playerModelBodyTextures': '',
                     'rtx.playerModel.enableInPrimarySpace': 'False'}

# Path bounces default to 1 to 12, as in the runtime's metadata and graphics presets (ADR 0051),
# whatever the merged files say.
PATH_BOUNCES = {'rtx.pathMinBounces': '1', 'rtx.pathMaxBounces': '12'}

PINNED = GPU_DEPENDENT | PLAYER_CATEGORIES | PATH_BOUNCES


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', nargs='+', type=Path, help='config files, weakest first')
    parser.add_argument('--out', type=Path, required=True, help='the merged layer to write')
    args = parser.parse_args(argv)
    missing = [str(p) for p in args.inputs if not p.is_file()]
    if missing:
        print('error: missing ' + ', '.join(missing), file=sys.stderr)
        return 1
    merged, origin = merge(args.inputs)
    for key, value in PINNED.items():
        merged[key] = value
        origin[key] = 'remix_defaults.py'
    header = ['# Remix defaults for the native loader package, merged by tools/remix_defaults.py (ADR 0021).',
              '# Sources, weakest first: ' + ', '.join(p.name for p in args.inputs) + '.',
              '# Frame generation is left off and at one generated frame: it depends on the GPU (ADR 0037).',
              '# Player texture categories are assigned to private local-body proxies (ADR 0043).',
              '# The player\'s own rtx.conf and user.conf in the game folder override every value here.']
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text('\n'.join(header + [f'{k} = {v}'.rstrip() for k, v in merged.items()]) + '\n', encoding='utf-8', newline='\n')
    counts = {}
    for name in origin.values():
        counts[name] = counts.get(name, 0) + 1
    print(f'{args.out}: {len(merged)} settings (' + ', '.join(f'{n} from {c}' for c, n in counts.items()) + ')')
    return 0


if __name__ == '__main__':
    sys.exit(main())
