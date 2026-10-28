"""Minimal reader for Valve's text KeyValues format (.vdf / .acf files)."""

import sys

__all__ = ['loads', 'load']


def _tokens(text):
    """Yield string tokens and the structural tokens '{' and '}'."""
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif text.startswith('//', i):
            end = text.find('\n', i)
            i = n if end < 0 else end + 1
        elif c in '{}':
            yield c, False
            i += 1
        elif c == '"':
            i += 1
            out = []
            while i < n and text[i] != '"':
                if text[i] == '\\' and i + 1 < n:
                    i += 1
                    out.append({'n': '\n', 't': '\t', '\\': '\\', '"': '"'}.get(text[i], '\\' + text[i]))
                else:
                    out.append(text[i])
                i += 1
            i += 1  # closing quote (tolerates a missing one at end of input)
            yield ''.join(out), True
        else:
            start = i
            while i < n and not text[i].isspace() and text[i] not in '{}"':
                i += 1
            yield text[start:i], False


def loads(text):
    """Parse KeyValues text into nested dicts of str -> (str | dict).

    A later duplicate key replaces an earlier one. Platform conditionals such as
    ``[$WIN32]`` after a value are skipped, not evaluated.
    """
    root = {}
    stack = [root]
    key = None
    for tok, quoted in _tokens(text):
        if not quoted and tok == '{':
            if key is None:
                raise ValueError('"{" without a key')
            child = {}
            stack[-1][key] = child
            stack.append(child)
            key = None
        elif not quoted and tok == '}':
            if len(stack) == 1:
                raise ValueError('unbalanced "}"')
            stack.pop()
            key = None
        elif not quoted and tok.startswith(('[$', '[!$')):
            continue
        elif key is None:
            key = tok
        else:
            stack[-1][key] = tok
            key = None
    if len(stack) != 1:
        raise ValueError('unterminated "{" block')
    return root


def load(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        return loads(fh.read())


if __name__ == '__main__':
    import json
    for arg in sys.argv[1:]:
        print(json.dumps(load(arg), indent=1))
