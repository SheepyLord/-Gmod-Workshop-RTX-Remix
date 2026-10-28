# 0003: Only allowlisted packages may deploy native code until signatures exist

- Status: Accepted 2026-10-27
- Decided by: the user (SheepyLord)

## Context

The loader deliberately does what GMod forbids: it runs native code that arrives through `.gma`
files. Verifying who made a package (signatures) is a later milestone. The field install has 759
Workshop items installed; without a gate, any of them that carried a loader manifest would run code.

## Decision

- `native-loader\config.json` holds an explicit allowlist: Workshop ids, local `.gma` paths and
  development folders. Nothing else is opened as a package, let alone deployed.
- Path rules apply to every package even when allowlisted: no absolute paths, `..`, reparse points
  or device names; root files only under allowed prefixes; Steam depot files and `user.conf` are
  never written.
- Off switches (`-nonativeloader`, `NATIVE_LOADER_DISABLE=1`, `native-loader\disable`) always win.
- Loosening any of this needs a new decision record the user agreed to.

## Consequences

- Subscribing to a package on the Workshop is not enough; the user also allowlists it (once).
  Acceptable for the PoC and field test.
- An allowlisted item whose owner account is compromised can still push code; only signatures fix
  that (later milestone).

## Alternatives considered

- **Any `.gma` with a manifest**: fastest to iterate, but every Workshop item could run code.
- **Prompt on first sight**: friendlier, but needs UI at the entry point and trains users to click "yes".
