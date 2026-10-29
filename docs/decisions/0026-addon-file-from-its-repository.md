# 0026: A bundled add-on may take single files from its own repository

- Status: Accepted 2026-10-29. The same day the fix landed on Model Hotloader's `main` as `bed4582`,
  and its branch was deleted
- Decided by: the user ("Yes, fix it", to fixing Model Hotloader's install check in its repository
  and getting the fix into the RTX package), Claude choosing how
- Builds on: [0024](0024-bundled-addons-and-module-dependencies.md) (bundled add-ons, module
  dependencies)
- Extends 0024: the classic install stays the source of the Model Hotloader part, except for the files
  a part names with `--addon-file`.

## Context

- **The warnings.** Since round 4, Model Hotloader prints two lines on the server and the client, in
  every RTX session on the PoC and the field:
  - "Missing bin/win64/mmdhl_runtime_win64.dll. Reinstall the native package and restart."
  - "The loaded runtime DLL is not the file that was checked".

  Its native module, its runtime and its worker all work ([RESEARCH.md](../RESEARCH.md) section 23).
- **Why.** Its install check (`lua/mmdhl/installation.lua`) reads the runtime only where Windows looks
  for it, `bin\win64`. It then compares the runtime the game loaded with that copy. A package cannot
  write `bin\win64` (0003, 0014), so the loader loads the runtime from `garrysmod\lua\bin` before the
  module (0024).
- **The fix is Model Hotloader's.** On its branch `claude/runtime-in-lua-bin`, the check reads the copy
  in `lua\bin` when `bin\win64` has none. It reports the missing file only if the loaded runtime is not
  that copy, so a player without the loader still gets the same reason when the module does not load.
- **Where the part comes from.** The RTX package takes the add-on from the classic install (0024), which
  agents never write (AGENTS.md rule 1). The user updates that copy with their own deploy. It equals
  Model Hotloader's `main` working tree, including work staged there since 2026-10-26, except for
  `native_policy.lua`, which the native build writes.

## Decision

1. **`package_content.py --addon-file PATH FILE`** replaces one file of a bundled add-on with FILE.
   - PATH is the add-on's folder name and a path in it.
   - Only a file the add-on has (after the gmad filter) can be replaced, so a misspelled path is refused
     rather than added.
2. **The Model Hotloader part** takes `lua/mmdhl/installation.lua` from Model Hotloader's main checkout
   (`ipg\!GMHLVK\Gmod-Model-Hotloader-with-Vulkan\addon\lua\mmdhl\installation.lua`). The fix is
   mirrored there, unstaged, beside the staged work, so the file is the classic install's copy plus the
   fix. Every other file of the add-on, and the natives, still come from the classic install.
3. **FILE is a publish input.** It is a separate argument, so `publish_workshop.py` fingerprints it like
   every absolute path a part names, and a change to it publishes.
4. **Temporary by nature.** Once the user's next deploy puts the fix into the classic install, the
   replacement changes nothing, and the option can be dropped from the part.

## Consequences

- RTX sessions show no Model Hotloader runtime warning. A player without the native loader whose
  runtime is missing from `bin\win64` still gets "Missing bin/win64/..." as the reason the module did
  not load.
- Until the deploy, a later edit to that one file in Model Hotloader's main checkout reaches the RTX
  package at the next publish without waiting for the deploy, as the other add-on parts' working trees
  already do.
- Model Hotloader's own Workshop item and releases are the maintainer's; this changes neither.

## Alternatives considered

- **Write the fix into the classic install.** AGENTS.md rule 1 forbids it.
- **Take the whole add-on from Model Hotloader's working tree.** Every publish would ship whatever is
  uncommitted there, without the user's deploy as the gate. Its `native_policy.lua` would also lack
  the 2.3.1 release the shipped natives are, which changes the check's verdicts.
- **Take the file from the fix branch's worktree.** It lacks a line the staged work adds to the same
  file and the classic install already ships, so the package would lose it.
