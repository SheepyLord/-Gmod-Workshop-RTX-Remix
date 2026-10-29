# loader/cli/ (`nlctl.exe`)

The loader core on the command line, so packages and installs can be examined and deployed without
starting Garry's Mod. It links `nl_core`, the same library the bootstrap uses.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Builds `nlctl`; registers the `nlctl_crosscheck_gmapack`, `nlctl_e2e_plan`, `nlctl_e2e_deploy` and `nlctl_uninstall_loader` CTests |
| `nlctl.cpp` | Command parsing (`wmain`, Unicode paths) and the commands below |
| `tests/crosscheck_gmapack.py` | CTest: `nlctl` must agree with the Python reference reader ([doc](tests/crosscheck_gmapack.py.md)) |
| `tests/e2e_plan.py` | CTest: the whole M2 chain on gmapack-built packages in a fake Steam library ([doc](tests/e2e_plan.py.md)) |
| `tests/e2e_deploy.py` | CTest: `apply`, `status`, `rollback` and `uninstall` end to end, refusals included ([doc](tests/e2e_deploy.py.md)) |
| `tests/uninstall_tests.ps1` | CTest: `tools\uninstall-loader.ps1` end to end in synthetic game folders ([doc](tests/uninstall_tests.ps1.md)) |

## Commands

```powershell
nlctl inspect <file.gma> [--json]   # header and file index (LZMA-wrapped: decoded only that far)
nlctl verify  <file.gma> [--json]   # one pass: every nonzero file CRC, the archive CRC, trailing data
nlctl scan    <folder>   [--json]   # read-only parse of every .gma / .bin archive below the folder
nlctl manifest <file.gma|folder> [--json]  # validate a native package; summarise its manifest
nlctl plan <game root> [--steam-dir <dir>] [--json]  # what the loader would deploy, read-only
nlctl apply <game root> [--steam-dir <dir>] [--dry-run] [--json]  # deploy the plan
nlctl activation <game root> [--json]  # what start-up would load, set and add from the runtime (read-only)
nlctl status <game root> [--verify] [--json]   # the journal; are the deployed files as placed (read-only)
nlctl rollback <game root> [--dry-run] [--json]   # return to the previous generation, and hold it
nlctl uninstall <game root> [--dry-run] [--json]  # remove everything the loader placed, and its journal
nlctl version
```

`apply` deploys what `plan` shows, as one transaction
([ADR 0007](../../docs/decisions/0007-transactional-deployment.md)). It reports its `outcome`:

- `deployed`, with the new generation number;
- `unchanged`: nothing to do, and nothing was written;
- `held`: a rollback is being kept;
- `planned`: a `--dry-run`;
- `refused` or `failed`.

It also reports each change (`add`, `replace`, `remove`, `adopt`, `payload`, `delete`), the
packages it did not deploy and why, notes about files it left alone (changed by the user, not
placed by the loader), and `operations`, the number of file-system changes it made. `rollback`
returns to the previous generation (the generation before that is not kept); the next `apply`
leaves it in place until the planned packages differ from the ones it rolled back from. `uninstall`
removes what the journal lists, then the journal and `native-loader\lock`. M4 also removes generated
status files and the empty `garrysmod/data/native-loader` folder, preserving unrelated files there.
It leaves `config.json`
and the bootstrap; [`uninstall-loader.ps1`](../../tools/uninstall-loader.ps1.md) does both steps.

These four commands, and `status`, exit with:

- `0`: done, or nothing to do;
- `1`: refused or failed, with the install as it was. That covers: this folder's `gmod.exe` is
  running, another deployment holds the lock, a failure was undone, there is nothing to roll back
  to, or (`status`) a file is not as placed or a transaction is pending;
- `2`: an invalid `config.json` or `state.json`.

`plan` runs the deployment half of what the bootstrap runs at start-up, without changing anything:
it reads `native-loader\config.json`, finds every allowlisted source and every subscribed Workshop
item that holds a package (marked "subscribed, content only",
[ADR 0027](../../docs/decisions/0027-content-packages-from-any-subscription.md)), loads each package
and prints one decision per source (active, or why not;
[ADR 0006](../../docs/decisions/0006-package-precedence-and-planning.md)). `--steam-dir` replaces the
registry lookup of Steam's folder when the game root is outside a Steam library. Exit `0` when a plan was made (even if everything was skipped), `2` for an invalid config.

`activation` shows the other half: from the deployed current generation it prints what start-up
would do with the runtime ([ADR 0008](../../docs/decisions/0008-activation-at-startup.md)) — the
`d3d9.dll` it would preload, the folder added to the DLL search, whether System32's `vulkan-1.dll`
is preloaded first, the environment variables it would set (config-file layer lists and the
package's own, skipping any this shell already has set) and the launch arguments it would add.
Package config layers precede the existing user list; absent/empty config lists use the default
root conf last. Missing/disabled config and pending journal transactions are inactive. It
reads the journal and config only. Launch arguments are shown as the package's whole set, since
nlctl does not have the game's command line. Exit `0` always (or `2` for an invalid journal/config).

`manifest` exits `0` for a valid package, `1` when the input has no `native/manifest.json` or the
manifest breaks a schema-1 rule (the message names the field), `2` for a damaged archive.

Plain (`.gma`) and LZMA-wrapped (Workshop `*_legacy.bin`) archives are both read.

- `inspect` reports `container` (`gmad` / `lzma`), `stream_size` (file size, or the declared
  decompressed size; `null` if undeclared), `complete` (all contents present) and `crc_trailer`
  (the optional 4-byte archive CRC is there).
- `verify` decodes everything and also reports `crc_trailer` and, for LZMA, `lzma_gmod_footer`.
  A damaged LZMA container (cut stream, wrong footer, bytes after it) is a format error: exit 2.
- `scan` reads headers and indexes only. It counts `parsed`, `lzma`, `without_crc_trailer` and
  `with_trailing_data`, and fails only archives whose contents or trailer are cut short.

Exit codes: `0` ok, `1` a check found problems (bad CRC, trailing data, failed archives in a scan),
`2` bad usage or unreadable / malformed input, `3` internal error.

Output is UTF-8. JSON strings come from `nl::json::quote`: invalid UTF-8 bytes in archive paths are
shown as U+FFFD, never passed through raw.
