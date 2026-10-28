# On-disk layout (game side)

What the loader adds to a Garry's Mod install. Everything except `bin\win64\winmm.dll` is created
by the loader itself and listed in its journal, so it can all be removed again.

```
GarrysMod\
├─ bin\win64\winmm.dll                     the bootstrap (installed by the user or install-loader.ps1)
├─ native-loader\
│  ├─ config.json                          user policy: allowlist, switches, options (the user writes it)
│  ├─ state.json                           journal (schema 1, below): what the loader placed, with SHA-256
│  ├─ lock                                 held open by the deployer that is running (one at a time)
│  ├─ disable                              optional empty file: loader stays a pass-through
│  ├─ packages\<id>\<version>_<gen>\...    payload folders, never changed once placed, e.g.
│  │                                         ...\rtx-remix-runtime\1.6.1+gmod.20261025_3\runtime\d3d9.dll
│  ├─ staging\<transaction>\...            extraction in progress (deleted at the end of every run)
│  ├─ backup\<gen>\<path>                  root files generation <gen> replaced or removed: the
│  │                                         previous generation's copies, kept for rollback
│  ├─ bootstrap-install.json               the bootstrap's install receipt (install-loader.ps1)
│  └─ logs\loader.log                      start-up step log (rotated)
├─ rtx-remix\mods\<mod>\...                root files from packages (journaled)
├─ rtx.conf, dxvk.conf, user.conf          the user's own Remix configs (top layers; never overwritten)
└─ garrysmod\
   ├─ lua\bin\gmcl_*_win64.dll             binary modules from packages (journaled)
   ├─ cfg\...                              create-only files from packages (journaled)
   └─ data\native-loader\status.json       written each start for the Lua companion (M4)
```

`nlctl uninstall` (or [`uninstall-loader.ps1`](../tools/uninstall-loader.ps1.md)) removes everything
the journal lists, then the journal and the lock; `config.json`, the receipt and the logs stay
unless `uninstall-loader.ps1 -RemoveConfig` removes the whole `native-loader` folder. How the
deployer changes these files is [ADR 0007](decisions/0007-transactional-deployment.md).

## config.json (schema 1)

Implemented by `nl::config` (`loader/core/src/config.cpp`). Check what the loader would do with
`nlctl plan <game root>`.

```json
{
  "schema": 1,
  "enabled": true,
  "allow": {
    "workshop": ["3600000000"],
    "local": ["garrysmod/addons/rtx-remix-runtime.gma"],
    "dev_folders": ["D:/dev/rtx-remix-runtime"]
  },
  "remix": { "enabled": true },
  "patch_sets": { "require_insecure": true }
}
```

| Key | Default | Rule |
|---|---|---|
| `schema` | required | the integer `1` |
| `enabled` | `true` | `false`: nothing is activated |
| `allow.workshop` | `[]` | Workshop item ids **as strings** (large numbers lose digits in some editors), no repeats |
| `allow.local` | `[]` | `.gma` / `.bin` archives, relative to the game root or absolute |
| `allow.dev_folders` | `[]` | unpacked package folders (with `native/manifest.json`), relative or absolute |
| `remix.enabled` | `true` | `false`: runtime packages stay planned but no runtime is loaded (vanilla rendering) |
| `patch_sets.require_insecure` | `true` | in-memory patch sets (M5) only with `-insecure` |

- `allow` is the native-code allowlist ([ADR 0003](decisions/0003-native-trust-allowlist.md)).
  Nothing else is opened as a package; without a config file nothing is allowlisted.
- Strict JSON; **unknown keys are errors** (a typo such as `"alow"` stops the loader instead of
  silently allowing nothing or something else). An invalid file leaves the loader inactive.
- Which allowlisted package wins when several qualify: [ADR 0006](decisions/0006-package-precedence-and-planning.md).

## state.json (schema 1)

The deployer's journal, implemented by `nl::journal` (`loader/core/src/journal.cpp`); `nlctl status
<game root> --json` prints it. Written only by the deployer, atomically (temporary file, flush,
rename). It is parsed as strictly as a manifest (unknown keys, unsafe paths and paths outside the
folders the loader manages are errors), and a journal that does not parse stops every deployer
command, which then changes nothing. Its paths follow the path rules of
[PACKAGE_FORMAT.md](PACKAGE_FORMAT.md), with one difference: they may be up to 4,096 bytes long,
because the loader puts its own folders in front of package paths.

| Key | Meaning |
|---|---|
| `schema` | the integer `1` |
| `loader` | the loader version that wrote it |
| `next` | number of the next transaction and generation (never reused) |
| `current` | the deployed generation, or `null`: `generation` (its number), `packages`, `files` |
| `previous` | the generation `rollback` returns to, or `null`; same shape |
| `previous_backup` | `native-loader/backup/<gen>`: where the previous generation's root files are that `current` replaced or removed; empty if none |
| `retired` | files waiting to be deleted, each only while it still matches its record; one that cannot be deleted yet (read-only, open elsewhere) stays for the next run |
| `dirs` | folders the loader created; each is removed once empty |
| `hold` | after a rollback, the packages it rolled back from (`id@manifest_sha256`). While the plan (before any package is re-planned as broken) names exactly these, apply deploys nothing; the hold ends when it names anything else. `null`: no hold |
| `pending` | a transaction that has not committed, or `null`: `transaction`, `action` (`apply`, `rollback`), `steps` (`make_dir` / `move`, each with its hash); the next run undoes it |

A package record: `id`, `version`, `manifest_sha256` (the identity of that package version),
`source` (`dev_folder`, `local`, `workshop`), `location`, `payload` (its payload folder, or empty)
and `remix` (the manifest's `remix` section for the runtime, which M4 activates; else `null`).

A file record: `path` (relative to the game root, `/`-separated), `package`, `sha256`, `size`,
`mtime` (last write time when placed, FILETIME units) and `adopted` (`true`: the file was there
before the loader with the right content; the loader never moves or deletes it).

## Off switches (any one)

| Switch | Effect |
|---|---|
| Launch option `-nonativeloader` | Pure pass-through for this launch |
| Environment variable `NATIVE_LOADER_DISABLE=1` | Same |
| File `native-loader\disable` | Same, until the file is deleted |
| Delete `bin\win64\winmm.dll` | Loader gone; deployed files stay inert until `uninstall-loader.ps1` removes them |
