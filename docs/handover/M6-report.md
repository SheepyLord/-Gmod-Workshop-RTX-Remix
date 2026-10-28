# M6 report: the Workshop route

- Author: Claude, 2026-10-28, planned and built without further approvals at the user's request;
  publishing to the Workshop is outward-facing (AGENTS.md rule 5) and was **not** done.
- Branch: `m5-rtx-fixes` in the main checkout: M5 and M6 share files (the status report, the companion), so they were committed together and merged into `main` as one.
- Decision: [ADR 0012](../decisions/0012-distribution-route.md). Facts: [RESEARCH.md](../RESEARCH.md)
  section 14.

## Plan, as carried out

The roadmap's M6: a private-visibility upload test of a runtime package, LZMA-wrapped downloads,
two-phase updates with a restart prompt, and a distribution route chosen with evidence. Everything
that does not publish anything was done; the upload test is left to the user, with the steps below.

| Item | Result |
|---|---|
| Can a package be built for the Workshop with GMod's own tools? | No: `gmad.exe` refuses `native/manifest.json` and `native/payload/*.dll` ("Not allowed by whitelist") and writes nothing; a Lua-only folder packs |
| LZMA-wrapped downloads | Covered since M3: `e2e_deploy.py` deploys from a `*_legacy.bin` Workshop item and updates it |
| Two-phase update | Deployment happens at the next start for every source (M3/M4). New: `status.json` lists each deployed package with its source and, for Workshop items, the update time Steam had installed at start-up |
| Restart prompt | New: the Lua companion compares that time with `steamworks.FileInfo` at client start and every ten minutes, prints a line and shows a notification once per item: "RTX package <id> was updated: restart Garry's Mod to use it". Tested under LuaJIT with GMod's functions mocked |
| Distribution route | ADR 0012: native packages are released as downloads (local sources); the Workshop stays a supported source |

## Evidence

- `out/m6/gmad-probe`: `gmad.exe create` output for both folders (see RESEARCH.md section 14).
- `tools/tests/test_companion.py`: 2 tests (a newer Workshop version asks once; the deployed version
  and a local package say nothing).
- `loader/proxy/tests/activation_integration.py`: the Workshop start-up scenario checks the new
  `packages` entry (`source: workshop`, `label: 123`).
- Full suite: see the M6 commit message.

## The private upload test, for the user

Only if you want to know whether the Workshop accepts and keeps an item with native files. Use a
throwaway package, never the real runtime.

**Corrections, 2026-10-28, at the user's direction:**
- This section first said such an item is against GMod's Workshop rules. It is not:
  - GMod's [Steam Workshop rules](https://wiki.facepunch.com/gmod/Steam_Workshop_Rules) have no rule
    about file types.
  - The `.dll`/`.exe` list on the wiki's addon-creation page is what `gmad.exe` will pack.
- It also said to delete the item afterwards (step 5). Instead, agents may upload test items for this
  project, and nothing on the Workshop is removed or deleted until the user says the project is done
  (AGENTS.md rule 5).

1. Build a tiny package with a harmless DLL, for example from the M4 test fixtures:
   `python tools\package_runtime.py --runtime out\build\win64-release\loader\proxy\tests\runtime --gma out\m6\upload-test.gma --id upload-test --version 0.0.1`
2. Upload it with GMod's tool (Steam running): `bin\gmpublish.exe create -addon out\m6\upload-test.gma -icon <a 512x512 jpg>`.
   `gmpublish` may refuse the file itself (that is the answer then).
3. On the item's Workshop page, set the visibility to **Private** at once.
4. Subscribe from the same account, let Steam download it, and check the item folder under
   `steamapps\workshop\content\4000\<id>\`: is the `.dll` there, byte for byte (`nlctl verify`)?
5. ~~Delete the item from the Workshop.~~ Keep it: nothing on the Workshop is deleted until the
   project is done (corrected above).

If the item survives and downloads intact, a later record can make the Workshop the preferred route
for users who want updates through Steam; the loader needs no change for that.

## The private upload test, as run (2026-10-28)

The user approved the test ("You have approval to perform workshop distribution test") and pointed
out that `tools/gmapack` packs any folder. Claude ran it on the PoC, from the R1 worktree. Evidence is
in `out\worktrees\r1-review\out\m6-ws\`: the builder and session scripts, both `gmpublish` outputs,
and the session records.

| Step | Result |
|---|---|
| Package | `gmapack` packed a throwaway package, entirely our own code (105,447 bytes): the M4 fixture DLL as payload, a Remix mod folder, a Lua add-on folder, and a Lua file at the archive root |
| Upload | `bin\win64\gmpublish.exe create` (run from the PoC) accepted it: item **3829070317**, "currently marked as hidden" |
| Download | In a PoC session, GMod's `steamworks.DownloadUGC` fetched it with no subscription. Steam stored `steamapps\workshop\content\4000\3829070317\nl-ws-test-0.0.1.gma`, byte-identical to the upload (same SHA-256), and listed it in `appworkshop_4000.acf` |
| Deploy | With the loader allowlisting only that Workshop ID, start-up deployed it (generation 1). The payload DLL was byte-identical, and the mod and add-on folders were placed. GMod mounted the add-on folder and ran its Lua. `status.json` listed `source: workshop`, the item ID and the update time |
| Update | `gmpublish update` uploaded 0.0.2. `DownloadUGC` fetched it during a session whose start had kept 0.0.1 (`unchanged`). The next start deployed 0.0.2 (generation 2, the earlier payload kept for rollback) |
| GMod's own mount | Refused: "Couldn't mount file". A probe found why: a Lua-only `gmapack` archive mounts, and the same archive with a `.dll` does not. GMod does not mount an archive holding a file outside its whitelist |
| Clean-up | Loader uninstalled from the PoC; 2,877 depot files OK. The test item stays on the Workshop, hidden, for later tests: nothing on the Workshop is deleted until the project is done (the user's instruction) |

Result: [ADR 0015](../decisions/0015-workshop-route-for-native-packages.md).
- Native packages can go through the Workshop. Their Lua must come through the loader's add-on folders
  (ADR 0011), because GMod does not mount the item itself.
- A public release is still the user's call.
  - The Workshop's rules have no rule about file types (corrected 2026-10-28; see ADR 0015).
  - The licences need checking first.
  - The item's description should say that it needs the loader, because GMod cannot mount it by
    itself.

## Open

- Publishing the two packages as release assets (and checking the NVIDIA redistributables' licences
  first) is the user's call.
- An `nlctl fetch` for a URL with a pinned SHA-256 stays on the roadmap's "Later" row.
