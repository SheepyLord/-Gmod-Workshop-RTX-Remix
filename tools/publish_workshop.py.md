# publish_workshop.py

Keeps the project's Workshop item, 3829070317, up to date
([ADR 0016](../docs/decisions/0016-one-workshop-item-kept-current.md)). **During development** it builds
the combined RTX package from this repository alone, as [`workshop.json`](workshop.json) lays it out
([ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)), and uploads it with
GMod's `gmpublish.exe` when its content changed; [`build_package.py`](build_package.py.md) is the same
build without the upload. **For a release** a person starts GitHub's package workflow, which builds the
package with every native binary and a hash report ([ADR 0106](../docs/decisions/0106-the-rtx-package-built-on-github.md));
`--from-ci` then uploads exactly that run's `.gma`
([ADR 0108](../docs/decisions/0108-releases-built-on-github-by-hand-development-built-here.md)).

Its git hooks run it in the background, so that:
- a commit or a merge on `main` updates the item;
- a push of `main` updates GitHub (with the Git LFS files) and the item.

```powershell
python tools\publish_workshop.py --install-hooks     # once per clone: the hooks below
python tools\publish_workshop.py                     # publish now (skips if nothing changed)
python tools\publish_workshop.py --dry-run           # build and compare, upload nothing
python tools\publish_workshop.py --force             # build and upload even if unchanged
python tools\publish_workshop.py --commit <sha>      # publish that commit, from the checkout that has it out
python tools\publish_workshop.py --from-ci --commit <sha> --dry-run   # a release: download and check its run's package
python tools\publish_workshop.py --from-ci --commit <sha>             # a release: upload that run's package
python tools\publish_workshop.py --uninstall-hooks   # remove this script's hooks
python tools\publish_workshop.py --uninstall-source-hooks <add-on repo>  # remove ADR 0024's hooks there
```

## `workshop.json`

| Key | What |
|---|---|
| `item` | The Workshop item id that is updated |
| `package` | The combined package's `id` and `name`, and the Workshop `title`, `type`, `tags` and `description` written into the archive |
| `parts` | The packages that go in, in order. Either `{"package": "<.gma or package folder>"}`, used as it is, or `{"build": "package_fixes"\|"package_runtime"\|"package_content"\|"package_reshade", "args": [...]}`, built afresh by that packager with those arguments. Relative paths are relative to this repository; every part reads `out/inputs/<part>/...`, unpacked from `packages/<part>/` |
| `gmpublish` | The `gmpublish.exe` that uploads. It runs from its game root, which must hold `steam_appid.txt` |

Today's parts, each from its folder in [`packages/`](../packages/README.md):
- **the runtime**, built by [`package_runtime.py`](package_runtime.py.md) from `packages/runtime`: the
  fork's `d3d9.dll` ([runtime/](../runtime/README.md): translated menus, [RESEARCH.md](../docs/RESEARCH.md)
  section 25; the real Moon, the night sky image and eclipses, section 29), NVIDIA's DLLs, the sky's
  textures in `atmosphere\`, the classic install's settings as one low defaults layer
  ([ADR 0021](../docs/decisions/0021-remix-defaults-in-one-low-layer.md)) and a second dxvk layer that
  gives shader compilation every hardware thread but two ([ADR 0032](../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md));
- **ReShade 6.8.0** for RTX sessions, built by [`package_reshade.py`](package_reshade.py.md) from the
  official setup ([ADR 0028](../docs/decisions/0028-reshade-in-rtx-sessions.md));
- **the RTX fixes**, built by [`package_fixes.py`](package_fixes.py.md) from their files and binary
  modules, with the companion and its translations from this repository's `companion/`;
- **Emissives**, the classic install's Remix mod for HL2's fluorescent lights, as packaged in round 3
  ([ADR 0023](../docs/decisions/0023-content-packages-and-modern-house-item.md));
- **Remove_halo**, the user's one-line add-on (`halo.Add` does nothing), and **the user's five
  add-ons** ([ADR 0024](../docs/decisions/0024-bundled-addons-and-module-dependencies.md)), built by
  [`package_content.py`](package_content.py.md): Model Hotloader with its natives and its runtime
  loaded before both modules, Advanced Material Editor (without its test textures) with its RTX
  bridge module, Advanced Bodygroup Tool, Procedural Bodygroup Destruction and the Character Motion
  Importer.

A change to any of them reaches the item through an import into `packages/` and a commit here
(packages/README.md, "Updating a part"); their own repositories no longer reach it.

The Modern House RTX package is a separate test item (3829275998), uploaded by hand with
`gmpublish update`, not by this script.

## What a `--from-ci` run does (a release; R16, ADR 0108)

A person has started the package workflow on GitHub for the commit (no push starts it).

1. **The run.** It looks up the package workflow's runs of the commit (`--commit`, default `HEAD`) with
   `gh api .../actions/workflows/package.yml/runs?head_sha=...` and waits, checking every minute, until
   the newest has finished (up to six hours). No run within five minutes is an error (exit 1): only a
   person starts the workflow, so nobody started it for that commit and there is no release to upload.
   A run that did not succeed, cancelled or failed, is an error too, and uploads nothing. Until review
   R19 both "no run" and "cancelled" ended with exit 0 (`no-run`, `cancelled`), from when every push
   started the workflow (ADR 0106).
2. **Lock and record.** The same lock and `out\workshop` state as below. If `published.json` already
   names that run, it stops (`unchanged`).
3. **Download and check.** First `gh api .../actions/runs/<id>/artifacts`: the run must still have both
   artifacts. Every artifact expires two days after its run (`ARTIFACT_DAYS`,
   [ADR 0113](../docs/decisions/0113-every-actions-artifact-expires-after-two-days.md)), and a newer
   package run deletes the older packages. An expired or missing one is an error (exit 1) that names it
   and says to start the workflow again; nothing is downloaded, and `out\workshop\ci` keeps the last
   download. Then `gh run download` of the artifacts `rtx-package-report` and `rtx-package` into
   `out\workshop\ci` (the folder is emptied first: only the newest download is kept). The `.gma`'s
   name, size and SHA-256 must be the report's, or it stops before uploading.
4. **Upload.** `gmpublish update` with that file; the change note names the version, the commit, the
   run's URL and the `.gma`'s SHA-256. `--dry-run` stops before this step.
5. **Record.** `published.json`: item, version, digest, the `.gma`'s size and SHA-256, commit (short SHA
   and subject) and `commit_sha` (the full SHA), `source: github`, the run's id and URL, the counts of
   compiled, fetched and `packages/` binaries, reason and time. It has no fingerprint: the hook runs
   that follow compare their commit with `commit_sha` instead (step 3a below).

Needs `gh` signed in with read access to this repository, and Steam (as below).

## What a run without `--from-ci` does

0. **Which checkout** (`--commit SHA`, what the hooks pass). The run belongs to the checkout that has
   that commit checked out: this one if its `HEAD` is the commit, else the first `git worktree list`
   names, whose own script it then runs (R3-004: a push of `main` from a worktree on another branch had
   built that worktree's package). If no checkout has the commit checked out, nothing is published
   (exit 1, with the reason in the log). The build then checks again that `HEAD` is that commit.
1. **Uncommitted changes.** It refuses when the packaging inputs in this repository (`REPO_INPUTS`)
   have uncommitted changes, which would otherwise go into the item: `companion/`, `packages/`,
   `tools/inputs.py`, the four packagers, `package_workshop.py`, `gmapack.py`, `companion_i18n.py`
   (it builds the shipped `i18n_data.lua`), `third_party/reshade`, `LICENSE` and
   `third_party/gmod/LICENSE` (shipped as notices), `.gitattributes` (it sets the bytes a checkout
   gives `/LICENSE` and the guard) and `workshop.json`. Before review R4 the four after `gmapack.py`
   were missing, and a change to them alone (`.gitattributes`, 2026-10-31) was never published.
   The part folders' own READMEs (`packages/README.md`, `packages/<part>/README.md`; see step 3a) do
   not count: they would not go into the item.
   `--dry-run` and `--allow-dirty` skip this check.
2. **Lock.** Its state lives in the **main checkout's** `out\workshop`, whichever worktree runs it, so
   every worktree shares one record of what the item holds. Only one publish runs at a time: it holds
   an exclusive Windows lock on the first byte of `out\workshop\publish.lock` through an open handle for
   the whole run. Windows lets go of it when the process ends, however it ends, so no lock is left
   behind and none is ever taken over (R3-005: a lock file holding a PID could be taken for stale in
   the moment between its creation and the PID's write). It waits up to two hours for a running
   publish. The file itself stays.
3. **Fingerprint.** It computes a fingerprint of everything that can change the item:
   - those packaging inputs in `HEAD` (their git tree, which for an LFS file is its pointer and so
     its content's oid) and any uncommitted change to them;
   - `workshop.json`;
   - any other path a part names (none does today; relative ones are relative to this repository): a
     git repository by its commit and changed files, a folder by each file's name, size and time, a
     file by its size and time. Paths under `out\inputs` are left out: they are derived from
     `packages/`, and their state depends on whether an unpack has run (counting it made the first run
     after a merge and every later run disagree, 2026-10-30).

   If the fingerprint matches the last upload's, it stops: **unchanged inputs**. This is the usual
   result of a commit that touches only docs or loader code; the item does not contain `winmm.dll`.
   The part folders' own READMEs count here, unlike in steps 1 and 3a: the fingerprint only decides
   whether the run looks further, and after a change to them alone the next steps upload nothing
   (3a while the item holds a release, 5 for a development build, whose content is the same).
3a. **A release on the item** (review R19, M1). When `published.json` holds a release built on GitHub
   (`source: github`, written by `--from-ci`) whose commit, `commit_sha`, has the packaging inputs `HEAD`
   has (`git diff --quiet <commit_sha> HEAD -- <SHIPPED_INPUTS>`: `REPO_INPUTS` and
   `':(exclude)packages/README.md' ':(exclude,glob)packages/*/README.md'`), with the configuration this run uses
   (`tools/workshop.json` of that commit), and no packaging input has an uncommitted change, it stops
   too: **unchanged inputs**. It records the fingerprint, so the next runs stop at step 3, and the
   release stays until an input changes; then the development build is uploaded as before (steps 4 to
   7). Without this, the first commit, merge or push of `main` after a release built the package here
   from the stored binaries, found a digest other than the release's (its binaries were built on
   GitHub) and uploaded that development build over the release. A record without `commit_sha` (one
   written before R19), a commit this clone does not have, and `--force` skip this step.

   **The part folders' own READMEs** ([ADR 0127](../docs/decisions/0127-part-folder-readmes-keep-the-release.md);
   `NOT_IN_PACKAGE`) are left out of both comparisons, committed and uncommitted. `packages/README.md`
   and each `packages/<part>/README.md` are about the parts, not in them: `tools/inputs.py` keeps that
   name for the part folder itself (`PART_DOCS`), so no part has a file there and `unpack` never writes
   one to `out\inputs`, and neither a packager nor `workshop.json` reads them. Until then a commit of
   only those ended the hold, and the next commit, merge or push of `main` uploaded a development build
   over the release. Git's glob magic keeps `*` in one folder, so a `README.md` deeper in a part, which
   ships with its add-on, still counts, as do a part's `LICENSE`, `COPYING`, `files.json` and
   `licenses/` (packagers ship them with `--add-to-addon`); the match is case-sensitive, so a part's
   `readme.md` counts too.
4. **Build.** It unpacks the `packages/` parts the config reads into `out\inputs\`
   ([`inputs.py`](inputs.py.md): every file checked against its index, its recorded time restored),
   builds the parts and combines them with [`package_workshop.py`](package_workshop.py.md) into
   `out\workshop\<id>-<version>.gma`, keeping only the newest archive (about 1.8 GB). The version is
   `0.0.0-dev.<UTC time>+<fingerprint prefix>`. The packagers check each part, and
   `package_workshop.py` the combined manifest, with `nlctl.exe` from this checkout's `out\build`
   (`win64-release`, else `win64-debug`), so that build must know the manifest. After a change that
   adds a manifest key or kind, build the loader in the main checkout (`tools\build.ps1 -Config
   Release`) before the merge into `main`: in round 8 (2026-10-29) the hooks' runs failed with "nlctl
   refuses the package: manifest: unknown key "reshade"" until it was rebuilt.
5. **Digest.** If the build's content digest matches the last upload's, it uploads nothing:
   **unchanged content**. It records the new fingerprint, so the next run stops at step 3.
6. **Upload.** It runs `gmpublish update -id <item> -addon <archive> -changes "<version> from <commit>
   (<reason>)"`. Steam must be running and logged in to the item's owner.
   If the reviewed publisher incorrectly rejects Steam's process-presence check, the guarded fallback
   below retries with an isolated copy. Real Steam initialization and authorization still run normally.
7. **Record.** It writes `out\workshop\published.json`: item, fingerprint, digest, version, the
   archive's SHA-256, commit, `commit_sha` (the full SHA), reason and time. `build.json` records the last
   build, uploaded or not.

### Stale Steam process detection

On 2026-10-30, Steam's `HKCU\Software\Valve\Steam\ActiveProcess` named an old PID even though the
client was running in the current user's session. The publisher's `SteamAPI_IsSteamRunning()` returned
false; both `SteamAPI_InitFlat()` and the publisher's exact-version API initialization succeeded. Its
early error therefore prevented a valid upload before Steam initialization was attempted.

The fallback is eligible only for the exact early message `Couldn't initialize Steam!` followed by
`Make sure it is running!`. Later API initialization, login, account ownership, network and upload
failures remain failures. It requires both complete file hashes and the expected machine-code window:

- `gmpublish.exe`: SHA-256 `fd999f4f90ff1b7e3e1f293574f90a3e18fa056b65a574901eb1f4f2be27107e`.
- `steam_api64.dll`: SHA-256 `eb17909a76668cf9ae0b92a618a34a50f6c73d3a6787cb4dd8ce36a8b10bfb75`.
- File offset `0x7595`: `75 0c` (`JNZ +0x0c`) becomes `eb 0c` (`JMP +0x0c`), past only the obsolete
  process-presence error. The next block still calls the original real Steam API initialization.

A bounded child process first performs real read-only `SteamAPI_InitFlat()` initialization for app
4000, using the hash-checked dependency copy. Failure refuses the retry. Raw probe diagnostics stay
captured, since Steam can print account identifiers. A successful probe permits the isolated publisher
copy under this checkout's `out/tmp/gmpublish-preflight-*`; the vendor's original UGC upload,
authentication, ownership and visibility behavior remain in place. The retry keeps the original game
working directory, item, archive and change notes. The temporary executable and DLL are removed when
the process exits; if the folder cannot be removed yet (the copy still held by Windows or a scanner),
it is left in `out/tmp` and logged, and the upload still counts: before review R4 that error escaped
after a successful upload, `published.json` was not written and the next hook run uploaded again.
Steam's originals, registry, settings and running processes are never changed.
Another vendor build fails closed until its exact code is reviewed and these guards are updated.
That review is the user's call ([ADR 0058](../docs/decisions/0058-gmpublish-preflight-fallback-recorded.md)):
when a GMod update changes `gmpublish.exe` or `steam_api64.dll` and the fallback refuses, report it to
the user (or ask them to restart Steam, which clears the stale process id) instead of pinning the new
hashes or offset yourself.

## Hooks (`--install-hooks`)

They go in the common `.git\hooks`, shared by every worktree. Each one is marked
`# nl-workshop-hook`; a hook without that marker is never replaced unless `--force-hooks` is given.
`--uninstall-hooks` removes only marked hooks.

`packages/` keeps its binaries in Git LFS, and these hooks take the place of the ones `git lfs
install` writes, so each runs Git LFS's step first.

| Hook | Git LFS's step | When it publishes |
|---|---|---|
| `post-commit` | `git lfs post-commit` | after a commit, when the branch is `main` |
| `post-merge` | `git lfs post-merge` | after a merge or pull, when the branch is `main` |
| `post-checkout` | `git lfs post-checkout` | never |
| `pre-push` | `git lfs pre-push`, which uploads the LFS files the push needs; without git-lfs on the path the push stops (exit 2) | when `refs/heads/main` is pushed |

`pre-push` reads the refs git gives it once and hands the same lines to Git LFS and to its own loop.
Without git-lfs the other hooks skip its step and go on. A push that deletes `main` publishes nothing.

Each hook runs `publish_workshop.py --background --commit <commit> --reason "<what> <commit>"`: for
`pre-push` the commit sent to `main`, which step 0 builds in the checkout that has it checked out.
- The background run is detached, so the commit, merge or push returns at once. It gets one hidden
  console (`CREATE_NO_WINDOW`) that every step it runs shares: started without a console, each step
  opened a window of its own, and Windows Terminal kept dozens of finished tabs (2026-10-31).
- Its output goes to `out\workshop\logs\publish-<time>-<pid>.log`.
- A run that fails, for example because Steam is not running, changes nothing. The next commit,
  merge or push of `main` tries again.
- Commits on other branches publish nothing.

**Git's hook environment is ignored.** Git runs a hook with the hooked repository in `GIT_DIR`,
`GIT_INDEX_FILE` and the like. The script removes those variables (`GIT_LOCAL_ENV`, the names `git
rev-parse --local-env-vars` lists) before any git call, so its git calls read this repository. It
also removes the ones that change how git reads pathspecs (`GIT_PATHSPEC_ENV`: `GIT_LITERAL_PATHSPECS`,
`GIT_GLOB_PATHSPECS`, `GIT_NOGLOB_PATHSPECS`, `GIT_ICASE_PATHSPECS`): step 3a's exclusions need git's
own rules. With literal pathspecs they would name no file, and a part folder's README would end the
hold again; with case-insensitive ones a part's `readme.md` would not count.

**The add-ons' repositories** carried hooks of this script until ADR 0033 (ADR 0024: their commits
rebuilt the parts and uploaded). They were removed on 2026-10-30, from the fixes fork, Model
Hotloader's, the material editor's, the bodygroup destruction's and the motion importer's
repositories. `--uninstall-source-hooks REPO` removes them from another clone; it removes only
`post-commit` and `post-merge` hooks that carry the marker.

## Side effects and exit codes

- **Outward-facing:** it updates the Workshop item. AGENTS.md rule 5 allows that for this item
  without asking (the user's instruction, 2026-10-28). It never changes the item's visibility,
  title or description; those stay on the item's page.
- **Writes:** `out\workshop\` (the archive, state files, logs, a scratch build folder), `out\inputs\`,
  the packagers' own scratch in `out\tmp`, and the hooks.
- **Exit codes:** 0 on success or when there is nothing to do (the JSON result says which:
  `unchanged-inputs`, `unchanged-content`, `dry-run` or `uploaded`; with `--from-ci`, `unchanged` for a
  run already uploaded). 1 on a refusal or failure, with the reason on stderr; with `--from-ci` that
  includes no run of the commit and a run that did not succeed.

Tests: [`tests/test_publish_workshop.py`](tests/test_publish_workshop.py.md). They replace the upload
step and never run `gmpublish`.
