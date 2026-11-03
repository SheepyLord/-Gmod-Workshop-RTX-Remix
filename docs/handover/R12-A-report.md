# R12-A: NPC readiness after deleting and reimporting a character

Branch: `r12-hotloader`, from `2dd3033`. Implementer: Codex (gpt-6.1-sol).
Scope: R12 item 36. Implementation date: 2026-11-03 UTC (the user's report is 2026-11-02).
Implementation, Release validation and PoC validation are complete. Ready for Claude's integration.

## Cause

Carrier bytes, rig metadata and the two Lua realms have separate lifetimes.
Windows can retain a mounted `carrier.gma` after deletion while `rig.json` and short-name
records are removed. Native `PrepareCarrier`'s cached-archive branch recreates the name record
and returns its fitted manifest, but does not recreate `rig.json`. The persistence wrapper
calls `EnsureModel` before `AttachNative` has cached that returned manifest. A cold model
lookup can therefore reject an already mounted/precache-ready carrier; clients also need the
missing sidecar to create presentation. Warm server metadata can hide the defect.

Deletion cleared the client's rig table but left server lookups and persistence's converted
NPC variants. In particular, a converted carrier could outlive the entry and ignore the fit
settings of its reimport. Remounting every archive would risk reloading models used by live
entities and would not repair metadata.

## Fix

See [ADR 0094](../decisions/0094-reimported-carrier-metadata-and-state.md).

- `RememberRig` accepts a loadable native manifest with matching full key/asset/model identities.
  Every spawn factory, attachment, actor readiness gate (including arms) and persistence conversion
  remembers it before `SetModel` or publication. Only a missing sidecar is restored, from the
  manifest native returned. A staged write is byte-verified before rename; failed/short writes
  never become final metadata. Existing metadata files are retained.
- An exact model lookup accompanies the full-key cache. It can resolve the prepared carrier
  without depending on a short-name record removed in this session. Persistence mounts also
  require the exact requested model.
- Entry deletion/withdrawal clears only that asset's reusable rig/model, morph geometry and
  converted-carrier caches in each realm. The conversion memo is shared across Lua refreshes;
  its installed wrapper and current forget callback must reference the same table. A conversion
  also requires its sidecar and current availability before reuse. Existing entities keep their
  already bound immutable manifest, so a new fit or cache
  withdrawal does not change their model or lose their metadata. No mount cache is globally reset.

Only five packaged Lua inputs and their index change. No native binary, fixes, companion,
runtime or loader code is changed. Input metadata is updated through `tools/inputs.py import`;
there are no new binary/LFS objects.

## Regression and Release checks

`tools/test.ps1 -Config Release` passed after the implementation and QA safety tests:
**26/26 CTests, 557 Python tests, two existing skips, “All checks passed.”**
Final evidence: `out/r12-a/release-verified-2.log` (earlier complete passes are also retained).

`test_mmd_reimport.py` runs fourteen LuaJIT cases against the production deletion, factories,
readiness, model lookup and persistence wrapper, with separate client/server cache lifetimes:
retained archives with missing metadata, changed fits, NPC/combine/ragdoll/player/arms, a new
saved bone map after deletion, model-only NPC conversion, failed/short writes, failed mounts,
existing metadata preservation and bound entities after their sidecar is gone. It also removes
a converted sidecar before a withdrawal callback and refreshes Lua with the guarded wrapper
still installed. A second asset
stays cached. A delegating outer `SetModel` wrapper is exercised; this is not a claim to have
loaded the user's complete compositeentities addon.

`test_mmd_reimport_qa.py` covers the activity gate's foreground/recent-input combinations and
lock ownership, normal release, failed restoration and a replaced lock, without any actual game,
registry or UI operation. The older morph/map-readiness harness stubs only the new manifest
persistence boundary and still passes its own cases.

`tools/inputs.py verify --part model-hotloader` reports no problems; repository conventions and
`git -c core.whitespace=cr-at-eol diff --check` pass. Packaged Lua retains its existing CRLF bytes.

## PoC evidence

The original PMX folder is read only. The test copy is `out/r12-a/source/endminf/女管理员.pmx`,
copied from the plan's `the_endministrator/1_PMX/...1dacd3b3a151ec99aeb33455dbf5d721` folder.
The driver snapshots the PoC's `garrysmod/data` and generated `~gmod_topbr` by rename, uses isolated
test directories (including automatic PBR and eye-white caches), and restores them after normal
session shutdown. Candidate runs start at the menu, back up/stage five Lua files after loader
startup, then request the first map so both game realms start with the production files.
All launches use the shared lock, the field activity gate and `-multirun`.

The cold baseline reproduces the user's exact English carrier-outdated message at
`out/r12-a/baseline-cold/console-after.log:692`. Its asset is
`a9c7045d38634d1d0469733b152022f5a6d47a161dffafbf0c8688d0ffd23ab3`, the field's Endministrator.
The saved NPC carrier `5dba2333854dc362c0fc5f85f3fced0d` had no sidecar after deletion/reimport:
its server model remained valid, `MMDHLBindingError` recorded `persistence.error.carrier_outdated`,
and its client had no rig/instance. A newly built ragdoll had its sidecar and instance 1.
The initial warm baseline masked the server error but likewise lost NPC/player client instances.

The first candidate proved all nine direct factory spawns through two deletion cycles, with
sidecars and client instances intact, then exposed the converted-carrier cache's missing-sidecar
gap. That additional gap and Lua-refresh memo lifetime now have explicit regressions and fixes.

The final **`fixed-clean`** run starts with the current wrapper at `persistence.lua:243` (recorded
by `R12A_INSTALLED`, not inferred from the file on disk). It passes:

| Sequence | Result |
|---|---|
| Import the copied PMX; citizen NPC and player model | Both Source-valid, attached, sidecar present, positive client instance |
| Delete; import the identical source; ragdoll, citizen and player | All ready; the old NPC/player carrier keys work again; ragdoll has 18 bodies |
| Change scale from 1 to 1.1 | Citizen key changes from `5dba2333...` to `71f93c50...`; existing actors keep their own model/rig |
| Convert a model-only ragdoll carrier to a citizen | Citizen role, attached and ready |
| Delete again; identical import; ragdoll, scale-1.1 NPC and player | All ready, with all metadata and positive client instances |
| Repeat the model-only conversion | Ready again; server forget count is 2 |

All **nine factory requests** have `manifest=true`, valid Source models and positive client
instances (`1,2,3,4,5,6,8,9,10`); neither conversion fails. The retained-entity observations
verify four entities before the second deletion and three after the final conversion: unchanged
model, original rig key and valid model in all seven observations. The session-only console has
**zero restore errors, zero probe errors and zero Lua errors**, and the game exits normally with
exit 0. The active forget hook runs in both realms on each deletion.

Evidence under `out/r12-a/`:

- `baseline-cold/console-after.log`, `events.json`, `session.json`, `11-citizen.png`: exact baseline
  error and missing client presentation. Its `08-ragdoll.png` and `17-citizen.png` are controls
  for newly generated carriers, whose metadata exists.
- `fixed-clean/console-after.log`, `events.json`, `summary.json`, `session.json` and `restored.json`:
  final assertions, normal quit and restoration. All nine PNGs were generated; inspected examples
  are `19-citizen.png` (NPC after reimport), `32-ragdoll.png` (second reimport), and
  `38-player.png` (changed player carrier). The cameras deliberately pose actors for inspection;
  this is readiness/presentation QA, not a navigation test.
- `qa-summary.json`: per-session outcomes and screenshot SHA-256s. `fixed-clean/baseline-hashes.json`
  proves the five original PoC Lua files matched `2dd3033` before staging and restoration.
- `poc-depot-verification.json`: **2,877 stock files / 7,279,873,012 bytes OK**, zero missing,
  size/hash/reparse/unverified failures. The known user-config `autoexec.cfg` difference is retained.

Exploratory `baseline` and `fixed` are retained for audit, not the final visual/conversion proof:
the first warm run's guide obscured images and its model-only probe lacked the citizen custom-model
flag. The early candidate staged into running Lua and then caught the additional conversion gap.
The final driver closes the guide, uses the custom-model flag, follows the inspected entity, stages
before the first game realm, and asserts the active wrapper definition and both conversions.

Every session used `-multirun` and the activity gate. Each finished with its original `data`, generated
ToPBR directory, config bytes, shared video settings, previous console and (for candidates) five
Lua files restored; Lua restoration is hash-verified. Config SHA-256 is `a4fc3d9a...` throughout.
Each own game quit normally and each own lock was released. The field was not launched or written,
and no field console was read. Remix `user.conf` and the original `E:\G\Upload` folder were untouched.

## Integration

Claude owns review/integration. No merge, push, tag or publication is performed by this task.
