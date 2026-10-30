# check_repo.py

Enforces the repo's documentation conventions so they cannot drift. Prints one line per problem and
exits 1 if there is any; [`test.ps1`](test.ps1.md) runs it first.

| Rule | Why |
|---|---|
| Every script (`.ps1 .psm1 .py .bat .cmd .lua .sh`) has `<script file name>.md` beside it | Agents and humans learn what a script does without reading it |
| Every folder with a `CMakeLists.txt` (except the root) has a `README.md` naming each C/C++ source file below it | Same, for native code; sub-folders with their own `CMakeLists.txt` are separate modules |
| Relative Markdown links resolve | Docs are navigated by links; stale links mislead |
| `CHANGELOG.md` has `## [Unreleased]` | Every notable change lands there first |
| [`docs/COMPONENTS.md`](../docs/COMPONENTS.md) mentions every folder under `loader/` and `tools/` | The component map stays complete |
| `CLAUDE.md` imports `@AGENTS.md` | One source of agent instructions |
| `runtime/base.json` `packaged` matches `runtime/` (the commit, `submodules`, `clones` and every `patches/*.patch` and `submodules/*.patch` SHA-256; the `why` texts aside) and `packages/runtime`'s `files/d3d9.dll` SHA-256 | The stored runtime is what [`runtime/build_runtime.ps1`](../runtime/build_runtime.ps1.md) builds from this repository; a patch changed without a new build fails here (R3-014, [ADR 0034](../docs/decisions/0034-the-runtimes-build-inputs-recorded.md)). Skipped when there is no `runtime/base.json` |

Skipped folders: `.git`, `out`, `build`, `__pycache__`, `third_party`, `.vs`, virtual environments, the
top-level `packages` (the RTX package's vendored inputs, whose add-ons bring their own scripts and
READMEs, [ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)), and any folder
with its own `.git`: another checkout, such as a worktree the Claude app keeps in `.claude/worktrees`.
Links inside code blocks and inline code are not checked.

## Usage

```powershell
python tools\check_repo.py                # this repo
python tools\check_repo.py --root D:\x    # another checkout
```

Tests: [`tests/test_check_repo.py`](tests/test_check_repo.py.md).
