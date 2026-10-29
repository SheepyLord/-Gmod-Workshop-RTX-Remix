# publish_workshop.py

Keeps the project's Workshop item, 3829070317, up to date
([ADR 0016](../docs/decisions/0016-one-workshop-item-kept-current.md)). It builds the combined RTX
package from the inputs in [`workshop.json`](workshop.json), and uploads it with GMod's
`gmpublish.exe` when its content changed.

Its git hooks run it in the background, so that:
- a commit or a merge on `main` updates the item;
- a push of `main` updates GitHub and the item.

```powershell
python tools\publish_workshop.py --install-hooks     # once per clone: the hooks below
python tools\publish_workshop.py                     # publish now (skips if nothing changed)
python tools\publish_workshop.py --dry-run           # build and compare, upload nothing
python tools\publish_workshop.py --force             # build and upload even if unchanged
python tools\publish_workshop.py --uninstall-hooks   # remove this script's hooks
python tools\publish_workshop.py --install-source-hooks <add-on repo> [--any-branch]  # a part's source repository
```

## `workshop.json`

| Key | What |
|---|---|
| `item` | The Workshop item id that is updated |
| `package` | The combined package's `id` and `name`, and the Workshop `title`, `type`, `tags` and `description` written into the archive |
| `parts` | The packages that go in, in order. Either `{"package": "<.gma or package folder>"}`, used as it is, or `{"build": "package_fixes"\|"package_runtime"\|"package_content", "args": [...]}`, built afresh by that packager with those arguments |
| `gmpublish` | The `gmpublish.exe` that uploads. It runs from its game root, which must hold `steam_appid.txt` |

Today's parts are:
- **the runtime**, pinned as `out\packages\i18n\runtime-b5.gma`: runtime B with the classic install's
  settings as one low defaults layer ([ADR 0021](../docs/decisions/0021-remix-defaults-in-one-low-layer.md)),
  and a `d3d9.dll` with translated menus from the fork branch `claude/remix-i18n`
  ([RESEARCH.md](../docs/RESEARCH.md) section 25);
- **the RTX fixes**, rebuilt from the fixes repository with the classic install's modules and the debug
  module;
- **Emissives**, the classic install's Remix mod for HL2's fluorescent lights, pinned as
  `out\packages\round3\emissives.gma` ([ADR 0023](../docs/decisions/0023-content-packages-and-modern-house-item.md));
- **Remove_halo**, the user's one-line add-on (`halo.Add` does nothing), rebuilt from its folder
  `H:\BACKUP_20260815\Modding\ipg\Remove_halo` by [`package_content.py`](package_content.py.md) at
  every publish, so an edit there reaches the item at the next commit or push of `main`;
- **the user's five add-ons**, each rebuilt from its source at every publish
  ([ADR 0024](../docs/decisions/0024-bundled-addons-and-module-dependencies.md)):
  - Model Hotloader: its add-on and six natives from the classic install, its runtime loaded before
    both modules;
  - Advanced Material Editor: from its working copy, without its test textures, plus its RTX bridge
    module from the classic install;
  - Advanced Bodygroup Tool, Procedural Bodygroup Destruction and the Character Motion Importer: from
    their working copies.

The fixes part takes its modules from the classic install too, so a module rebuilt and installed
there (as the visibility-tuned `gmcl_RTXFixesBinary_win64.dll` was) ships with the next publish.

The Modern House RTX package is a separate test item (3829275998), uploaded by hand with
`gmpublish update`, not by this script.

## What a run does

1. **Uncommitted changes.** It refuses when the packaging inputs in this repository have uncommitted
   changes, which would otherwise go into the item: `companion/`, the four packagers, `gmapack.py`
   and `workshop.json`. `--dry-run` and `--allow-dirty` skip this check.
2. **Lock.** Its state lives in the **main checkout's** `out\workshop`, whichever worktree runs it, so
   every worktree shares one record of what the item holds. It takes `out\workshop\publish.lock`
   there, so only one publish runs at a time. It waits up to
   two hours for a running publish, and takes over a lock whose owner is gone.
3. **Fingerprint.** It computes a fingerprint of everything that can change the item:
   - this repository's packaging inputs in `HEAD`;
   - `workshop.json`;
   - each part's paths: a git repository by its commit and changed files, a folder by each file's
     name, size and time, a file by its size and time.

   If the fingerprint matches the last upload's, it stops: **unchanged inputs**. This is the usual
   result of a commit that touches only docs or loader code; the item does not contain `winmm.dll`.
4. **Build.** It builds the parts and combines them with
   [`package_workshop.py`](package_workshop.py.md) into
   `out\workshop\<id>-<version>.gma`, keeping only the newest archive (about 1.4 GB). The version is
   `0.0.0-dev.<UTC time>+<fingerprint prefix>`.
5. **Digest.** If the build's content digest matches the last upload's, it uploads nothing:
   **unchanged content**. It records the new fingerprint, so the next run stops at step 3.
6. **Upload.** It runs `gmpublish update -id <item> -addon <archive> -changes "<version> from <commit>
   (<reason>)"`. Steam must be running and logged in to the item's owner.
7. **Record.** It writes `out\workshop\published.json`: item, fingerprint, digest, version, the
   archive's SHA-256, commit, reason and time. `build.json` records the last build, uploaded or not.

## Hooks (`--install-hooks`)

They go in the common `.git\hooks`, shared by every worktree. Each one is marked
`# nl-workshop-hook`; a hook without that marker is never replaced unless `--force-hooks` is given.
`--uninstall-hooks` removes only marked hooks.

| Hook | When it publishes |
|---|---|
| `post-commit` | after a commit, when the branch is `main` |
| `post-merge` | after a merge or pull, when the branch is `main` |
| `pre-push` | when `refs/heads/main` is pushed |

**Hooks in the parts' source repositories** (`--install-source-hooks REPO`, repeatable; ADR 0024):
`post-commit` and `post-merge` in that repository run this checkout's script by its absolute path, so
an update there rebuilds the parts and uploads if the item's content changed.
- They fire on that repository's `main`, or on any branch with `--any-branch`.
- Installed (2026-10-29) in:
  - the material editor's, the bodygroup destruction's and the motion importer's repositories (`main`);
  - the fixes fork and Model Hotloader's repository (any branch): their builds reach the classic
    install from feature-branch worktrees.
- `--uninstall-source-hooks REPO` removes them. They carry the same marker, and an unmarked hook is
  never replaced without `--force-hooks`.
- **Git's hook environment is ignored.** Git runs a hook with the hooked repository in `GIT_DIR`,
  `GIT_INDEX_FILE` and the like. The script removes those variables (`GIT_LOCAL_ENV`, the names `git
  rev-parse --local-env-vars` lists) before any git call, so its git calls read this repository.
  - Before round 6 they read the source repository instead. Each such run saw this repository's
    packaging inputs as untracked, refused ("uncommitted changes in the packaging inputs"), and left
    its log in the source repository's `out\workshop\logs`.
  - So until then no source-repository commit had updated the item.

Each hook runs `publish_workshop.py --background --reason "<what> <commit>"`.
- The background run is detached, so the commit, merge or push returns at once.
- Its output goes to `out\workshop\logs\publish-<time>-<pid>.log`.
- A run that fails, for example because Steam is not running, changes nothing. The next commit,
  merge or push of `main` tries again.
- Commits on other branches publish nothing.

## Side effects and exit codes

- **Outward-facing:** it updates the Workshop item. AGENTS.md rule 5 allows that for this item
  without asking (the user's instruction, 2026-10-28). It never changes the item's visibility,
  title or description; those stay on the item's page.
- **Writes:** `out\workshop\` (the archive, state files, logs, a scratch build folder), the
  packagers' own scratch in `out\tmp`, and the hooks.
- **Exit codes:** 0 on success or when there is nothing to do (the JSON result says which:
  `unchanged-inputs`, `unchanged-content`, `dry-run` or `uploaded`). 1 on a refusal or failure, with
  the reason on stderr.

Tests: [`tests/test_publish_workshop.py`](tests/test_publish_workshop.py.md). They replace the upload
step and never run `gmpublish`.
