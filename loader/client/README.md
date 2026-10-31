# loader/client

Native client-payload support for this project's allowlisted RTX package. It does not change
sv_allowcslua, widen the native source allowlist, or create a general source-execution API.

| File | Purpose |
|---|---|
| `catalog.h`, `catalog.cpp` | Validate the enabled RTX owner/source, bind the bootstrap module to its journaled SHA-256, and snapshot only owned add-on Lua whose exact bytes match the committed generation |
| `module.cpp` | Menu-realm module entry, active-owned-runtime and committed-journal checks, client-realm lifecycle polling, private catalog callbacks, completion/status and cleanup |
| `bootstrap.lua` | Private client initializer: scoped include/require/file helpers, shared/client autoruns, client entity registration and owned initialization-hook replay |
| `bootstrap.lua.md` | Initializer behavior and side effects |
| `bootstrap_data.h.in` | CMake embedding template for the initializer |
| `CMakeLists.txt` | Static catalog library, native module, script embedding and test targets |
| `tests/` | Synthetic catalog policy checks; see [tests/README.md](tests/README.md) |

The module consumes the existing protected native-loader journal and config through nl_core.
Catalog preparation expects a validated committed generation; normal use refuses absent/pending
journals, disabled policy and an active renderer that is not the package's deployed runtime.
Only package gmod-rtx-remix is accepted. Local and development sources must match their own
allowlist entries; Workshop loading is limited to distribution item 3829070317.

Catalog keys identify an add-on and virtual Lua path. Callback reads are exact map lookups into an
immutable verified snapshot, not arbitrary filesystem reads. Source is limited to 2 MiB per file
and 64 MiB total, with NUL text and case-colliding keys refused. Generic developer automation
rtx_agent and mmdhl/debug.lua is excluded from this multiplayer path. Other community files and
server code remain subject to the original engine APIs.

`secure_render_patch_set` recognizes only the exact SHA-256 fingerprints of the seven reviewed
rendering fixes emitted by tools/package_fixes.py and only for gmod-rtx-remix. Changing a recipe,
adding/removing a patch or using another owner cannot inherit the secure-render exception.
Other memory patches retain their general insecure gate, and config can disable this exception.

The Garry's Mod interface headers are vendored separately under third_party/gmod with their
BSD-3-Clause notice. Build with the normal tools/build.ps1 flow. Development/build/test scratch
belongs under the repository's out directory; no build step installs into a real game.
