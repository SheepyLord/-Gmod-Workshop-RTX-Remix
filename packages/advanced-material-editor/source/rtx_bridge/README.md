# Advanced Material Editor native RTX bridge

This directory contains the source for an optional native compatibility
provider. It is not a prebuilt binary. Its primary integration target is the
64-bit `RTXFixesBinary` module shipped by garrys-mod-rtx-remixed; an
experimental standalone `gmcl` target is included for development builds.

The provider exposes `AdvMatRTXBridge` protocol 1 to client Lua and persists
legacy texture-hash replacements as immutable, content-revisioned RTX Remix
USDA layers per exact captured hash. `mod.usda` is the sole activation ledger;
an apply stages every new dependency and swaps that root once, so a failed
multi-hash update cannot leave a split active version. Exact-hash clears cannot
remove a newer hash layer for the same Source material. Its output is strictly
confined to:

```text
<Garrys Mod>/rtx-remix/mods/!advanced_material_editor/
```

It never reads, modifies, indexes, or deletes `~gmod_topbr`.

Protocol 1 includes an optional reversible-preview extension: `livePreview`
and `reversiblePreview` are advertised together with `RestorePreview`.
Preview overlays and their saved rollback ledger share one atomic root update.
Closing the editor restores current saved values; module unload also restores
them, and initialization recovers an interrupted preview. Older binaries remain
save-only. Calls are synchronous. A DDS is validated and copied as it is, never
decoded. Validation checks the header against the file: a known format, a mip
count the dimensions allow (16 at most, all the RTX Remix runtime records), sane
faces and array layers, and every byte the header describes present; a copy made
earlier gets the same check before it is reused. A DDS may be up to 512 MiB and
16384 pixels per axis, enough for RTX
Remix enhancement maps such as rpai's 4096 px BC7 maps and its 11059 x 8847
Firefly sheet. An image the writer decodes and mips itself (PNG, JPEG, BMP,
TIFF, GIF, and so every map with bake operations) keeps the conservative
32 MiB / 2048-pixel limits, with at most four operations per map.
`Capabilities()` reports the DDS limits as `maxTextureBytes` /
`maxTextureDimension` and the decode limits as `maxDecodedTextureBytes` /
`maxDecodedTextureDimension`. A source spelled as a network, device or
drive-relative path (`\\host\share`, `//host`, `\\?\`, `\\.\`, `\??\`, `C:file`)
is refused before any filesystem call. A source lexically outside every allowed
root and outside `rtx-remix/mods` is refused the same way (one error code,
before `canonical`) whether or not it exists, so the error cannot reveal whether
a file is on the player's PC. A source must resolve inside the game folder,
except one read through a folder in `rtx-remix/mods` that is itself a link or
junction to a mod kept elsewhere: it may resolve anywhere inside that link's
own target. Unchanged
content-addressed textures are reused before image decoding, a source whose
size and write time have not changed since it was read is not read again while
its copy exists (previews re-send every map), and unchanged
commits do not rewrite their profile/root layers. Each apply/clear first prunes
files outside the current root ledger, and failure paths repeat that cleanup. A
successful edit retains only its immediately superseded transaction until the
next call, bounding same-session churn without deleting a dependency before its
replacement root is durable.

Protocol 1 also requires `ClearAllOwned` and advertises
`authoritativeReset = true`. The client invokes it before synchronizing a new
server session so globally persistent Remix layers from a previous server
cannot leak into the new server's server-scoped profile state. Reset atomically
publishes an empty owned root first, then independently retires the complete
`profiles/` and `textures/` generations with contained directory renames. This
deactivates any number of owned hash/legacy layers in O(1) activation work.
Fixed `profiles.retired/` and `textures.retired/` quarantines are replaced on
the next populated reset, so inactive profile and map generations cannot
accumulate without bound. A failure between the two renames is retryable
without republishing an active root.

See [`docs/NATIVE_RTX_BRIDGE.md`](../../docs/NATIVE_RTX_BRIDGE.md) for the API,
security model, integration steps, and current limitations.

## Pure writer tests

```powershell
cmake -S native/rtx_bridge -B out/advmat-rtx-bridge
cmake --build out/advmat-rtx-bridge --config Release
ctest --test-dir out/advmat-rtx-bridge -C Release --output-on-failure
```

The tests do not load Garry's Mod or RTX Remix. `tests/writer_tests.cpp`
exercises validation, deduplicated hash authoring, dedicated-mod containment,
DDS ingestion (crafted headers: too many mips, missing data, bad array sizes,
dimensions and formats, a cached copy cut down to its header), UNC, device and
drive-relative sources refused from their spelling, atomic
transaction publication with deterministic failure injection, reversible
preview, crash recovery, concurrent commits, unchanged-commit cache reuse,
skipping the read of an unchanged source (shown with a file held open without
sharing), the separate DDS and decode limits, maps read through a junctioned (and, where
the host allows symbolic links, symlinked) mod folder and every way out of it
that stays refused, aggregate-layer migration, exact-hash/idempotent clear behavior, and
empty-root-first authoritative reset with bounded profile/texture quarantine
rotation at 64-layer scale. With `ADVMAT_RTX_BUILD_GMOD_MODULE=ON`,
`tests/lua_binding_tests.cpp` also checks the Lua boundary against an in-memory
`ILuaBase`: request strings (hashes, paths, names) are refused by length before
they are copied, and a C++ exception inside an exported function becomes a
`false, "native_exception: ..."` result with the bridge lock released. All
native targets use `/WX` or `-Werror`.

The Lua client may attempt `require("advmat_rtx_bridge")` only after it has
positively detected the RTX runtime. Do not ship the resulting DLL merely
because it compiles: native load failures can crash the game outside Lua's
error handling. Build and smoke-test it against the exact Win64 client and
`garrysmod_common` revision, or integrate the sources into that client's
`RTXFixesBinary`.

The standalone module discovers the game root from the absolute executable
path. It validates a bounded ancestor chain for both `garrysmod/` and
`rtx-remix/`, which handles the RTX client's `bin/win64/gmod.exe` layout. It
does not use the process current directory as a fallback.
