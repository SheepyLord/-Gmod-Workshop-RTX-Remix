"""Validate bundled add-on catalogs and their real language selectors. See check_addon_i18n.py.md."""
import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LANGUAGES = ('zh', 'zh-tw', 'ja', 'ko', 'fr', 'ru')
PLACEHOLDER = re.compile(r'\{+\s*[A-Za-z_][A-Za-z_0-9]*\s*\}+')
FORMAT = re.compile(r'%[-+ #0]*\d*(?:\.\d+)?[diouxXeEfFgGcs%]')


def luajit():
    found = shutil.which('luajit')
    local = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
    return found or (str(local) if local.is_file() else None)


def read_catalogs(root=REPO, lua=None):
    lua = lua or luajit()
    if not lua:
        raise RuntimeError('LuaJIT is required to exercise the bundled add-ons; no game is started')
    run = subprocess.run([lua, str(root / 'tools/tests/addon_i18n_harness.lua')], cwd=root,
                         capture_output=True, encoding='utf-8', timeout=60)
    if run.returncode:
        raise RuntimeError(run.stderr)
    result = {}
    for line in run.stdout.splitlines():
        part, language, key, value = json.loads(line)
        result.setdefault(part, {}).setdefault(language, {})[key] = value
    for path in (root / 'packages/model-hotloader/mmd_hotloader/resource/localization').glob('*/mmdhl.properties'):
        table = {}
        for number, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            key, value = line.split('=', 1)
            key, value = key.strip(), value.strip()
            if key in table:
                raise RuntimeError(f'{path}:{number}: duplicate key {key}')
            table[key] = value
        result.setdefault('hotloader', {})[path.parent.name] = table
    return result


def validate(catalogs, allowed):
    problems = []
    for part, languages in catalogs.items():
        english = languages.get('en', {})
        if not english:
            problems.append(f'{part}: no English catalog')
            continue
        required = ('zh-cn', *LANGUAGES[1:]) if part == 'hotloader' else LANGUAGES
        for language in required:
            if language not in languages:
                problems.append(f'{part}: missing language {language}')
        for language, table in languages.items():
            if language == 'en':
                continue
            for key, source in english.items():
                where = f'{part}/{language}/{key}'
                translated = table.get(key)
                if not translated or not translated.strip():
                    problems.append(f'{where}: missing or blank translation')
                    continue
                if ('\ufffd' in translated and '\ufffd' not in source) or '\0' in translated:
                    problems.append(f'{where}: invalid character')
                if sorted(PLACEHOLDER.findall(source)) != sorted(PLACEHOLDER.findall(translated)):
                    problems.append(f'{where}: changed interpolation placeholders')
                # Only motion's printf templates use these conversions; other add-ons use named placeholders.
                if part == 'motion' and FORMAT.search(source):
                    wanted = [s for s in FORMAT.findall(source) if s != '%%']
                    got = [s for s in FORMAT.findall(translated) if s != '%%']
                    if wanted != got:
                        problems.append(f'{where}: changed printf conversions')
                if translated == source and allowed.get(part, {}).get(language, {}).get(key) != source:
                    problems.append(f'{where}: unreviewed English fallback')
            for key in table.keys() - english.keys():
                problems.append(f'{part}/{language}/{key}: not in the English catalog')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, help='write the audited catalogs and counts as JSON')
    args = parser.parse_args()
    catalogs = read_catalogs()
    allowed = json.loads((REPO / 'tools/addon_i18n_unchanged.json').read_text(encoding='utf-8'))
    problems = validate(catalogs, allowed)
    counts = {part: {language: len(table) for language, table in languages.items()}
              for part, languages in catalogs.items()}
    for part, languages in counts.items():
        print(part + ': ' + ', '.join(f'{code} {count}' for code, count in sorted(languages.items())))
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps({'counts': counts, 'problems': problems, 'catalogs': catalogs},
                                      ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for problem in problems:
        print(problem)
    print(f'{len(problems)} problems; real language-selection assertions passed')
    return bool(problems)


if __name__ == '__main__':
    raise SystemExit(main())
