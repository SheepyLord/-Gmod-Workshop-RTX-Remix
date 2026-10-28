# 0014: R1 hardening: narrower package areas, deployed files checked at activation, a safer restore

- Status: Accepted 2026-10-28
- Decided by: Claude, triaging Codex's whole-repo review ([R1 report](../handover/R1-report.md),
  [triage](../handover/R1-triage.md)). Each point narrows what the loader does; nothing is loosened
  (AGENTS.md rule 4).
- Supersedes: the `garrysmod/cfg/...` package area of the M2 path rules
  ([PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md), `paths::root_area`). Refines
  [0003](0003-native-trust-allowlist.md) (what the allowlist protects),
  [0008](0008-activation-at-startup.md) (activation preconditions) and
  [0010](0010-rtx-session-extras.md) (the session-variable restore).

## Context

Codex's review found three places where the loader trusted more than it should:

- **Package areas.** A package could place create-only files in `garrysmod/cfg`. That folder holds 18
  of Steam's depot files (`config_default.cfg`, `valve.rc`, the `skill*.cfg` set and others; measured
  from the depot manifests, [RESEARCH.md](../RESEARCH.md) section 16). Create-only protects an
  existing file, so a depot file that happened to be missing would have been recreated with the
  package's bytes, against AGENTS.md rule 2 (R1-007).
  - The other areas (`rtx-remix/mods`, `garrysmod/lua/bin`, `garrysmod/addons`, `garrysmod/data`)
    hold no depot file today.
  - No package of ours uses `garrysmod/cfg`. The session variables go through the loader's own
    generated cfg files, not package files.
  - The folder areas also accepted a file directly in the area, such as `garrysmod/data/x.txt` or
    `garrysmod/addons/x.gma`, which ADR 0011 describes as folders only (R1-022).
- **Activation.** It checked only the size the journal recorded for `d3d9.dll` and the config
  layers. A deployed file changed in place, or while a second instance kept a start from deploying,
  was loaded (R1-008).
- **The session-variable restore.** It ran even when the journal could not be read, and it put every
  recorded value back, including one the user had changed after the RTX session (R1-004).

## Decision

1. **Package areas.**
   - `garrysmod/cfg` is no longer a package area.
   - In `rtx-remix/mods`, `garrysmod/addons` and `garrysmod/data`, every file must be inside a named
     folder: `<area>/<folder>/<file>` at least.
   - The manifest parser and the journal parser both enforce this (`paths::file_depth_ok`).
   - A new area needs a new decision, and a check that Steam's depots hold nothing in it.
2. **Activation checks size and time.** Before activation loads anything, every file it loads or hands
   to the runtime must have the size and last-write time the journal recorded:
   - the whole runtime payload, `d3d9.dll` included;
   - the config layers;
   - the module-override DLLs.

   If one differs, the start stays vanilla and says why. The next start that deploys stages a fresh
   copy. Deployment keeps checking the SHA-256 of everything it places. Hashing the whole runtime
   (about 1 GiB) again at every start would cost seconds, more on a hard disk.
3. **What the allowlist protects.** It decides which packages may deploy and load native code. It
   does not protect deployed files from a local process that can write into the game folder: such a
   process could equally replace `gmod.exe` or the bootstrap itself. Point 2 catches accidental
   changes, not deliberate ones that keep the size and time.
4. **The session-variable restore.**
   - It runs only in a start whose journal could be read. With an invalid journal the process stays a
     pure pass-through, and the record waits.
   - A recorded value is put back only while `config.cfg` still holds the value the RTX session set.
     A value the user changed since is theirs to keep. A value that is already the user's is skipped.
   - When nothing is left to put back, the record is dropped.
   - The record (`native-loader/session_cvars.json`) is now schema 2: it also holds the session values
     (`session_values`). Schema 1 records are still read; for them the deployed packages' session
     variables stand in.

## Consequences

- A package that used `garrysmod/cfg`, or put a file directly in a folder area, is refused at manifest
  validation. None of ours does.
  - A journal written by an older loader that records such files is invalid: the loader stays a pass-through
    until it is uninstalled.
  - No install has such a journal: the PoC and the field install were uninstalled after M5-M7.
- A runtime file that changes after deployment is no longer loaded. The status report says which one.
  Starting once with the allowlisted source present redeploys it.
- The restore may leave fewer values than before. The ones it leaves are values the user changed
  themselves.

## Alternatives considered

- **Read Steam's depot manifests at run time and refuse depot paths in any area.** This would need a
  protobuf reader in the bootstrap, and it would depend on Steam's cache. Narrowing the areas does the
  same job with a rule that has no inputs.
- **Hash every runtime file at every start.** Rejected for its cost (point 2). Point 3 explains why
  hashing would not stop a deliberate change anyway.
- **Keep restoring every recorded value.** Rejected: it overwrote changes the user made themselves.
