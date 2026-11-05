# R19-R report: the runtime's review findings

The brief is [R19-plan.md](R19-plan.md), "R19-R: the runtime"; the findings are in
[R19-review.md](R19-review.md) (H1) and, with every verdict, in the main checkout's
`out/review-final/` (`task-mw40igsn-lqi299.md`, `task-mw40jm2u-u90jd7.md`, `verdicts.md`).

**Who did what.** Claude (the R19-R part), in the fork tree `out/worktrees/r17/out/runtime-src` on branch
`claude/r19-review-fixes` and in this worktree on `r19-runtime`. No game was started.

**What it makes.** One fork commit, `51cf1b8b` (built as `248fa6ee`, the same tree) on 0032 (`e095f29a`), exported alone as
`runtime/patches/0033-Bound-the-DDS-readers-and-fix-the-review-s-other-run.patch`
(`format-patch -1 --start-number 33 --binary --no-signature --zero-commit`, absolute `-o`; patches
0001-0032 are untouched). `runtime\build_runtime.ps1` built `d3d9.dll` from it and imported it into
`packages/runtime`; `runtime/base.json` `packaged` and `runtime/README.md` record it. All of this is commit
`c3699ff` on `r19-runtime`; this report is the next one.

## The findings

| ID | Verdict | Outcome |
|---|---|---|
| H1 | high, confirmed | fixed |
| F-01 | low | fixed |
| F-02 | false positive | no change |
| F-03 | low | fixed |
| F-04 | low | fixed |
| F-05 | low, confirmed | fixed |
| R-01 | low | fixed |
| R-02 | low, by design | by design; the option's description reworded |
| R-03 | low | fixed |

### H1: the DDS readers

**What happened.** Every DDS a loaded mod references is read when the mod loads, so a Workshop item
could hand the runtime any header.
- The partial loader (`DdsFileParser` in `rtx_asset_data_manager.cpp`) took `MipMapLevels` unchecked and
  wrote one size per level into `std::array<size_t, 16>`; the only guard was an `assert`. 17 levels
  overwrote the data size and the `FILE*` it later closes, 18 and more the object's vtable and the heap;
  2^31 read as a negative count. The size check multiplied `int` layer and face counts.
- GLI's fallback (`gli::load_dds`) copied `Texture.size()` bytes, as the header claims, from a buffer as
  large as the file. Its own texture cache (`gli/texture.hpp:289-290`) also holds 16 levels, so a header
  past 16 overflowed it too.

**Found on the way (same class, fixed with it).**
- `GliTextureData` called `gli::load`, which tries a file as DDS, then KMG, then KTX
  (`gli/core/load.inl`); the KMG and KTX readers copy what their headers claim. `findAsset` admits
  `.dds` names only, so the fallback now calls `gli::load_dds`.
- An empty file made GLI's reader call `strncmp` on a null pointer.
- A volume's level sizes left out the depth, while the uploader reads every slice
  (`dmaCopyDataToStaging`): a short volume was read past what was checked.
- Both readers measured files with `ftell` (a `long`, -1 from 2 GB).
- The mapped file was assumed to be as long as when it was parsed (an `assert`): a file replaced by a
  shorter one would be read past its mapping.

**The fix.** One check for both readers, `gli::detail::dds_check_layout`
(`include/gli/core/load_dds.inl`), runs on the headers before a byte of the data is read. It refuses:
- a format GLI does not know (its block size used to be read from before GLI's format table);
- a side of 0 or past 65536 (twice the largest image a GPU makes; it keeps every size GLI computes in
  `int`), and a volume of depth 0;
- more than 16 mip levels, or more than the sides allow (`floor(log2(longest side)) + 1`);
- no cube face, or more than 2048 array layers;
- data that does not fit in the file. Level, face and total sizes are summed in 64 bits with overflow
  checks; a volume's levels count their depth.

A mip count of 0 with the flag set reads as 1, as Microsoft's DDS loaders read it. That is a deviation
from the brief's "below 1 is rejected": it is just as safe, since the size check then holds that one
level to the file, and it keeps files that D3D's own loaders take. 2^31 and every count over 16 are
rejected.

A file with more levels than its sides allow (a malformed chain, which Vulkan does not allow an image to
have) is now refused, as the brief says; before, it became an invalid image. Should a mod turn up with
such files, the alternative is to read only the levels the sides allow, which is as safe.

**The partial loader** moved to `src/dxvk/rtx_render/rtx_dds_file_parser.h` so the unit test runs it.
It measures the file in 64 bits, checks every `fread`, records nothing unless the whole layout fits,
places nothing for a layer, face or level the file lacks (`data()` returns null, which the uploader
handles), and maps a file only while it still holds all of the checked data.

**GLI's reader** reads each header only when the buffer holds it, checks the layout, and copies only when
`Texture.size()` fits in what follows the headers. Its file reader refuses empty files, files `ftell`
cannot measure and short reads.

**Test.** `tests/rtx/unit/test_dds_reader.cpp` (new) writes crafted files and runs the real parser inside
an object fenced by canaries, `gli::load_dds` from memory and from the file, and `dds_check_layout` in a
fenced struct. Rejected without a write outside the object and without a texture:
- mip counts 17, 18, 32, 2^31 and 2^32-1 on 64x64, 17 on 65536x1, 3 on 2x2;
- widths and heights of 0, a volume of depth 0, a side of 65537;
- files short by 1 byte and by 54 of 64, a header cut short, a DX10 header cut short, 3 bytes, an empty
  file, a wrong magic number;
- array sizes 2049, 65536, 2^31 and 2^32-1, and 2048 layers with 2047 layers of data;
- a cube map with no face, an unknown DXGI format.

Accepted with the right layout, and GLI's copy equal to the file: RGBA8 with 3 mips (with and without
trailing bytes), legacy DXT1 with a mip count of 0, a BC1 array of 3, an R8 cube map, an R8 volume
4x4x4 with 3 mips, R8 32768x1 with 16 mips, and 2048 layers.

**Not changed.** A texture the GPU cannot create (a side past `maxImageDimension2D`, or a volume, which
the texture manager makes as a 2D image) still fails `vkCreateImage` when its larger mips stream in. This
is a `DxvkError` on the render thread, not a memory error. It needs a decision: refuse such textures, or
cap their mips. It is listed under open issues.

### F-01: string options read beside the render thread

**What happened.** `getValue()` holds the update mutex only until it returns a reference. A reader on
another thread then reads the string after the mutex is released, while dxvk-cs can re-resolve it (a copy
assignment that frees the old buffer).

**The fix.** `RtxOption::getCopy()` (`rtx_option.h`) returns a copy made under the update mutex; a
trivially copyable option keeps its lock-free read. The readers that use it:
- `RemixGui::InputText` (`rtx_imgui.h`): every text box bound to a string option, among them the Nsight
  paths and the camera sequence path.
- The texture menu's legacy-emissive and thin-wall strings, read every frame while their drags set them
  (`dxvk_imgui.cpp`).
- The capture menu's stage name (`dxvk_imgui_capture.cpp`), and `getCaptureInstanceStageNameWithTimestamp`
  with its timestamp, which the menu calls every frame while its name box sets the name
  (`rtx_game_capturer.cpp`).
- The menu language (`rtx_fork_i18n.cpp`) and the fallback-mod list (`rtx_fallback_mods.h`, which the menu's mod rescan reads on the game's
  thread).

**Found on the way.** The capture name box copied `strlen` bytes of the configured name into its 64-byte
buffer; it now copies at most 63.

**By design, unchanged.**
- Trivially copyable options stay lock-free: patch 0029's rule. They are overwritten in place at a fixed
  address.
- The splash's welcome message and key binds, and the capture timestamp in the menu's own `setValue`, keep
  their reads. Nothing edits those options at run time. Naming them through `xxxObject()` in a menu file
  would also make `i18n/tools/update_strings.py` list their descriptions as menu text (three new
  untranslated entries).

**Test.** `test_rtx_option_threads` gains `test_stringReadsDuringResolve`: the main thread sets a 300- or
500-character string and reads it with `getCopy()` for 2 s while a render thread resolves; no read is
torn.

### F-02: a false positive

No change.

### F-03: a shared texture and the preload rule

**What happened.** The asset cache gives every request for a file the texture made for the first one. A
material that preloads (`preload_textures`) could get a texture another material made to stream, and its
first draw then showed the smallest mips.

**The fix.** The rule is in `rtx_texture_budget.h`. Each request has a strength, weakest first:

| Strength | Request |
|---|---|
| `Streamed` | a material without `preload_textures` |
| `AtFirstDraw` | a material's preload, R13-F |
| `Yielding` | a material's preload with `preloadOnFirstDraw` off |
| `Pinned` | dome lights, the Remix API, or a texture too large to stream |

- `preloadTextureAsset` stores the strength a texture is made with (`m_preloadStrength`).
- A cache hit with a stronger request raises the texture's atomic `m_preloadRequest`, from any thread.
  So does a second thread that made the same asset's texture at the same time.
- The texture's next `addTexture` (render thread) applies a raised request. It makes the texture a
  preload drawn for the first time: R13-F's `loadPreloadOnFirstDraw` pins it and stages every mip
  synchronously, before the frame renders. A `Pinned` request also stops it from giving way under
  pressure.

**Behaviour.** The upgrade applies at the texture's next draw, by any material that uses it. A
`Yielding` request (which loads with its mod when the texture is new) thus waits for that draw too; the
texture is whole when drawn either way. No shipped mod shares a file between a preloaded and a streamed
material (the verdict), so this changes nothing visible today.

**Test.** `test_texture_budget_pressure`: the strengths, and that `raisePreloadRequest` takes the
strongest request and never lowers it.

### F-04: the middle deck's patch probes

**What happened.** `marchEchoDeck` skipped the deck when the patch mask was empty at the ray's entry,
middle and exit. These do not bound the mask between them. At the default 14 km patches the verifier
found nothing visible lost; at the 2 km minimum about 1.8 % of horizon rays lost a patch.

**The fix** (`cloud_march_common.slangh`):
- The mask is probed along the ray's crossing at most a quarter of a patch apart (the shortest
  wavelength of its field), from 3 to 16 probes (`kEchoPatchProbeMax`).
- The deck is skipped only when every probe is empty.
- Each step's cover is interpolated between the probes either side of it, in a local array.

**Cost.** A crossing within half a patch keeps R18's three probes, at the same places, so most of the sky
costs what it did:
- At the default 14 km that is partly cloudy's whole sky above about 5 degrees.
- Grazing rays take up to 6 probes in partly cloudy (0.6 km deck) and up to 13 in overcast (1.5 km deck,
  crossings to about 40 km), against R18's 3.
- One probe is a 3-octave 2D gradient noise, no texture fetch.
- At the 2 km minimum the longest crossings are probed about 1 km apart (the cap), not 0.5 km.

Not measured: no game was started. The comparison for the integrator is below.

### F-05: the middle deck's moon shadows

`sampleCloudSunOpticalDepth_localSlab` (the deck's two moon-shadow taps, 0.8 and 1.6 km toward the moon)
now reads the deck's patch mask at each tap, instead of the shaded sample's cover. A tap between patches
skips its density fetch, as the view march skips such steps. `echoDeckPatchMask` moved above it,
unchanged. Cost: two mask evaluations per dense moonlit sample, by night only, less the density fetches
the empty taps skip.

### R-01: config files saved through a link

**What happened.** A config file that is a link (a symbolic link, or a file with several hard links) is
rewritten in place to keep the link (ADR 0044). A failure or an exit halfway through the write left it
incomplete, with nothing that held the previous contents.

**The fix** (`config.cpp`):
- Before the rewrite, the previous contents are read whole (at most 64 MiB) and written to a flushed
  backup beside the file, `<file>.bak-<process>-<tick>-<n>`. The log names it before the write starts.
- A failed rewrite puts the previous contents back, and the save fails with "Previous file kept".
- A completed save deletes the backup and the staged copy.
- If the restore fails too, the log names the backup (previous contents) and the staged copy (new
  contents).

**Test.** `test_rtx_option` gains `test_configSaveThroughLink`: a save through a hard link reaches the
file's other name, and leaves neither a staged copy nor a backup.

**Not done.** There is no automatic recovery at the next start. After a crash mid-write, the backup and
the staged copy stay beside the file, named in the log.

### R-02: the eye-white brightness

The multiplier scales the scene-wide adaptive emission. That is ADR 0088's design: only eye materials
carry the input (the automatic eye whites, rpai's eye classes). The option's description now says so:
"Session-only brightness multiplier (0..2) for all scene-adaptive emission: automatic eye whites and every
material with emissive_adaptive_intensity (in the GMod package, the eye materials)." `RtxOptions.md` is
regenerated (`test_documentation` passes). The option is not shown in a menu, so the catalogs do not hold
it.

### R-03: non-finite floats

`Config::parseOptionValue(float)` refuses `nan`, `inf` and the like (`std::isfinite`), as it refused
other invalid text. The float vectors parse into a copy and keep it only whole, so a refused component
leaves the old value instead of half of a new one. This covers config files, environment variables and
the Remix API's `SetConfigVariable`.

**Test.** `test_rtx_option` gains `test_configNonFiniteValues`.

**Not covered.** A value typed into a developer-menu float box: ImGui parses that text itself. The
verdict placed the fix in the parser.

## Build

- **The build.** `runtime\build_runtime.ps1 -Fork <tree> -Worktree <tree>`, with the script's defaults
  (4 jobs). It verified the tree (base `c6b48ed1` with the 33 patches, tree `e6a5b873`), reconfigured for
  the commit's version, ran both passes, imported the DLL and wrote `packaged`.
- **The DLL.** `d3d9.dll` is 417,070,592 bytes, SHA-256
  `34287de8edcbffea4607171cf5f1f8ca0252360af258a767905f42e64853bea0`, version `remix-main+248fa6ee`.
- **The import.** Into `packages/runtime/files/d3d9.dll.xz` (61,321,840 bytes xz, one new LFS object)
  and `files.json`; `base.json` `packaged` names the DLL and the 33 patch hashes.
- **Time.** A full recompile after the shared headers changed took about 2 minutes on this machine
  (`out/r19r/build-iter1.log`: 251 objects, both cloud shaders).

## Tests

**The fork's unit tests** (`meson test --no-rebuild` in `_CompRelease_x64`, on the imported build): 34 of
35 pass, among them:
- `test_dds_reader` (new), with 34 crafted files;
- `test_rtx_option` (new: non-finite values, a save through a hard link);
- `test_rtx_option_threads` (new: string reads during resolves, over 3 million reads in 2 s);
- `test_texture_budget_pressure` (new: preload strengths);
- `test_documentation` (`RtxOptions.md` regenerated).

The 35th, `test_remix_categories`, cannot load `d3d9.dll` under meson: its definition leaves the packman
dependency folders off `PATH`, as R13-B and R13-D found. Run with them (`out/r19r/run_categories.ps1`), it
exits 0.

**The runtime's record.** `runtime\build_runtime.ps1 -Verify` after the import: the tree is the base with
the 33 patches (tree `e6a5b873`), and its built `d3d9.dll` is the packaged one (`34287de8`).
`python -I tools\inputs.py verify --part runtime --deep`: 11 parts checked, 0 problems.

**The catalogs** need no change. Running `i18n/tools/update_strings.py` produces no content change in
`remix.pot` or the six `.po` files: no new menu text, and the menu files' strings keep their lines. Its
`--check` compares bytes, so in this CRLF checkout (`core.autocrlf=true`) it reports the template out of
date at 0032 as well.

**This repository.** `tools\test.ps1 -SkipNative` passes on the final state (no C++ here changed): the
conventions (`check_repo.py` holds `runtime/` to the `packaged` record), and 28 + 25 + 578 Python tests
(1, 1 and 7 skipped). `python -I tools\weather_presets.py --check`: up to date, since no weather field or
preset changed, so the companion's table stays as it is.

## For the integrator

- **Imports.** Done here: `d3d9.dll` in `packages/runtime`, `runtime/base.json` `packaged`. No pins, no
  other part. The fork branch `claude/r19-review-fixes` holds the commit, and it is not pushed.
- **Strings to translate.** None.
- **The patch's author** is SheepyLord with the fork's git identity (its configured noreply address),
  as the earlier patches. The brief named another address; the integrator corrected the commit's author
  (`248fa6ee` became `51cf1b8b`, the same tree) and exported the patch again: only its `From:` line changed.
- **In-game checks** (PoC, any RTX session unless named):
  1. **Mods still load their textures.** The package's mods, ToPBR's generated materials (`~gmod_topbr`)
     and an imported character show their textures as before. ToPBR and the material editor's bridge
     write the full mip chain, `floor(log2(longest side)) + 1` levels, which the new check accepts. The
     log shows no new `Corrupted DDS file` or `DDS file is shorter` warnings, and no
     `The GLI library was used` lines that were not there with R18.
  2. **The sky against R18 (F-04, F-05).** Repeat R18's method (RESEARCH.md, "R18", "Cost at
     3840x2160": the same spawn and views, about a second of frames before each shot, R18's package in a
     second session). States and checks:
     - Partly cloudy at 15 h: toward the sun, away from it and overhead, plus a view toward the horizon
       across the middle deck's patches. Frame times within about 0.2 ms of R18, and the middle deck
       0.15-0.3 ms where drawn (the deck's cover set to 0 as the off case, as R18 did). Patches near
       the horizon stay as the camera turns, with no popping.
     - Overcast at 14.5 h, the view away from the sun. Here grazing rays take the most probes (up to 13);
       expect R18's 13.3 ms within noise.
     - Partly cloudy at night with a low moon (moon 0 below about 22 degrees, a bright phase). The middle
       deck's cloudlets at a patch's edge toward the moon are now lit; before, the clear air beside them
       shadowed them as if it held cloud. Cloudlets behind another patch, seen from the moon, are
       shadowed by it.
     - Optional: `rtx.atmosphere.cloudLayer2PatchSizeKm = 2`. Horizon patches no longer drop out (the
       verifier's 1.8 % of rays).
  3. **Menus** (Alt+X, developer menu): the Nsight path boxes, a texture's legacy-emissive strength drag
     and its colour, the capture name box (type, then click away), and the language selector work as
     before.
  4. **Config through a link** (optional): with `user.conf` as a hard link, Save Settings reaches the
     other name and leaves no `.bak-` or `.tmp-` file.

## Proposed lines for the shared docs

**CHANGELOG** (`## [Unreleased]`):
- Runtime patch 0033: a DDS file in a Remix mod can no longer corrupt the game's memory. Both of the
  runtime's DDS readers check a file's mip count (at most 16, and what its size allows), sides, layers,
  faces and data size against the file before reading it. The fallback reads DDS only, and refuses empty
  and short files (R19 H1).
- Runtime: option strings that the menus read on the game's thread are copied under the update mutex
  (text boxes, the texture menu's emissive and thin-wall strings, the capture name, the language)
  (R19 F-01).
- Runtime: a texture that two materials share loads as the stronger of their preloads, so a preloaded
  material is whole at its first draw even when a streamed material named the file first (R19 F-03).
- Runtime: the middle cloud deck finds its patches along grazing rays (probes at most a quarter of a
  patch apart), and its moon shadows follow its patches (R19 F-04, F-05).
- Runtime: a config file saved through a link keeps a backup of its previous contents until the rewrite
  is complete; float options refuse NaN and infinities (R19 R-01, R-03).

**RESEARCH.md** (a new section "R19: the runtime's review fixes"):
- **GLI** (`include/gli`):
  - `gli::load` (`core/load.inl`) tries a file as DDS, then KMG, then KTX, whatever its name; the KMG and
    KTX readers copy what their headers claim.
  - GLI's texture cache keeps 16 levels in fixed arrays (`texture.hpp:289-290`).
  - `GLI_ASSERT` is empty in release builds (`type.hpp:24-28`), and so is the runtime's `assert`
    (`NDEBUG`, `meson.build:125-126`).
  - `get_dds_format` returns `FORMAT_INVALID` for an unknown format, and `block_size(FORMAT_INVALID)`
    reads before the format table.
- **The texture manager** makes every replacement texture a 2D image (`ManagedTexture::imageCreateInfo`)
  at the extent of its first loaded mip (`allocDeviceImage`). A side past the GPU's limit therefore fails
  only when the larger mips stream in.
- **The catalog extractor.** `i18n/tools/update_strings.py` counts an option's description as menu text
  when its `xxxObject()` accessor appears in any file that draws ImGui. Its `--check` compares bytes, so
  it reports `remix.pot` out of date in a CRLF checkout.
- **The fork's `.gitignore`** ignores `tests/rtx/unit/*` but a few names; new test sources need
  `git add -f`, as the earlier patches' tests had.
- **Build time.** A change to `rtx_option.h` recompiles 251 objects in about 2 minutes with 4 jobs on
  this machine.

## Open issues

- A replacement texture the GPU cannot create (a side past `maxImageDimension2D`, or a volume) fails when
  its larger mips load; deciding between refusing it and capping its mips is the user's call.
- R-01 has no automatic recovery after a crash during an in-place save; the backup stays beside the file.
- R-03 does not cover a NaN typed into a developer-menu float box.
- As patches 0024-0032 did, 0033 does not update the fork's `docs/fork-touchpoints.md` (the upstream
  Remix Plus project's touchpoint list).
