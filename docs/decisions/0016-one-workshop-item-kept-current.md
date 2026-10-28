# 0016: One Workshop item carries the RTX package, and commits and pushes of main keep it current

- Status: Accepted 2026-10-28
- Decided by: the user, Claude doing the setup the same day. The user's words: "Upload the Remix
  payload to https://steamcommunity.com/sharedfiles/filedetails/?id=3829070317, this will be the item
  that the user will subscribe to for RTX-Remix to work given winmm.dll is installed. In the future,
  commit will update this workshop item, and push will update both GitHub and this workshop item."
- Builds on: [0015](0015-workshop-route-for-native-packages.md) (the Workshop route), and the
  test-item rules of AGENTS.md rule 5. Item 3829070317 started as that test item.

## Context

- **What a subscriber needs.** RTX Remix in GMod needs two packages: the Remix runtime and the RTX
  fixes. M4 showed that the runtime alone loads but does not path-trace: the frame needs the fixes'
  shader DLL, patch sets and Lua ([M4 review](../handover/M4-review.md),
  [M5 report](../handover/M5-report.md)). A subscriber should not have to collect several items.
- **What `gmpublish` can do.** `gmpublish update` replaces an item's file (and icon). It cannot change
  the title, the description or the visibility.
- **The tested runtime.** Runtime B (`a8e39d93`, tested in M5, M7 and R1) survives only in
  `out\packages\m5\runtime-b.gma`: its build folder in the fork is gone. The fork's `_output` holds
  the older runtime A.

## Decision

1. **One combined package** (`gmod-rtx-remix`) goes into item 3829070317. It holds the runtime and
   the RTX fixes, the fixes carrying the Lua companion.
   - [`tools/package_workshop.py`](../../tools/package_workshop.py.md) merges the packages: kinds and
     session extras united, one runtime, no file from two parts, every file checked.
   - The parts are listed in [`tools/workshop.json`](../../tools/workshop.json): today runtime B as
     pinned, and the fixes rebuilt from the fixes repository with the modules M5 used.
2. **[`tools/publish_workshop.py`](../../tools/publish_workshop.py.md) keeps the item current.**
   - It fingerprints the inputs and stops when they are unchanged.
   - Otherwise it builds the package and compares the content digest with what the item holds, and
     uploads with `gmpublish update` only when the content changed.
   - The version is `0.0.0-dev.<UTC time>+<fingerprint prefix>`.
   - Its state is shared by every worktree, under the main checkout's `out\workshop`.
3. **Git hooks run it in the background.** `post-commit` and `post-merge` publish when the branch is
   `main`, and `pre-push` publishes when `main` is pushed. So a commit (or merge) on `main` updates
   the item, and a push updates GitHub and the item.
   - Commits on other branches publish nothing; a milestone branch reaches the item when it is merged.
   - The hooks are installed once per clone with `publish_workshop.py --install-hooks`.
4. **The item stays hidden until the user makes it public.** Its title, description and visibility
   are set on its Workshop page. The GPL-2.0 and NVIDIA licence checks come before that.

## Consequences

- **A subscriber needs three things:**
  - the loader's `bin\win64\winmm.dll`;
  - a `native-loader\config.json` that allowlists the item: `{"schema": 1, "allow": {"workshop":
    ["3829070317"]}}`;
  - a subscription.

  The package itself adds `-insecure` and the other launch arguments. GMod refuses to mount the item
  itself, which it reports as "Couldn't mount file"; the loader deploys it.
- **Most commits upload nothing.** A commit that touches only the loader or the docs costs a
  fingerprint. A commit that changes the packaging inputs costs a rebuild (seconds) and, if the
  content changed, a 1.4 GB upload.
- **Publishing needs this machine.** It runs only where `workshop.json`'s paths exist and Steam runs
  logged in to the item's owner. Elsewhere, for example in a sandboxed agent, the background run
  fails, logs why, and the next commit or push of `main` on this machine tries again.
- **Moving to a new runtime build** means pointing the runtime part at it: a fork build folder through
  `package_runtime`, or a new pinned package. That change is committed like any other.

## Alternatives considered

- **Two items, the runtime and the fixes, linked as Workshop dependencies.** Subscribers would need
  both, and two allowlist entries, and the versions could drift apart. One item keeps them together,
  as ADR 0012 already argued for the fixes' halves.
- **Publishing from CI.** That needs a Steam login on a build machine, which is not available.
- **Publishing by hand.** The user asked for commits and pushes to do it.
- **Uploading on every commit.** That is 1.4 GB per commit; the fingerprint and digest make an
  unchanged commit cost nothing.
