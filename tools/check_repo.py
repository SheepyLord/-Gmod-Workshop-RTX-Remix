"""Check the repo's documentation conventions; print every problem and exit 1 if any.

Rules (AGENTS.md explains why):
1. Every script (.ps1 .psm1 .py .bat .cmd .lua .sh) has '<script file name>.md' beside it.
2. Every folder with a CMakeLists.txt (except the repo root) has a README.md naming every
   C/C++ source file below it; sub-folders with their own CMakeLists.txt are their own module.
3. Relative links in Markdown files point at files or folders that exist.
4. CHANGELOG.md has an '## [Unreleased]' section.
5. docs/COMPONENTS.md mentions every folder directly under loader/ and tools/.
6. CLAUDE.md imports AGENTS.md.
"""

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import unquote

SCRIPT_EXTS = {'.ps1', '.psm1', '.py', '.bat', '.cmd', '.lua', '.sh'}
SOURCE_EXTS = {'.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.inl', '.asm', '.def', '.rc', '.in'}
SKIP_DIRS = {'.git', 'out', 'build', '__pycache__', 'third_party', '.vs', '.venv', 'venv', 'node_modules'}
COMPONENT_ROOTS = ('loader', 'tools')

LINK_RE = re.compile(r'\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
FENCE_RE = re.compile(r'^(```|~~~).*?^\1', re.S | re.M)
INLINE_CODE_RE = re.compile(r'`[^`\n]*`')


def _files(root):
    stack = [root]
    while stack:
        current = stack.pop()
        for entry in sorted(current.iterdir()):
            if entry.is_dir():
                if entry.name not in SKIP_DIRS:
                    stack.append(entry)
            else:
                yield entry


def _rel(path, root):
    return path.relative_to(root).as_posix()


def check_script_docs(root, files):
    return [f'{_rel(f, root)}: missing {f.name}.md beside it'
            for f in files if f.suffix.lower() in SCRIPT_EXTS and not f.with_name(f.name + '.md').exists()]


def check_module_readmes(root, files):
    problems = []
    modules = sorted({f.parent for f in files if f.name == 'CMakeLists.txt' and f.parent != root})
    for module in modules:
        sources = [f for f in files if f.suffix.lower() in SOURCE_EXTS and module in f.parents
                   and not any(m != module and module in m.parents and m in f.parents for m in modules)]
        readme = module / 'README.md'
        if not readme.exists():
            problems.append(f'{_rel(module, root)}/: module folder has no README.md')
            continue
        text = readme.read_text(encoding='utf-8')
        for src in sources:
            if src.name not in text:
                problems.append(f'{_rel(readme, root)}: does not mention {_rel(src, module)}')
    return problems


def check_markdown_links(root, files):
    problems = []
    for md in (f for f in files if f.suffix.lower() == '.md'):
        text = INLINE_CODE_RE.sub('', FENCE_RE.sub('', md.read_text(encoding='utf-8')))
        for target in LINK_RE.findall(text):
            if re.match(r'^[a-z][a-z0-9+.-]*:', target, re.I) or target.startswith('#'):
                continue  # URL, mailto: or in-page anchor
            path = unquote(target.split('#', 1)[0].split('?', 1)[0])
            if not path:
                continue
            resolved = (root / path.lstrip('/')) if path.startswith('/') else (md.parent / path)
            if not resolved.exists():
                problems.append(f'{_rel(md, root)}: broken link -> {target}')
    return problems


def check_changelog(root):
    changelog = root / 'CHANGELOG.md'
    if not changelog.exists():
        return ['CHANGELOG.md is missing']
    if not re.search(r'^## \[Unreleased\]', changelog.read_text(encoding='utf-8'), re.M):
        return ['CHANGELOG.md has no "## [Unreleased]" section']
    return []


def check_components(root):
    components = root / 'docs' / 'COMPONENTS.md'
    if not components.exists():
        return ['docs/COMPONENTS.md is missing']
    text = components.read_text(encoding='utf-8')
    problems = []
    for top in COMPONENT_ROOTS:
        base = root / top
        if not base.is_dir():
            continue
        for child in sorted(p for p in base.iterdir() if p.is_dir() and p.name not in SKIP_DIRS):
            if f'{top}/{child.name}' not in text:
                problems.append(f'docs/COMPONENTS.md does not mention {top}/{child.name}')
    return problems


def check_claude_md(root):
    claude = root / 'CLAUDE.md'
    if not (root / 'AGENTS.md').exists():
        return ['AGENTS.md is missing']
    if not claude.exists() or '@AGENTS.md' not in claude.read_text(encoding='utf-8'):
        return ['CLAUDE.md must exist and import @AGENTS.md']
    return []


def check(root):
    root = Path(root).resolve()
    files = list(_files(root))
    return (check_script_docs(root, files) + check_module_readmes(root, files) + check_markdown_links(root, files)
            + check_changelog(root) + check_components(root) + check_claude_md(root))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--root', default=Path(__file__).resolve().parent.parent, help='repo root (default: this repo)')
    a = ap.parse_args(argv)
    problems = check(a.root)
    for problem in problems:
        print(problem)
    print(f'{len(problems)} problem(s)' if problems else 'repo conventions OK')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
