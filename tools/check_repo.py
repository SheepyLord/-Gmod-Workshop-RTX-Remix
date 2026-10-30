"""Check the repo's documentation conventions; print every problem and exit 1 if any.

Rules (AGENTS.md explains why):
1. Every script (.ps1 .psm1 .py .bat .cmd .lua .sh) has '<script file name>.md' beside it.
2. Every folder with a CMakeLists.txt (except the repo root) has a README.md naming every
   C/C++ source file below it; sub-folders with their own CMakeLists.txt are their own module.
3. Relative links in Markdown files point at files or folders that exist.
4. CHANGELOG.md has an '## [Unreleased]' section.
5. docs/COMPONENTS.md mentions every folder directly under loader/ and tools/.
6. CLAUDE.md imports AGENTS.md.
7. runtime/base.json "packaged" matches runtime/ and packages/runtime: the stored d3d9.dll is what
   runtime/build_runtime.ps1 builds from this repository.
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

SCRIPT_EXTS = {'.ps1', '.psm1', '.py', '.bat', '.cmd', '.lua', '.sh'}
SOURCE_EXTS = {'.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.inl', '.asm', '.def', '.rc', '.in'}
SKIP_DIRS = {'.git', 'out', 'build', '__pycache__', 'third_party', '.vs', '.venv', 'venv', 'node_modules'}
# Top-level folders of vendored content, kept byte for byte (ADR 0033): the RTX package's inputs, whose
# add-ons bring their own scripts and READMEs.
SKIP_TOP = {'packages'}
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
                if entry.name not in SKIP_DIRS and not (current == root and entry.name in SKIP_TOP):
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


def check_runtime_record(root):
    """runtime/base.json "packaged" names the d3d9.dll packages/runtime holds and what it was built from:
    the fork's commit, the submodule settings, the clones and every patch file's SHA-256. While runtime/
    differs from that record, the stored DLL is not what runtime/ builds (R3-014)."""
    base_path = root / 'runtime' / 'base.json'
    if not base_path.is_file():
        return []
    base = json.loads(base_path.read_text(encoding='utf-8'))
    record = base.get('packaged') or {}

    def settings(table):  # what builds: everything but the explanations
        return {k: {kk: vv for kk, vv in v.items() if kk != 'why'} for k, v in (table or {}).items()}

    files = {p.relative_to(root / 'runtime').as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for folder in ('patches', 'submodules') for p in sorted((root / 'runtime' / folder).glob('*.patch'))}
    now = {'commit': base.get('commit'), 'submodules': settings(base.get('submodules')), 'clones': settings(base.get('clones')),
           'files': files}
    built = {'commit': record.get('commit'), 'submodules': settings(record.get('submodules')),
             'clones': settings(record.get('clones')), 'files': record.get('files')}
    problems = [f'runtime/: the {key} differ from what the stored d3d9.dll was built from (runtime/base.json "packaged"); '
                'run runtime/build_runtime.ps1 to build and store it again' for key in now if now[key] != built[key]]
    index = root / 'packages' / 'runtime' / 'files.json'
    if index.is_file():
        entry = json.loads(index.read_text(encoding='utf-8'))['files'].get('files/d3d9.dll') or {}
        if entry.get('sha256') != record.get('d3d9.dll'):
            problems.append('packages/runtime/files/d3d9.dll is not the d3d9.dll runtime/base.json "packaged" records')
    return problems


def check(root):
    root = Path(root).resolve()
    files = list(_files(root))
    return (check_script_docs(root, files) + check_module_readmes(root, files) + check_markdown_links(root, files)
            + check_changelog(root) + check_components(root) + check_claude_md(root) + check_runtime_record(root))


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
