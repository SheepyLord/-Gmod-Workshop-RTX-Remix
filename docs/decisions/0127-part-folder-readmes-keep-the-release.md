# 0127: The part folders' own READMEs do not end the release hold

- Status: Accepted 2026-11-06 (after R20; amends the release hold that review R19, M1, added to the
  development path of [ADR 0108](0108-releases-built-on-github-by-hand-development-built-here.md):
  steps 1 and 3a of [`tools/publish_workshop.py.md`](../../tools/publish_workshop.py.md))
- Context: while adding [ADR 0126](0126-a-record-of-what-this-repositorys-modules-were-built-from.md),
  a side session found that its three README edits under `packages/` would have replaced the release on
  the Workshop item, and held them back (commit `316e2db` on branch `claude/heuristic-yalow-28cab7`)

## Context

Since review R19 (M1), a hook run on `main` uploads nothing while Workshop item 3829070317 holds a
release built on GitHub (`out/workshop/published.json` with `source: github`) and `HEAD` has the release
commit's packaging inputs: `git diff --quiet <commit_sha> HEAD -- <REPO_INPUTS>` finds no difference and
no packaging input has an uncommitted change. A build here would only put the binaries stored in
`packages/` where the release's GitHub-built ones are ([ADR 0106](0106-the-rtx-package-built-on-github.md)).

`REPO_INPUTS` names `packages/` as a whole. So a commit that only edited the notes about the parts,
`packages/README.md` or a part folder's `README.md`, ended the hold: the next commit, merge or push of
`main` built the package here and uploaded it over the release, a download of about 1.8 GB for every
subscriber that also swaps the release's binaries for the stored ones.

Those READMEs are not in the package:

- `tools/inputs.py` keeps the name `README.md` for the part folder itself (`PART_DOCS`, with
  `files.json`, `LICENSE`, `LICENSE.txt` and `COPYING`): an import refuses a part file of that name,
  `verify` passes over it, and `unpack` never writes one to `out/inputs/<part>/`, where the packagers read
  the parts.
- No part in `tools/workshop.json` names one or a folder that holds one. What it takes from `packages/`
  directly is part licences (`packages/<part>/LICENSE`) and folders below `licenses/` (`--add-to-addon`).
- No packager names one: `package_fixes.py` reads only the companion catalog's README
  (`companion/i18n/addons/README.md`), and `companion_i18n.py` walks `packages/` for `.lua` files only.

## Decision

1. **Not packaging inputs for the hold.** The comparisons that decide whether the release stays leave
   out `packages/README.md` and `packages/<part>/README.md`: the pathspecs `:(exclude)packages/README.md`
   and `:(exclude,glob)packages/*/README.md` (`NOT_IN_PACKAGE`) follow `REPO_INPUTS` (`SHIPPED_INPUTS`)
   in `same_inputs()`, the committed comparison, and in the check for uncommitted inputs. That check is
   also step 1's refusal, whose reason ("would go into the item") does not hold for these files.
2. **Exactly those files.** Git's `glob` magic keeps `*` within one folder, so a `README.md` deeper in a
   part, which add-ons ship, still counts. So do a part's `LICENSE`, `COPYING`, `files.json` and
   `licenses/` (packagers ship licences with `--add-to-addon`; the fixes part bundles
   `licenses/oversized-skinning`, READMEs included) and every other file at a part's top. The match is
   case-sensitive, also where `core.ignorecase` is true: a part's `readme.md`, which `inputs.py` allows,
   counts. In this repository the exclusions leave out five tracked files; without `glob` they would
   leave out sixteen.
3. **Git's own pathspec rules.** The script removes `GIT_LITERAL_PATHSPECS`, `GIT_GLOB_PATHSPECS`,
   `GIT_NOGLOB_PATHSPECS` and `GIT_ICASE_PATHSPECS` from its environment, as it removes git's
   repository-local variables: with literal pathspecs the exclusions would name no file and the READMEs
   would end the hold again; with case-insensitive ones a part's `readme.md` would be left out too.
4. **The fingerprint is unchanged.** It still covers the whole `packages/` tree and its uncommitted
   changes. It decides only whether a run looks further, and after a change to the READMEs alone the next
   step uploads nothing either way: the hold while the item holds a release, the digest comparison for a
   development build, whose content is the same. Every recorded fingerprint also stays valid.
5. **A test keeps it true.** `test_no_packager_reads_a_part_folders_readme` fails when a part's index
   lists a `README.md` at its root, when `workshop.json` names one or a whole part folder, when a packager
   names one, or when the exclusions leave out any other tracked file.

## Consequences

- Notes about the parts can land on `main` without replacing a release on the item; once this is on
  `main`, commit `316e2db` no longer has to wait for a change that publishes anyway.
- A part that one day ships its folder's README (`--add-to-addon` of `packages/<part>/README.md`, say)
  fails that test; it must then move the file or supersede this decision.
- While the item holds a development build, a change to a part folder's README alone still costs one
  local build in the background (the fingerprint changed), which finds the same content and uploads
  nothing.
- GitHub's package workflow and `--from-ci` are unchanged.
