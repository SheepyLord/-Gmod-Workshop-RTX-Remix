"""Writes the companion's table of weather presets: the 12 weather archetypes of the user's Remix fork
(dxvk-remix-gmod), with the Remix option each of their fields sets, read from the fork's sources,
and what Remix has for each such option when nothing sets it (the package's classic layer, else the
runtime's default), which the weather goes back to when it is left to Remix again. The companion's
sky (nativeloader_sky.lua) blends between the presets through RemixConfig.SetConfigVariable, because
the RTX fixes give Lua no way to the runtime's own blender (remixapi_SetGameValue). Reads the fork as
the runtime is built from it (runtime/base.json's commit with runtime/patches applied, R17), or with --fork
a checkout as it is. Reads only; writes the one Lua file (and scratch under out/tmp)."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FORK = Path(r'H:\BACKUP_20260815\Modding\dxvk-remix-gmod')
OUT = REPO / 'companion' / 'nativeloader' / 'lua' / 'nativeloader' / 'weather_presets.lua'
RENDER = Path('src') / 'dxvk' / 'rtx_render'
HEADER = RENDER / 'rtx_weather.h'
BLENDER = RENDER / 'rtx_weather.cpp'
# Where the options a preset field drives are declared (category, type and name of each RTX_OPTION).
OPTION_HEADERS = [RENDER / 'rtx_atmosphere.h', RENDER / 'rtx_global_volumetrics.h', RENDER / 'rtx_precipitation.h']
OPTION_MACROS = ('RTX_OPTION', 'RTX_OPTION_ARGS', 'RTX_OPTION_FLAG', 'RTX_OPTION_ENV')  # the default is the 4th argument of each
# The files read from the fork, and what the runtime is built from (ADR 0034): a commit of the fork
# and this repository's patches to it.
SOURCES = [HEADER, BLENDER, *OPTION_HEADERS]
BASE = REPO / 'runtime' / 'base.json'
PATCHES = REPO / 'runtime' / 'patches'
SCRATCH = REPO / 'out' / 'tmp'
# The package's low Remix layer (ADR 0021): what it sets is Remix's own value in an RTX session.
LAYER = REPO / 'packages' / 'runtime' / 'layers' / 'classic_remix_defaults.conf'
# Options the companion's weather sets beside the preset fields (its WEATHER_LOOK): every one of these.
PRECIPITATION = 'rtx.weather.precipitation.'
# The blender's field kinds, as the companion interpolates them. The two display kinds (km/s shown as
# m/s, 1/km shown as km) blend linearly on the stored value, as in the runtime.
KINDS = {'WK_Scalar': 'scalar', 'WK_Angle': 'angle', 'WK_Extinction': 'extinction', 'WK_Color': 'color',
         'WK_Vec3': 'vec3', 'WK_Step': 'step', 'WK_SpeedKmS': 'scalar', 'WK_PatchPerKm': 'scalar'}


class SourceError(Exception):
    pass


def macro_body(text: str, name: str) -> str:
    """The body of `#define <name>(...)`: its continuation lines joined, comments removed."""
    match = re.search(r'^#define\s+' + re.escape(name) + r'\b[^\n]*', text, re.M)
    if not match:
        raise SourceError(f'#define {name} not found')
    lines, rest = [match.group(0)], text[match.end() + 1:].split('\n')
    while lines[-1].rstrip().endswith('\\') and rest:
        lines.append(rest.pop(0))
    body = ' '.join(line.rstrip().rstrip('\\') for line in lines)
    body = re.sub(r'/\*.*?\*/', ' ', body)
    return body.split(')', 1)[1] if body.startswith('#define') else body


def calls(body: str, function: str) -> list[list[str]]:
    """The argument lists of every `function(...)` call in a macro body, split at top-level commas."""
    found, start = [], 0
    pattern = re.compile(r'\b' + re.escape(function) + r'\(')
    while (match := pattern.search(body, start)):
        depth, i, args, current, quoted = 1, match.end(), [], '', False
        while depth:
            c = body[i]
            if c == '"':
                quoted = not quoted
            elif not quoted and c == '(':
                depth += 1
            elif not quoted and c == ')':
                depth -= 1
                if not depth:
                    break
            elif not quoted and c == ',' and depth == 1:
                args.append(current.strip())
                current = ''
                i += 1
                continue
            current += c
            i += 1
        args.append(current.strip())
        found.append(args)
        start = i + 1
    return found


def value(text: str, type_: str):
    """A C++ literal of a preset table as a Python value: float, bool or a list of three floats."""
    text = text.strip()
    if type_ == 'bool':
        if text not in ('true', 'false'):
            raise SourceError(f'bad bool {text!r}')
        return text == 'true'
    if type_ == 'Vector3':
        match = re.fullmatch(r'Vector3\(([^)]*)\)', text)
        parts = match.group(1).split(',') if match else []
        if len(parts) != 3:
            raise SourceError(f'bad Vector3 {text!r}')
        return [float(p.strip().rstrip('f')) for p in parts]
    return float(text.rstrip('f'))


def option_name(field: str, group: str) -> str:
    """The live option a preset field drives: the blender's snapshotRenderer reads exactly these."""
    if field.startswith('precipitation'):
        rest = field[len('precipitation'):]
        return 'rtx.weather.precipitation.' + rest[0].lower() + rest[1:]
    if field == 'volumetricAnisotropy':
        return 'rtx.volumetrics.anisotropy'
    if group == 'Volumetric Fog':
        return 'rtx.volumetrics.' + field
    return 'rtx.atmosphere.' + field


def declared_options(fork: Path) -> dict[str, str]:
    """Full option name -> C++ type of every RTX_OPTION in the option headers."""
    options = {}
    for header in OPTION_HEADERS:
        text = (fork / header).read_text(encoding='utf-8')
        for category, type_, name in re.findall(
                r'RTX_OPTION(?:_ARGS|_FLAG|_ENV)?\(\s*"([^"]+)"\s*,\s*([A-Za-z0-9_:]+)\s*,\s*([A-Za-z0-9_]+)\s*,', text):
            options[f'{category}.{name}'] = type_
    return options


def option_text(literal: str, type_: str) -> str | None:
    """An RTX_OPTION's C++ default as Remix's option text (as rtx.conf and SetConfigVariable take it),
    or None for an expression this does not read."""
    text = literal.strip()
    try:
        if type_ == 'bool':
            return {'true': 'True', 'false': 'False'}[text]
        if type_ == 'Vector3':
            return ', '.join(lua_value(v) for v in value(text, 'Vector3'))
        if type_ in ('int', 'uint32_t', 'uint16_t', 'uint8_t'):
            return str(int(text.rstrip('uU')))
        if type_ == 'float':
            return lua_value(float(text.rstrip('f')))
    except (KeyError, ValueError, SourceError):
        return None
    return None


def option_defaults(fork: Path) -> dict[str, str]:
    """Full option name -> its default as option text, for every RTX_OPTION of the option headers whose
    category is a plain string and whose default is a literal."""
    defaults = {}
    for header in OPTION_HEADERS:
        text = (fork / header).read_text(encoding='utf-8')
        for macro in OPTION_MACROS:
            for args in calls(text, macro):
                if len(args) < 4 or not re.fullmatch(r'"[^"]+"', args[0]) or not re.fullmatch(r'\w+', args[2]):
                    continue  # a category made in a macro (the moons' "rtx.atmosphere.moon" #N)
                converted = option_text(args[3], args[1])
                if converted is not None:
                    defaults[f'{args[0][1:-1]}.{args[2]}'] = converted
    return defaults


def read_layer(path: Path) -> dict[str, str]:
    """option -> value text of a Remix .conf file (name = value lines; # comments)."""
    found = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.split('#', 1)[0].strip()
        if '=' in line:
            name, text = (part.strip() for part in line.split('=', 1))
            found[name] = text
    return found


def read_presets(fork: Path, layer: Path | None = LAYER) -> dict:
    header = (fork / HEADER).read_text(encoding='utf-8')
    fields = []
    for args in calls(macro_body(header, 'WEATHER_PRESET_FIELD_LIST'), 'X'):
        if len(args) != 11:
            raise SourceError(f'field list entry with {len(args)} arguments: {args}')
        type_, name, _default, kind, group = args[0], args[1], args[2], args[3], args[4].strip('"')
        if kind not in KINDS:
            raise SourceError(f'{name}: unknown kind {kind}')
        fields.append({'name': name, 'type': type_, 'kind': KINDS[kind], 'group': group, 'label': args[6].strip('"')})
    order = [args[0] for args in calls(macro_body(header, 'DECLARE_ALL_WEATHER_PRESETS'), 'DECLARE_WEATHER_PRESET')]
    if len(order) != 12 or len(set(order)) != 12:
        raise SourceError(f'expected 12 presets, found {order}')
    types = {f['name']: f['type'] for f in fields}
    presets = {}
    for preset in order:
        entries = calls(macro_body(header, f'WEATHER_PRESET_VALUES_{preset}'), 'X')
        values = {}
        for type_, name, literal in entries:
            if name not in types or types[name] != type_ or name in values:
                raise SourceError(f'{preset}: unexpected or repeated field {type_} {name}')
            values[name] = value(literal, type_)
        missing = [f['name'] for f in fields if f['name'] not in values]
        if missing:
            raise SourceError(f'{preset}: no value for {missing}')
        presets[preset] = values
    # Fields the blender takes over only when the presets disagree on them (resolveLegacyWeatherOwnership);
    # the rest it always owns while a weather is set.
    blender = (fork / BLENDER).read_text(encoding='utf-8')
    conditional = set(re.findall(r'^\s*FALLBACK_IF_INVARIANT\((\w+)\);', blender, re.M))
    unknown = conditional - set(types)
    if unknown or not conditional:
        raise SourceError(f'FALLBACK_IF_INVARIANT list unreadable or naming unknown fields: {sorted(unknown)}')
    declared = declared_options(fork)
    for f in fields:
        f['option'] = option_name(f['name'], f['group'])
        option_type = declared.get(f['option'])
        if option_type is None:
            raise SourceError(f"{f['name']}: the option {f['option']} is not declared in the fork")
        f['integer'] = option_type in ('int', 'uint32_t', 'uint16_t', 'uint8_t')
        same = all(presets[p][f['name']] == presets[order[0]][f['name']] for p in order)
        f['owned'] = f['name'] not in conditional or not same
    # What the weather puts back when it is left to Remix again: every option it sets.
    known = option_defaults(fork)
    wanted = {f['option'] for f in fields if f['owned']} | {o for o in declared if o.startswith(PRECIPITATION)}
    missing = sorted(o for o in wanted if o not in known)
    if missing:
        raise SourceError(f'the defaults of {missing} cannot be read from the fork')
    defaults = {o: known[o] for o in wanted}
    if layer is not None and layer.is_file():
        defaults.update({o: text for o, text in read_layer(layer).items() if o in wanted})
    return {'fields': fields, 'order': order, 'presets': presets, 'defaults': defaults,
            'header_sha256': hashlib.sha256((fork / HEADER).read_bytes()).hexdigest()}


def patched_sources(fork: Path, scratch: Path, base: Path = BASE, patches: Path = PATCHES) -> str:
    """Writes the files this tool reads under scratch as runtime/build_runtime.ps1 builds them: the fork's
    commit named in base.json, with every patch of the patches folder applied in name order (only the
    hunks of those files). The patches change the presets too (R17), so the fork's checkout alone is not
    what the runtime has. Returns a description of the source for the table's first line."""
    commit = json.loads(base.read_text(encoding='utf-8'))['commit']
    for rel in SOURCES:
        done = subprocess.run(['git', '-C', str(fork), 'show', f'{commit}:{rel.as_posix()}'], capture_output=True,
                              timeout=120)
        if done.returncode:
            raise SourceError(f'{rel.as_posix()} at {commit[:8]}: '
                              + done.stderr.decode('utf-8', 'replace').strip())
        (scratch / rel).parent.mkdir(parents=True, exist_ok=True)
        (scratch / rel).write_bytes(done.stdout)
    # git apply on plain files: the ceiling keeps git from taking this repository (scratch is inside it)
    # for the one to patch.
    env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(scratch.parent))
    includes = [f'--include={rel.as_posix()}' for rel in SOURCES]
    applied = sorted(patches.glob('*.patch'))
    for patch in applied:
        done = subprocess.run(['git', 'apply', '--whitespace=nowarn', *includes, str(patch)], cwd=scratch, env=env,
                              capture_output=True, timeout=300)
        if done.returncode:
            raise SourceError(f'{patch.name} does not apply to the fork at {commit[:8]}: '
                              + done.stderr.decode('utf-8', 'replace').strip()[:400])
    return f'{commit[:8]} + {len(applied)} runtime/patches'


def fork_commit(fork: Path) -> str:
    try:
        done = subprocess.run(['git', '-C', str(fork), 'rev-parse', '--short=8', 'HEAD'], capture_output=True,
                              text=True, timeout=30)
        return done.stdout.strip() or 'unknown'
    except (OSError, subprocess.SubprocessError):
        return 'unknown'


def lua_value(v) -> str:
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, list):
        return '{ ' + ', '.join(lua_value(x) for x in v) + ' }'
    text = repr(float(v))
    return text[:-2] if text.endswith('.0') else text


def generate(data: dict, commit: str) -> str:
    owned = [f for f in data['fields'] if f['owned']]
    left = [f['name'] for f in data['fields'] if not f['owned']]
    lines = ['-- Generated by tools/weather_presets.py; do not edit. The weather presets of the Remix fork',
             f"-- (dxvk-remix-gmod {commit}, rtx_weather.h SHA-256 {data['header_sha256'][:16]}): each field with",
             '-- the option it sets and how it blends. Fields every preset leaves alike, which the runtime',
             '-- leaves to the configuration too, are not here: ' + ', '.join(left) + '.',
             'return {',
             '  order = { ' + ', '.join(f'"{p}"' for p in data['order']) + ' },',
             '  fields = {']
    for f in owned:
        extra = ', integer = true' if f['integer'] else ''
        lines.append(f'    {{ name = "{f["name"]}", option = "{f["option"]}", kind = "{f["kind"]}"{extra} }},')
    lines += ['  },',
              "  -- What Remix has for each option the weather sets, when rtx.conf does not set it: the package's",
              "  -- classic layer, else the runtime's default. Leaving the weather to Remix puts these back.",
              '  defaults = {']
    for option in sorted(data.get('defaults', {})):
        text = data['defaults'][option].replace('\\', '\\\\').replace('"', '\\"')
        lines.append(f'    ["{option}"] = "{text}",')
    lines += ['  },', '  presets = {']
    for preset in data['order']:
        lines.append(f'    {preset} = {{')
        lines += [f"      {f['name']} = {lua_value(data['presets'][preset][f['name']])}," for f in owned]
        lines.append('    },')
    lines += ['  },', '}']
    return '\n'.join(lines) + '\n'


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fork', type=Path, default=None,
                        help='a Remix fork tree to read as it is (default: the fork checkout at runtime/base.json\'s '
                             'commit with runtime/patches applied, as the runtime is built)')
    parser.add_argument('--out', type=Path, default=OUT, help='the Lua table to write')
    parser.add_argument('--layer', type=Path, default=LAYER, help="the package's classic Remix layer (its values win over the runtime's defaults)")
    parser.add_argument('--check', action='store_true', help='exit 1 when --out differs from what would be written')
    args = parser.parse_args(argv)
    scratch = None
    try:
        if args.fork is None:
            SCRATCH.mkdir(parents=True, exist_ok=True)
            scratch = Path(tempfile.mkdtemp(prefix='weather-presets-fork-', dir=SCRATCH))
            source = patched_sources(FORK, scratch)
            data = read_presets(scratch, args.layer)
        else:
            source = fork_commit(args.fork)
            data = read_presets(args.fork, args.layer)
    except (OSError, SourceError, ValueError, subprocess.SubprocessError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    finally:
        if scratch is not None:
            shutil.rmtree(scratch, ignore_errors=True)
    text = generate(data, source)
    current = args.out.read_text(encoding='utf-8') if args.out.is_file() else None
    # The commit line names the fork's checkout, which moves on without the presets changing; compare
    # the presets (the header hash is in that line too, so compare from the line after it).
    same = current is not None and current.splitlines()[2:] == text.splitlines()[2:]
    if args.check:
        print('up to date' if same else f'{args.out} differs from the fork')
        return 0 if same else 1
    if not same:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding='utf-8', newline='\n')
    owned = sum(1 for f in data['fields'] if f['owned'])
    print(f"{args.out}: {len(data['order'])} presets, {owned} of {len(data['fields'])} fields"
          + (' (unchanged)' if same else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
