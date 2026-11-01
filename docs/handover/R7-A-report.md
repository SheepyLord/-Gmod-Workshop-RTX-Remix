# R7-A report: MMD alpha

Implemented on `r7-alpha` in `b47aefd` (runtime and ADR) and `8fb7a11` (companion and probe).
The runtime builds and all functional tests pass. **The required repository gate still exits 1:**
its existing provenance check requires importing the rebuilt runtime, which this task explicitly
forbids. `runtime/base.json`'s historical `packaged` record and `packages/**` remain unchanged.
The requested permission to extend the checker for a verified, unimported build was not answered;
no checker exception or false packaged provenance was introduced. Claude must import the runtime
on integration, or approve that separate checker change, before claiming the whole gate passes.

Patch [0017](../../runtime/patches/0017-Apply-scoped-MMD-alpha-consistently-to-ray-materials.patch)
adds saved `rtx.mmdAlphaTextures`, joined with NoSave
`rtx.gmod.mmdAlphaTexturesForSession`, and `rtx.mmdAlphaCutoff` (default **0.5**). D3D9 category
snapshots, preserved-draw invalidation, external submission tagging and USD category metadata are
covered. Published Remix SDK bit assignments remain unchanged.

For tagged draws using legacy alpha, the alpha test uses the cutoff instead of Source's fixed
reference, preserving the comparison operator. Authored replacement alpha and forced cutout/hair
categories retain precedence. Blended opacity **at or above 0.5 becomes 1** in the shared opacity
evaluator, after texture/vertex operations and blend inversion, before lighting. Primary,
visibility/shadow, PSR, indirect throughput and OMM baking therefore see the same promoted value.
Lower opacity retains the existing blend/stochastic behavior; the global 0.79 threshold is unchanged.

The cutoff occupies unused surface bits, at 1/2048 resolution including exact 0.5; the GPU surface
stays 256 bytes. Explicitly initialized alpha state includes the flag/cutoff in OMM cache identity;
the hash-source structure stays 128 bytes. MMD OMMs always evaluate the required texture/vertex
operations, and alpha-category/cutoff changes invalidate material history. Blended/cutout geometry
remains nonopaque, preserving ADR 0048's traversal rejection and cached/shared BLAS flags.
The decision is [ADR 0080](../decisions/0080-mmd-alpha-texture-category.md).

The [companion](../../companion/nativeloader/lua/autorun/client/nativeloader_mmd_alpha.lua.md)
discovers loaded `mmdhl.assets` public material names and registers their real `mmd/` base-texture
hashes. It handles late mounts, uploads, API arrival, revisions, tracking/write refusals and asset
removal; excludes shared fallbacks and foreign bindings; sorts/deduplicates hashes; bounds discovery
to 128 slots and lookups to 16 names per frame, with publication at most four times per second.
It writes only the NoSave list. No new translated opt-out is needed for this scoped fix.

**No hotloader change is required.** Read-only inspection confirmed Columbina's public mask VMT
binds `mmd/t/2c7b2c8505cc6a6e`. The imported hotloader's soft copies bind that same base texture;
its soft pass must remain to retain coverage below 0.5. The imported part was not edited.

Validation:

- Fork Release: **29/29 unit tests**, including the new alpha boundary/precedence, snapshot,
  packing and OMM identity checks; generated options documentation and USD schema also pass.
- Companion: **16/16 LuaJIT scenarios**, including a 4,096-part lookup-budget fixture.
- Repository Release: **25/25 CTests**, **455 Python tests, two skips**. The command
  `tools/test.ps1 -Config Release` fails only the packaged-runtime provenance convention described
  above. The companion suite runs separately with `python -m unittest discover -s companion/tests -v`.
- The QA probe compiles with LuaJIT. Exact source/submodule/clone verification passes, both build
  passes complete, and eight representative ray/OMM SPIR-V binaries are verified embedded in the DLL.

Built DLL (397,842,944 bytes), runtime identity **`remix-main+e9460a14`**, Remix API **0.1000.1**:

```text
H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r7-alpha\out\runtime-src\_CompRelease_x64\src\d3d9\d3d9.dll
SHA-256: 50856d6205a7ab44580d2940d6fe9bc4926946380c73efd41eda70953d915f4a
```

Claude must also import the updated **text** schema from
`out/runtime-src/_CompRelease_x64/src/usd-plugins/RemixCategories/generatedSchema.usda` to the
runtime part's `files/usd/plugins/RemixCategories/generatedSchema.usda`
(SHA-256 `56d12d20d636902299d85ecb0db3ad494a2714f16c82bdb1d6a48149969fc2ac`).
The schema plugin's C++ implementation and public ABI are unchanged. Include the companion in the
fixes-part rebuild. Source commit is `e9460a14efab77149924ce2f7004028c5f09872a`, tree
`0ead7fd10deb5704ca75cd9d6ca471415f922edc`, base `c6b48ed1` plus patches 0001-0017.
The isolated build uses MSVC 19.44, Release/Ninja, optimization 3, release DLL CRT, Tracy/shim off,
`download_apics=false`, and four Ninja jobs. Dependencies came from the wrapper's clone setup and
local cached SDKs; its own fork checkout was left alone.

Claude's in-game acceptance remains:

1. Load Columbina, including a late load; `nativeloader_mmd_alpha_status` must include
   `0xfb1616f217669e2e`. Check white lattice bars, holes/soft panes, and matching shadows at noon/dusk.
2. Compare mask-texture plates and the alpha ramp in fresh processes, untagged then with
   `NL_ALPHA_MMD = true` in the [probe](../../tools/qa/alpha_probe.lua.md). Tagged tests should cut at
   0.5 and tagged blends become opaque at equality. Verify fractional opacity below the cutoff stays soft.
3. Repeat cold with OMM disabled, then enabled through baking; compare query/trace, PSR/reflections
   and indirect paths, including the supported NRC/SHARC/WBOIT variants. Retain layered-face regression QA.
4. Check ordinary map glass, props, cutouts and replacement materials remain unchanged. Exercise
   category add/remove and cutoff changes with static cached geometry/shared BLAS after OMM baking.
5. Check `mmdhl_soft_alpha` on and off: soft detail should remain with it on; the cutout-only path
   must still show the lattice with it off.

Limits: no game/GPU acceptance was run. This is a texture-hash category: another draw sharing the
same image hash inherits it. Below-cutoff transparency retains Remix's existing approximations.
Capture metadata still has the existing byte-sized alpha-reference field; live evaluation uses the
exact packed cutoff. No game install, Steam file/settings, existing Remix user.conf, package input,
Workshop item, main branch, push, merge or tag was changed.

Local receipts are under `out/tmp`: `r7-runtime-built.json` (artifact/configuration/patch hashes and
shader embeddings), `r7-runtime-build-final.log`, `r7-runtime-verify.log`,
`r7-runtime-unit-tests.log`, `r7-companion-tests.log` and `r7-repo-tests-final.log`.
