"""Translations of the Lua companion (the RTX Remix spawn-menu tab, the guide, the update notice):
gettext files in companion/i18n for people to review and edit, built into the add-on when the RTX
package is made.

  update  extracts the text the companion marks with L("...") or N("...") into companion/i18n/
          nativeloader.pot, and merges it into every <language>.po (translations kept, new text
          added untranslated, text no longer used dropped)
  check   checks every .po: syntax, text the companion has, and the same printf conversions (%s,
          %d) as the English
  build   checks, then writes the Lua table the add-on reads (lua/nativeloader/i18n_data.lua);
          package_fixes.py runs it for the package

Usage: python tools/companion_i18n.py update|check|build [--out FILE]
See companion_i18n.py.md for the format and the exit codes."""

import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA_ROOT = os.path.join(REPO, 'companion', 'nativeloader', 'lua')
I18N = os.path.join(REPO, 'companion', 'i18n')
POT = 'nativeloader.pot'
# GMod's language codes (gmod_language), as the companion looks them up.
LANGUAGES = ('zh-CN', 'zh-TW', 'ja', 'ko', 'fr', 'ru')
# L("text"), L"text", N("text"), N"text": a Lua string literal in double quotes.
MARKED = re.compile(r'\b([LN])\s*(?:\(\s*)?"((?:[^"\\\n]|\\.)*)"')
LUA_ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'", 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v'}
CONVERSION = re.compile(r'%[-+ #0]*\d*(?:\.\d+)?[sdifgxXqc%]')


class I18nError(Exception):
    pass


def lua_unescape(text, where):
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c != '\\':
            out.append(c)
            i += 1
            continue
        nxt = text[i + 1:i + 2]
        if nxt in LUA_ESCAPES:
            out.append(LUA_ESCAPES[nxt])
            i += 2
        elif nxt.isdigit():
            digits = re.match(r'\d{1,3}', text[i + 1:]).group(0)
            out.append(chr(int(digits)))
            i += 1 + len(digits)
        else:
            raise I18nError('%s: the escape \\%s is not one this tool reads' % (where, nxt))
    return ''.join(out)


def extract(root=LUA_ROOT):
    """Every marked text in the companion's Lua, in file order: [(text, ["file:line", ...])]."""
    found = {}
    for folder, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            if not name.endswith('.lua') or name == 'i18n_data.lua':
                continue
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, os.path.dirname(os.path.dirname(root))).replace('\\', '/')
            with open(path, encoding='utf-8') as fh:
                for number, line in enumerate(fh, 1):
                    if line.lstrip().startswith('--'):
                        continue  # a comment line (the headers name L and N too)
                    for match in MARKED.finditer(line):
                        text = lua_unescape(match.group(2), '%s:%d' % (rel, number))
                        if text:
                            found.setdefault(text, []).append('%s:%d' % (rel, number))
    return list(found.items())


# ---------------------------------------------------------------- PO files

def po_quote(text):
    escaped = text.replace('\\', '\\\\').replace('"', '\\"').replace('\t', '\\t').replace('\r', '\\r')
    if '\n' not in escaped:
        return '"%s"' % escaped
    parts = escaped.split('\n')
    lines = ['""'] + ['"%s\\n"' % p for p in parts[:-1]] + (['"%s"' % parts[-1]] if parts[-1] else [])
    return '\n'.join(lines)


def po_unquote(chunks, where):
    out = []
    for chunk in chunks:
        if len(chunk) < 2 or chunk[0] != '"' or chunk[-1] != '"':
            raise I18nError('%s: %s is not a quoted string' % (where, chunk))
        body, i = chunk[1:-1], 0
        escapes = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"'}
        while i < len(body):
            c = body[i]
            if c == '\\':
                nxt = body[i + 1:i + 2]
                if nxt not in escapes:
                    raise I18nError('%s: the escape \\%s is not allowed (\\n, \\t, \\\\ and \\" are)' % (where, nxt))
                out.append(escapes[nxt])
                i += 2
            elif c == '"':
                raise I18nError('%s: a quote inside a string must be written \\"' % where)
            else:
                out.append(c)
                i += 1
    return ''.join(out)


def read_po(path):
    """[{'msgid', 'msgstr', 'fuzzy', 'comments', 'line'}] of a PO file (the header entry included)."""
    entries, current, field = [], None, None
    with open(path, encoding='utf-8-sig') as fh:
        lines = fh.read().split('\n')

    def finish():
        if current and current.get('msgid') is not None:
            where = '%s:%d' % (path, current['line'])
            current['msgid'] = po_unquote(current.pop('msgid_chunks'), where)
            current['msgstr'] = po_unquote(current.pop('msgstr_chunks', ['""']), where)
            entries.append(current)

    for number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith('#~'):
            continue  # obsolete entries are dropped
        if line.startswith('#'):
            if current is not None and current.get('msgid') is not None:
                finish()
                current = None
            if current is None:
                current = {'comments': [], 'fuzzy': False, 'line': number}
            if line.startswith('#,') and 'fuzzy' in [flag.strip() for flag in line[2:].split(',')]:
                current['fuzzy'] = True
            current['comments'].append(raw)
            continue
        if line.startswith('msgid '):
            if current is not None and current.get('msgid') is not None:
                finish()
                current = None
            if current is None:
                current = {'comments': [], 'fuzzy': False, 'line': number}
            current['msgid'] = True
            current['msgid_chunks'] = [line[6:].strip()]
            field = 'msgid_chunks'
        elif line.startswith('msgstr '):
            if current is None or current.get('msgid') is None:
                raise I18nError('%s:%d: msgstr without msgid' % (path, number))
            current['msgstr_chunks'] = [line[7:].strip()]
            field = 'msgstr_chunks'
        elif line.startswith('"'):
            if current is None or field is None or field not in current:
                raise I18nError('%s:%d: a string continues nothing' % (path, number))
            current[field].append(line)
        else:
            raise I18nError('%s:%d: not PO syntax (msgctxt and plural forms are not used here): %s' % (path, number, line))
    finish()
    return entries


def header(language):
    return ('msgid ""\nmsgstr ""\n"Project-Id-Version: GMod native loader companion\\n"\n'
            '"Language: %s\\n"\n"MIME-Version: 1.0\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n'
            '"Content-Transfer-Encoding: 8bit\\n"\n' % language)


def write_po(path, language, strings, translations):
    """`strings` [(msgid, refs)]; `translations` {msgid: (msgstr, fuzzy)}."""
    parts = [('# Translations of the GMod native loader companion (the RTX Remix tab, the guide).\n'
              '# Edit msgstr only; see companion/i18n/README.md. An empty msgstr shows the English.\n'
              if language else
              '# The English text of the GMod native loader companion. Generated by tools/companion_i18n.py update:\n'
              '# do not edit; the text is in companion/nativeloader/lua.\n') + header(language or 'en')]
    for msgid, refs in strings:
        msgstr, fuzzy = translations.get(msgid, ('', False))
        entry = ''.join('#: %s\n' % ref for ref in refs)
        if fuzzy:
            entry += '#, fuzzy\n'
        if CONVERSION.search(msgid):
            entry += '#, c-format\n'
        entry += 'msgid %s\nmsgstr %s\n' % (po_quote(msgid), po_quote(msgstr if language else ''))
        parts.append(entry)
    text = '\n'.join(parts)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)


def update(i18n=I18N, root=LUA_ROOT):
    strings = extract(root)
    os.makedirs(i18n, exist_ok=True)
    write_po(os.path.join(i18n, POT), None, strings, {})
    summary = {}
    for language in LANGUAGES:
        path = os.path.join(i18n, language + '.po')
        old = {e['msgid']: (e['msgstr'], e['fuzzy']) for e in read_po(path) if e['msgid']} if os.path.exists(path) else {}
        write_po(path, language, strings, old)
        used = {s for s, _ in strings}
        summary[language] = {'translated': sum(1 for s, _ in strings if old.get(s, ('', False))[0]),
                             'dropped': sorted(s for s, (msgstr, _) in old.items() if s not in used and msgstr)}
    return strings, summary


def check(i18n=I18N, root=LUA_ROOT):
    """{language: {msgid: msgstr}} of the usable translations. Raises I18nError naming file and line."""
    known = {s for s, _ in extract(root)}
    out, problems = {}, []
    for language in LANGUAGES:
        path = os.path.join(i18n, language + '.po')
        if not os.path.exists(path):
            problems.append('%s is missing (tools/companion_i18n.py update makes it)' % path)
            continue
        table = {}
        for entry in read_po(path):
            msgid, msgstr = entry['msgid'], entry['msgstr']
            where = '%s:%d' % (path, entry['line'])
            if not msgid:
                continue  # the header
            if msgid not in known:
                problems.append('%s: "%s" is not text the companion has (run update)' % (where, msgid[:60]))
                continue
            if not msgstr or entry['fuzzy']:
                continue
            # Only text the companion formats has conversions; elsewhere a "%" is just a percent sign.
            want, got = CONVERSION.findall(msgid), CONVERSION.findall(msgstr)
            if want and want != got:
                problems.append('%s: printf conversions %s must match the English %s' % (where, got, want))
                continue
            table[msgid] = msgstr
        out[language] = table
    if problems:
        raise I18nError('\n'.join(problems))
    return out


def lua_quote(text):
    out = []
    for c in text:
        if c == '\\':
            out.append('\\\\')
        elif c == '"':
            out.append('\\"')
        elif c == '\n':
            out.append('\\n')
        elif ord(c) < 32 or ord(c) == 127:
            out.append('\\%03d' % ord(c))
        else:
            out.append(c)
    return '"%s"' % ''.join(out)


def build_text(tables):
    lines = ['-- Generated by tools/companion_i18n.py build from companion/i18n/*.po when the package is made:',
             '-- do not edit. The companion reads it through nativeloader/i18n.lua.', 'return {']
    for language in LANGUAGES:
        lines.append('    [%s] = {' % lua_quote(language))
        for msgid in sorted(tables.get(language, {})):
            lines.append('        [%s] = %s,' % (lua_quote(msgid), lua_quote(tables[language][msgid])))
        lines.append('    },')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def build(out, i18n=I18N, root=LUA_ROOT):
    tables = check(i18n, root)
    text = build_text(tables)
    with open(out, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)
    return {language: len(table) for language, table in tables.items()}


def main(argv=None):
    ap = argparse.ArgumentParser(description='Translations of the Lua companion (companion/i18n).')
    ap.add_argument('command', choices=('update', 'check', 'build'))
    ap.add_argument('--out', help='build: the Lua file to write (lua/nativeloader/i18n_data.lua of the add-on)')
    args = ap.parse_args(argv)
    try:
        if args.command == 'update':
            strings, summary = update()
            print('%d texts in companion/i18n/%s' % (len(strings), POT))
            for language, info in summary.items():
                print('  %-6s %d of %d translated%s' % (language, info['translated'], len(strings),
                                                       ', %d translations of text no longer used dropped' % len(info['dropped'])
                                                       if info['dropped'] else ''))
        elif args.command == 'check':
            tables = check()
            for language, table in tables.items():
                print('  %-6s %d translations' % (language, len(table)))
        else:
            if not args.out:
                ap.error('build needs --out')
            for language, count in build(args.out).items():
                print('  %-6s %d translations' % (language, count))
    except (I18nError, OSError) as error:
        print('error: %s' % error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
