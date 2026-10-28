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

Only if you want to know whether the Workshop accepts and keeps an item with native files (it is
against the Workshop rules for GMod as the wiki states them, so expect a removal or a ban risk on the
item). Use a throwaway package, never the real runtime, and remove the item afterwards.

1. Build a tiny package with a harmless DLL, for example from the M4 test fixtures:
   `python tools\package_runtime.py --runtime out\build\win64-release\loader\proxy\tests\runtime --gma out\m6\upload-test.gma --id upload-test --version 0.0.1`
2. Upload it with GMod's tool (Steam running): `bin\gmpublish.exe create -addon out\m6\upload-test.gma -icon <a 512x512 jpg>`.
   `gmpublish` may refuse the file itself (that is the answer then).
3. On the item's Workshop page, set the visibility to **Private** at once.
4. Subscribe from the same account, let Steam download it, and check the item folder under
   `steamapps\workshop\content\4000\<id>\`: is the `.dll` there, byte for byte (`nlctl verify`)?
5. Delete the item from the Workshop.

If the item survives and downloads intact, a later record can make the Workshop the preferred route
for users who want updates through Steam; the loader needs no change for that.

## Open

- Publishing the two packages as release assets (and checking the NVIDIA redistributables' licences
  first) is the user's call.
- An `nlctl fetch` for a URL with a pinned SHA-256 stays on the roadmap's "Later" row.
