# 0015: Native packages can be distributed through the Workshop, packed with gmapack

- Status: Accepted 2026-10-28
- Decided by: the user, with Claude's private upload test the same day. The user's words: "the
  workshop accepts anything that is packed within a gma ... tools\gmapack could pack any folder into a
  gma", and approval to run the test.
- Supersedes in part: [0012](0012-distribution-route.md), namely its premise that native packages
  cannot go through the Workshop because `gmad.exe` refuses them, and with it "released as downloads
  only". Its other points stand: the Workshop stays a supported source, and local sources stay.
- Confirms: [0011](0011-lua-addon-folders.md) for packages distributed through the Workshop.

## Context

ADR 0012 chose downloads because GMod's `gmad.exe` refuses `native/manifest.json` and DLLs. The user
pointed out that the Workshop accepts any GMA, and that `tools/gmapack` packs any folder.

The private upload test, run on 2026-10-28 ([RESEARCH.md](../RESEARCH.md) section 14; evidence in the
R1 worktree's `out/m6-ws/`):

1. **Pack.** `gmapack` packed a throwaway package of our own code, 105,447 bytes:
   - a fixture DLL as payload;
   - a Remix mod folder;
   - a Lua add-on folder for the loader to deploy;
   - a Lua file at the archive root.
2. **Upload.** GMod's `gmpublish.exe create` uploaded it as item 3829070317, marked hidden.
3. **Download.** Inside a PoC session, GMod's `steamworks.DownloadUGC` fetched it without a
   subscription.
   - Steam stored it in `steamapps/workshop/content/4000/3829070317/` as a plain `.gma` under the
     uploaded name, byte-identical (same SHA-256).
   - Steam listed it in `appworkshop_4000.acf`.
4. **Deploy.** The loader, allowlisting only the Workshop ID, deployed it at start-up.
   - The payload DLL arrived byte-identical, along with the mod folder and the add-on folder.
   - GMod mounted the add-on folder and ran its Lua.
   - `status.json` listed the package with `source: workshop`, the item ID and Steam's update time.
5. **Update.** `gmpublish update` uploaded 0.0.2.
   - During a session, `DownloadUGC` fetched it; that session's start had kept 0.0.1.
   - The next start deployed 0.0.2. This is M6's two-phase update, end to end.
6. **GMod's own mount.** GMod refused to mount the item itself ("Couldn't mount file"). A probe
   settled why: a Lua-only `gmapack` archive mounts, and the same archive with a `.dll` added does
   not. GMod does not mount a GMA that holds a file outside its whitelist.

## Decision

1. **Publishing.** A native package may be published on the Workshop: packed with `tools/gmapack`,
   uploaded with GMod's `gmpublish.exe`. The loader needs no change. It finds the item through Steam's
   Workshop folder and `appworkshop_4000.acf`, then checks and deploys it like any allowlisted source
   (allowlisted by Workshop ID, [ADR 0003](0003-native-trust-allowlist.md)).
2. **Lua.** Such a package carries its Lua as add-on folders under
   `native/root/garrysmod/addons/<addon>/` ([ADR 0011](0011-lua-addon-folders.md)).
   - GMod does not mount the item, so Lua at the archive root never runs.
   - The loader's add-on folders are the only way the package's Lua reaches the game.
   - They are also what lets [ADR 0013](0013-rtx-only-addons-hidden-without-rtx.md) hide that Lua
     without RTX.
3. **Public releases.** Whether a public release uses the Workshop, downloads or both is the user's
   decision, made per release.
   - GMod's Workshop rules restrict `.dll` files, so a public item may be removed, or the account
     warned, if it is reported.
   - The GPL-2.0 and NVIDIA licence obligations apply to any public package.

## Consequences

- **Updates through Steam need no new code.** Steam fetches a new version, the next start deploys it,
  and the companion's notice (M6) asks the user to restart.
- **Subscribers see a console line.** GMod tries to mount the item at every start, refuses, and
  prints "Couldn't mount file". It is harmless, but the item's description should say so.
- **The test item (3829070317) stays hidden until the user deletes it.** Deleting needs its Workshop
  page.

## Alternatives considered

- **Downloads only (ADR 0012).** Gives up Steam's distribution and updates, for no technical reason.
- **Lua at the archive root, mounted by GMod.** GMod refuses archives that hold native files. Even if
  it did not, nothing could hide that Lua without RTX.
- **Two Workshop items: Lua only (mountable, and `gmad` can build it) plus a native item.** The
  RTX-only Lua would then run without RTX, and the two items would have to be kept in step.
