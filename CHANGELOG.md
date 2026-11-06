# Changelog

Notable changes to this repo. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the loader's CMake project version once it ships; until then everything is under
`Unreleased`, grouped by milestone.

## [Unreleased]

### R20

- **Readable dupe thumbnails:** suppressed-lighting raster previews use a bounded, restored unlit
  base-map override, with stable cache identities and late-helper handling, so saved props show
  their textures as well as saving without the camera underflow. Complex thumbnails remain a
  flat approximation; world materials and dupe data are unchanged.

- **Native effect rendering:** offscreen alpha canvases keep their native blend/write operations,
  premultiplied transmission filters no longer draw opaque black backgrounds, and changing effect
  alpha avoids static opacity micromaps. Camera tracking distinguishes native 2D, 3D, 3D2D and
  orthographic scopes ([ADR 0122](docs/decisions/0122-raster-canvases-keep-their-native-draws.md));
  the rebuilt runtime also corrects the compiled project fallback link.

- **Automatic Source effect categories:** particles, decals and blended effect meshes receive
  session-only Remix tags from their ordinary Lua APIs and already drawn material metadata,
  preserving effect color/opacity without rewriting saved categories
  ([ADR 0121](docs/decisions/0121-source-effect-categories-for-the-session.md)).

- **Dupe camera tracking:** the RTX guard observes `cam.End` as well as `End2D` and `End3D`,
  so the stock dupe icon's repeated cameras no longer exhaust its tracked stack. Composite 3D2D
  cameras reject incomplete closers ([ADR 0120](docs/decisions/0120-camera-closers-share-the-guards-stack.md)).

- **The repository is now https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix** (renamed by the user
  from `-Gmod-Workshop-RTX-Remix`, now public): every link in the docs, the startup messages, the main
  menu's project link, the Workshop page and the package indexes' origins points at the new name
  (206 links). Runtime patch 0012's compiled-in fallback text keeps the old name until the runtime is
  rebuilt; GitHub redirects it. Plan of the round: [R20-plan.md](docs/handover/R20-plan.md).

### R19

- **The pre-release review's findings fixed; release v0.14.0 with loader 0.14.0** (the user's request;
  [review](docs/handover/R19-review.md), [plan](docs/handover/R19-plan.md),
  [report](docs/handover/R19-report.md)). Codex reviewed the release in eleven parts, independent Claude
  verifiers checked each finding against the code, and every real finding was fixed by seven parallel
  parts:
  - **Content packages come only from subscribed Workshop items**
    ([ADR 0111](docs/decisions/0111-content-packages-only-from-subscribed-items.md)). The loader deployed a
    content package from every Workshop item Steam had installed, and any multiplayer server can make the
    game download an item without a subscription (`steamworks.DownloadUGC`). Now only an item an account
    on this computer subscribed to (Steam's `subscribedby`) is deployed, and a content package an older
    loader deployed from such a download is removed at the next start, like an unsubscribe. A missing or
    unreadable Steam record adds nothing and removes nothing. Allowlisted items are unchanged.
  - **A texture file in a Remix mod can no longer corrupt the game's memory** (runtime patch 0033). Both
    of the runtime's DDS readers check a file's mip count (at most 16, and what its size allows), sides,
    layers, faces and data size against the file before reading it; the fallback reads DDS only and
    refuses short files. The material editor's bridge checks a DDS the same way.
  - **A server's Lua can no longer make the RTX fixes write outside the game or contact another computer**
    ([ADR 0112](docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)). ToPBR's
    output folder stays inside `~gmod_topbr\textures`; texture, VMT and model paths, Remix material and
    light textures, RTX Water's materials and the Remix options that name files must stay in the game's
    folders. A network path (`\\host\share`) made Windows offer the player's login to that host. ToPBR
    and imported game maps work only while the player's `rtx_topbr_enabled` and `rtx_topbr_game_maps` are
    on. The material editor's bridge refuses network, device and drive-relative texture paths before it
    touches the disk, and answers alike for a file outside the game whether it exists or not.
  - **The dance tool works on yourself only** (Character Motion Importer). A player could select another
    player, which hid them and locked their movement until they died. Now only an admin may select, pose,
    build on or dance another player; Force Reset and death unfreeze or show only a player the add-on froze
    or hid; "stop all" stops your own NPC dances; a leaver's dances stop.
  - **A release stays on the Workshop.** After a release uploaded from GitHub (`publish_workshop.py
    --from-ci`), the next commit on `main` no longer uploads a development build over it while the
    packaging inputs are the release's, and `--from-ci` fails when the package workflow has no run for the
    commit.
  - **The RTX guard installs only in an RTX session.** An RTX start holds
    `garrysmod/data/native-loader/rtx-session.txt` until the game exits, so a later start with
    `-nonativeloader` no longer installs the guard from the previous session's report. The player README
    says that `"remix": {"enabled": false}` is the way to play without RTX.
  - Smaller fixes:
    - **Loader:**
      - a file an uninstall left in `backup/originals` no longer blocks every later deployment;
      - uninstall keeps its journal while files remain to delete;
      - a package that fails its checks leaves no staged bytes;
      - a file changed during extraction fails the run instead of being kept under a wrong hash;
      - a rollback refuses while a root file both generations share is missing or changed;
      - declared sizes can no longer wrap the free-space check;
      - a module dependency that failed to load is tried again at the next load;
      - module overrides work with the caller's search flags;
      - the exit observer forwards winmm calls;
      - `nlctl scan` reports folders it cannot list.
    - **Runtime:**
      - option strings the menus read are copied under the update lock;
      - a texture two materials share takes the stronger preload;
      - the middle cloud deck finds its patches along grazing rays, and its moon shadows follow them;
      - float options refuse NaN and infinities;
      - a config saved through a link keeps a backup until the rewrite completes.
    - **Material editor:** the sync snapshot is encoded once per state, and no handshake resets the RTX
      profile limit.
    - **Bodygroup tool:**
      - crafted dupes paste without errors;
      - the client's region cache is bounded;
      - tool actions are paced;
      - another player's model is editable only by that player or an admin.
    - **Bodygroup destruction:**
      - settings that default to on (damage, materials, no-cull, UV seams and others) can be turned off
        again;
      - refused settings log one line per player every 10 s.
    - **Model Hotloader:**
      - only a character's owner or an admin removes or replaces it;
      - prop attachments need the target within reach;
      - collision meshes are paced on the server;
      - a model reads files only inside its folder, the tex and textures folders near it, or its Workshop
        item;
      - loads check free memory first and stop when the map changes;
      - remote collision shapes are evicted;
      - its build fetches its dependencies with git.
    - **Motion importer:**
      - the RPE and skirt add-ons' settings it turns off come back after a map change, a quit or a crash;
      - built animations have a byte budget, and each player's builds are capped.
    - **Glass:**
      - a joining player's pane snapshots are paced;
      - another player's shots move your broken glass only when you can see them or are within 1,024
        units;
      - the glass module checks a map's compressed lumps before inflating them, caps static props across
        entries and bounds the world walk;
      - quitting or changing map cancels a map import in progress.
    - **RTX fixes:**
      - RTX Water skips a malformed polygon;
      - the RTX flashlight no longer leaks a light on a repeated "on", paces toggles, and gives no
        flashlight to the dead or where the gamemode refuses one.
    - **Companion:** the eye-white cache deletes only its own files.
    - **Tools and CI:**
      - the release job passes the tag through the environment;
      - only the package job may delete artifacts;
      - `inputs.py` refuses Windows path aliases;
      - `gmapack.py` caps LZMA output;
      - Pillow is pinned;
      - the vanilla-copy tool reports unhashed files;
      - `pins.json` records the patched fixes' tree ids, and RTX Water has patches of its own.
- **Released as v0.14.0.** The GitHub release has loader 0.14.0's bundle and its symbols. The RTX package
  that GitHub's workflow built for it (run 42130241622, `.gma` SHA-256 `12c404dc...`) is on Workshop item
  3829070317 as 0.0.0-dev.20261106004558+ad5cf8e8.
- **After the release: every Actions artifact expires two days after its run**, the loader's bundle
  included (the user; [ADR 0113](docs/decisions/0113-every-actions-artifact-expires-after-two-days.md)).
  Actions storage is 2 GB, and the per-push bundles, kept 90 days, would have filled it in about two
  weeks. `publish_workshop.py --from-ci` now names an expired or deleted package artifact, says to start
  the workflow again, and keeps the last download.
- **After the release: the loader's workflow runs only for a release or when a person starts it** (the
  user; [ADR 0114](docs/decisions/0114-the-loader-workflow-runs-only-for-a-release-or-by-hand.md)). No
  push of a branch and no pull request starts `build.yml` any more. A `v*` tag still runs every check
  before its release, and pushes of `main` stay gated by `tools\test.ps1` on the developer's machine.

### R18

- **R17's sky limits addressed** (the user's request; [ADR 0110](docs/decisions/0110-thin-decks-a-middle-deck-of-its-own-ice-arcs-a-milky-haze-and-twilight.md),
  runtime patch 0032):
  - **Thin cloud decks close.** Overcast, drizzle and fog are now drawn at real stratus depths (0.9,
    0.6 and 0.45 km instead of 1.2-1.8) and stay closed: the depth of a cloud body's soft edge is now a
    weather setting, shallow for these decks. Thinner decks also cost less to draw.
  - **The middle cloud deck has a pattern of its own.** Altocumulus now comes in patches and bands with
    clear sky between them, with cloudlets a few hundred metres across, instead of copying the low
    clouds at a greater height. Where a sight line meets no patch, the deck costs nothing.
  - **Sun dogs and the other ice halos.** Where the high clouds hold level ice plates, a low sun gets
    sun dogs at its height just outside the 22 degree halo: red on the inside, a white tail outward. A
    sun lower than 32 degrees also gets the circumzenithal arc high above it, an upside-down rainbow,
    and veils show the faint 46 degree halo. The moon gets them too.
  - **Hazy is a pale, milky haze.** Its sky was a flat grey in dim, warm light: the preset flattened
    the air's colour and warmed the sun, and its aerosol absorbed more light than it scattered. Hazy now
    has the clear sky's air and sun, and an aerosol that scatters most of what it meets and spreads it
    more broadly, under the cirrostratus veil: a pale bluish-white sky. Smog keeps its brown.
  - **The twilight lasts.** The sky's own twilight is kept to 8 degrees after sunset and fades out by
    16, instead of going black at 5: the blue hour and the glow over the sunset stay through nautical
    twilight.
  - The Remix menu gains Dust Absorption, Layer 2 Cell Size and Patch Size, Sun Dogs and Arcs, and
    Twilight Depth, translated into the six languages. While a weather is set, Profile Depth, Dust
    Absorption and Mie Anisotropy show the weather's values.

### R17

- **The sky fits the weather, and its clouds shade** (the user's request;
  [ADR 0109](docs/decisions/0109-cloud-genera-per-weather-a-sun-disc-and-a-high-cloud-layer.md), runtime
  patch 0031). Each weather now has its own cloud genera: fair-weather cumulus under cirrus when clear,
  cumulus with altocumulus when partly cloudy, a closed stratocumulus deck under altostratus when
  overcast, a cirrostratus veil with the 22 degree halo when hazy, stratus in fog and drizzle,
  nimbostratus in rain and snow, and cumulonimbus with anvil cirrus in a thunderstorm. The clouds are
  dense enough to shade: dark undersides, bright tops, billowed edges. An overcast or rainy sky closes
  up; it used to keep blue gaps.
- **The sun has a disc.** Numos drew the sun only as the haze around it (a scattered lamp). The disc is
  now true to size, darker at its edge and reddened toward the horizon. Clouds hide it, and thin cirrus
  dims it.
- **High clouds.** Cirrus streaks drawn out by the wind, the cirrostratus veil and cirrocumulus grains
  are drawn on a thin layer at 9 km. It stays lit and red for a while after sunset, rings the sun and
  the moon with a halo when it is a veil, and dims the stars at night.
- **The Milky Way and the nebula of the night-sky image come out in astronomical twilight.** They used
  to be full by 9 degrees after sunset. The stars appear as before.
- The Remix menu's sky settings gain Sun Disc, High Clouds and Edge Billows, translated into the six
  languages. While a weather is set, the middle deck's sliders show the weather's values.
- `tools/weather_presets.py` reads the Remix fork as the runtime is built from it: the fork's base
  commit with `runtime/patches` applied.
- **The RTX package workflow starts only by hand, for a release** (the user;
  [ADR 0108](docs/decisions/0108-releases-built-on-github-by-hand-development-built-here.md)). During
  development, commits, merges and pushes of `main` build the package locally and update the Workshop
  item as before R16. `publish_workshop.py --from-ci` uploads a release run's `.gma`.

### R16

- **Fixed: a chosen time of day and weather did not apply on entering a map whose add-on sets its own
  sky** (the user's item 44, Modern House RTX on `modern_house`;
  [ADR 0105](docs/decisions/0105-the-players-sky-applies-from-a-maps-start.md)). The add-on's
  afternoon stayed until a setting was changed in Sky and weather. Now, with "Follow the map's sun"
  unticked, the player's sky and weather are in charge from the map's start, and the add-on's own sky
  is put back at once whenever it sets it again; following the map still keeps the add-on's sky. Other
  maps were not affected: a new game, a map change and a listen server applied the sky at the start in
  the traces of this round.
- **The RTX package is built on GitHub, its native binaries included, and every run reports its
  hashes** (the user's item 45; [ADR 0106](docs/decisions/0106-the-rtx-package-built-on-github.md)).
  `package.yml` builds the Remix runtime from the fork with `runtime/patches`, the RTX fixes' modules,
  the debug module and the material editor's bridge from pinned sources
  ([`tools/ci`](tools/ci/README.md)), and this repository's modules; ReShade, the fixes'
  `stdshader_dx6.dll` and CoACD are downloaded from their publishers against pinned SHA-256 hashes. The
  run's summary lists the `.gma`'s SHA-256 and every file's, and where each native binary came from
  ([`tools/package_report.py`](tools/package_report.py.md)); `rtx-package-report` keeps it. Only the
  newest `.gma` artifact is kept. The Workshop gets exactly that `.gma`: the pre-push hook waits for the
  run and checks the file against its report (`publish_workshop.py --from-ci`); commits and merges no
  longer publish, and a package built locally is no longer uploaded unless the user asks. The material
  editor's bridge source is vendored in `packages/advanced-material-editor/source` (not shipped).
- **The Model Hotloader's natives are built on GitHub too** (the user's choice;
  [ADR 0107](docs/decisions/0107-the-model-hotloaders-natives-built-from-a-source-copy.md)). Their source,
  version 2.3.1 with the buoyancy and secondary-water changes that were staged but never committed in its
  author's worktree, is kept in `packages/model-hotloader/source` (not shipped); the workflow's
  `hotloader` job builds the four natives with the add-on's own recipe and regenerates its
  `native_policy.lua` and `mmdhl-native-release.json` from them ([`build_hotloader.ps1`](tools/ci/build_hotloader.ps1.md)).
  No native binary of the package comes from `packages/` any more. `tools/inputs.py extract` writes one
  folder of a part (a source tree) for a build.

### R15

- **Painted shadows of imported characters are left out in RTX sessions** (the user's item 43;
  [ADR 0104](docs/decisions/0104-painted-shadows-and-solid-hair.md)). The shadows MMD models paint over
  their eyes (目影), under their fringe (发影) and on their faces (陰影) darkened twice under path tracing: a
  dark band over the eyes. New rules find them by name, including Laevatain's `Moyin` (the pinyin of 目影),
  and by their properties (an untextured dark see-through overlay, such as Laevatain's `Hair+`, or one
  painted from a plain black image); make-up named 眼影 counts only when it is dark or grey, and glasses
  never. They are left out of the draw through a new hook in the Model Hotloader's visibility sync;
  bodygroups, saves and dupes do not change. Rendering > Model outlines: **Hide painted shadows**
  (`nativeloader_hide_painted_shadows`, on by default). In the field library's 6,684 parts it hides 92,
  all of them shadows.
- **Solid hair for imported characters whose hair texture hides a mask in its alpha** (the user's item
  44, Laevatain's hair). A hair part whose texture is mostly opaque, with partial alpha inside the
  strands that the 0.5 alpha test cuts into holes, is drawn without the alpha test and its soft copy
  without blending: the user's own fix, applied in memory and put back when it is turned off. The
  texture is sampled a few rows per frame; card-style hair, binary alpha and see-through hair keep the
  alpha test. Texture hashes, and so PBR, do not change. Rendering > Model outlines: **Solid hair**
  (`nativeloader_solid_hair`, on by default). `nativeloader_imported_parts_status` lists both per character.
- The guide's Characters page explains both, and Troubleshooting points to them.
- **The loader's release candidate, `v0.13.0-rc.1`** (the user, after R15): loader 0.13.0, the first
  release since 0.12.1, with memory profiles; the RTX package comes through the Workshop item.
- A client joining a server now receives the companion's eye-white rule modules too (they were only
  `include`d, never sent with `AddCSLuaFile`).

### R13-F

- **Material preloads load at their first draw** (runtime patch 0030, accepted by the user;
  [ADR 0103](docs/decisions/0103-material-preloads-load-at-their-first-draw.md),
  [report](docs/handover/R13-F-report.md)). A USD material's `preload_textures` no longer loads every
  mip when its mod loads. The frame that first draws the material loads them, synchronously, before it
  renders, so a character still appears with its whole maps. In the PoC's A/B the start-up held 2.4 GB
  less of replacement textures and about 1.7 GB less VRAM and commit. The frame that first draws a
  character lasted 0.11-0.58 s (with the machine's state as well as the character) instead of
  0.04-0.11 s, once per character and session. `rtx.texturemanager.preloadOnFirstDraw` turns it off.

### R13-D

- **Fixed an intermittent crash of the Remix runtime** (runtime patch 0029,
  [report](docs/handover/R13-D-report.md)): an access violation in its option system on the render
  thread, seen once in R13's PoC sessions. Lua's `RemixConfig.SetConfigVariable` (the companion's sky
  sends its values every 20 ms) changed options without the runtime's option lock while the render
  thread resolved them. It, the option layers that mods' graphs add and remove, and the Remix menu's
  layer actions now take that lock.
- **A setting sent from Lua is no longer lost now and then** (patch 0029): the end-of-frame resolve
  could drop a value another thread had just sent, which then took effect only when it changed again.

### R13-P

- **Character PBR maps stay preloaded** ([ADR 0102](docs/decisions/0102-character-pbr-maps-stay-preloaded.md),
  [report](docs/handover/R13-P-report.md)). In the PoC's A/B, streaming the four test characters' maps
  saved 2.2 GB of replacement textures and 1.7 GB of VRAM and commit at idle, with the same settled
  image. But each character first appeared with blurry maps for 0.15-0.9 s, and again after removal and
  respawn. rpai, ToPBR and existing mods keep `preload_textures`.

### R14

- Glass: a player in noclip no longer fractures glass it passes through (touch, contact and the
  pre-movement sweep ignore `MOVETYPE_NOCLIP` players).
- Glass (R14 continued): spectating players (`MOVETYPE_OBSERVER`) are ignored the same way, and broken
  glass no longer moves for a player in noclip or spectating. In a PoC game a player flew through a
  pane at 1,500 units/s in noclip and while spectating and left it whole; running into the same kind of
  pane still broke it.
- The in-game RTX Remix guide (R14's first pass, replaced by the redesign below): a "Where to find
  things" orientation, a Glass section, and annotated screenshots (numbered arrows) of the RTX Remix
  tab, Common Remix settings, Glass settings and Remix's Alt+X menu, drawn from real captures
  (`tools\guide_annotate.py`, `tools\qa\guide_shots.lua`); the new text is translated into the six
  languages.
- **The RTX Remix guide, redesigned** (R14-H): a window with a contents list (every page and its
  sections) instead of six tabs, and six task-ordered pages: Welcome, The RTX Remix tab (one section per
  group), The Remix menu (Alt+X), Characters, Performance and memory (was Memory and stability) and
  Troubleshooting. Short task-first steps, the words it uses explained, symptoms with what to do, and
  sharp labeled pictures of every place a player goes (the tab and its panels, both forms of the Alt+X
  menu and its Save buttons, External Models, Imported game PBR and the eye-white chooser with a
  character): real 1920x1080 captures, cropped, never scaled, with numbered badges and arrows that never
  cover what they point at, and a translated legend under each. `nativeloader_guide <page> [section]`
  opens a part directly. The help lines of the RTX Remix tab's own panels, the Sky and weather panel and
  the eye-white chooser were reworded in the same terms (the Start here button is now Performance and
  memory guide). `tools\guide_annotate.py` reads a per-picture spec (`tools\guide_pictures.json`);
  `tools\qa\guide_shots.lua` opens each panel through `spawnmenu.ActivateTool`.
- **The guide's text checked and translated** (R14-T, Codex, as the user asked): a check of the English
  against the code corrected the guide before translation. The memory profiles load up to five or ten
  recently used characters in advance when a map starts, not a fixed number kept ready. DLSS has its own
  preset beside Graphics Preset. The VRAM CSVs are kept across starts. Single game maps need Game layout.
  The flashlight's and the steady eye whites' controls are now named exactly as shown. The 292 new and
  reworded messages are translated into the six languages, with every on-screen name taken from the
  translation the player sees: the RTX Remix tab, the RTX add-ons, the glass panel, the Model Hotloader
  and Remix's own Alt+X menu. `tools\companion_i18n.py` lets DLSS, PBR, VRAM and Remix API equal the
  English. The player READMEs name the guide's page Performance and memory.
- **The guide grows with the screen** (found in R14's field check). On the user's 3840x2160 screen a GUI
  scaler add-on draws the spawn menu twice as large, but only the spawn menu, so the guide stayed at
  its 1080p size, less than half as large. At every opening the guide now scales its fonts, margins and
  window by the screen's height over 1080: 2 at 2160 lines, 1.33 at 1440. It also follows a larger
  `DermaDefault` when an add-on enlarges it everywhere, and 1080p games keep the plain sizes. Its
  pictures grow by whole steps, point-sampled, so they stay sharp. `nativeloader_guide_scale` (0
  measures, 1 to 4 sets it) overrides the measurement.

### R13

- **Imported game maps take about a sixth of the memory** (R13-M,
  [ADR 0098](docs/decisions/0098-compact-imported-game-maps-and-recipe-keys.md)): normals are stored
  as BC5, roughness and metallic as BC4, and the unused AO map is no longer written. A 2048x2048
  family needs 11.2 MB of replacement-texture VRAM instead of 67.1 MB (11.2 MB on disk instead of
  89.5 MB); emission maps are unchanged. Maps converted before are re-encoded on first use, without
  converting them again, also for characters whose source folder is gone.
- **Updates no longer convert every character again** (R13-M): converted maps are keyed by what
  changes their bytes, so a release that changes no conversion reuses them all.
- **Imported game PBR refusals say why** (R13-M): when free disk space or an image's size stops a
  conversion, the log and the Imported game PBR panel show the limit and its numbers instead of
  "DDS publication failed", and a character interrupted halfway completes on its next pass.
  Imported game maps have no per-session budget; the opt-in world conversion keeps its 1 GiB.
- **Memory profiles (loader 0.13.0):** the loader reads the largest graphics card's VRAM and the
  computer's RAM and picks a memory profile: below minimum, minimum (8 GB / 16 GB), recommended
  (16 GB / 32 GB) or high (24 GB / 64 GB). The smaller of the two decides, and the budgets scale with
  what the computer has:
  - Characters kept ready: none, five or ten.
  - A quarter of the VRAM for game textures before idle ones leave the GPU.
  - One copy of a game texture on the minimum, two above it.
  - `remix.memory_profile` overrides the choice. `status.json` reports it as `activation.memory`,
    the runtime gets its budgets in `native-loader\remix\memory.conf`, and the RTX tab shows it
    ([ADR 0101](docs/decisions/0101-memory-profiles.md)).
- **Memory report:** `tools/qa/memory_report.py` summarizes a session's RAM and VRAM from the
  loader's and the companion's telemetry, by phase, with an optional address-space census of the
  running game.
- **A lower-end guide** in the player README: the minimum and recommended computers, the profiles,
  and what takes memory.
- **Saved characters load when they are first used (R13-A).** A map no longer loads every saved
  NPC and player-model character: the NPC tab and the player-model selector list them from their
  metadata, and a character is mounted and precached right before its first real use (the NPC tab,
  the hotloader's own spawns, the player's model, saves, dupes and tools). The most recently used
  characters stay ready at map start, as many as the memory profile in
  `native-loader/status.json` keeps (`activation.memory.warm_characters`, `warm_mib`; none
  without it); `mmdhl_warm_characters` and `mmdhl_warm_mib` override them for tests. Menu icons of
  characters show their name or a real cached image instead of loading the model
  ([ADR 0099](docs/decisions/0099-saved-characters-load-on-first-use.md)).
- **The lag after a Combine soldier no longer grows with the character library (R13-A).** The first
  Combine soldier of a session (the NPC tab's, or a character spawned in that role; the AR2 alt-fire
  ammo it precaches) makes every texture the game has loaded GPU-resident at once. With every saved
  character precached that was
  17 GB on a copy of the field library; now it is the ready set and the characters already used
  (5.0 GB with a high computer's 10). The engine-side step itself remains
  ([R13-A report](docs/handover/R13-A-report.md)).
- QA: GMod keeps `cfg/config.cfg` in Steam Cloud, so a PoC session's last settings reached the
  field game's next start. R13-A's PoC driver ends each session with the field game's own settings,
  and so does every `tools/poc_session.py` run (`exec` of a copy of the field's `config.cfg`, then
  `host_writeconfig`, before the quit).
- QA: `tools/qa/mmd_lazy_session.py --sequence integrated` checks one memory profile with the built
  package (idle, four characters, the Combine trigger and the runtime's release after it); the
  [R13 report](docs/handover/R13-report.md) has the three profiles' numbers.
- **One copy of each game texture, and idle textures leave the GPU** (runtime patch 0024,
  [ADR 0100](docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)): on computers below
  28 GiB of RAM or 15 GiB of VRAM a game texture's CPU copy is freed once the GPU holds its data
  (`d3d9.releaseManagedHostCopies`); on every computer, while game textures hold more than a quarter of
  the VRAM, those not drawn for a minute give their GPU memory back (`d3d9.managedTextureBudgetMiB`).
  The data stays and returns on the next use with the same Remix hash; nothing visible changes. Both
  are automatic in GMod, so a player with an older loader gets them with the new runtime; explicit values
  from the loader's memory profile win. The lag report's 14 GB of suddenly resident character textures
  now return within about 75 seconds instead of staying until the game restarts: with R13-A's trigger
  (a plain Combine soldier) on the copied field library, game textures went 17.08 -> 8.58 GB and
  private bytes 43.69 -> 35.22 GB with this computer's defaults (the original runtime kept 17.08 GB).
  The `[RTX Managed Textures]` line also counts what created each image (runtime patch 0027): the
  burst's images all come from draws.
- **Replacement textures give way under real VRAM pressure** (runtime patches 0025 and 0026): near or
  over the driver's live budget, replacement textures stop growing or give back the overflow, whatever
  the configured texture budget (percentage or fixed), and preloaded textures (`preload_textures`, which
  rpai, ToPBR and the material editor set) that nothing draws drop to their smallest mip until drawn
  again. Preloads were the lag report's 10.3 GB that never gave way: the field's mods preload 11.05 GB
  of files at every start, every character's maps whether spawned or not. With free memory nothing
  changes. `DXVK_TEXTURE_PRESSURE_TEST_BUDGET_MIB` lets tests make that pressure on a large card.
- **Fixes from the review of the memory patches** (runtime patch 0028): the texture hash API no longer
  races the release of a game texture's image (a caller on another thread, such as ToPBR, could get an
  empty hash or read a freed image); the terrain baker's preloaded source textures count as in use, so
  they no longer drop to their smallest mip under pressure; a texture locked with
  `D3DLOCK_NO_DIRTY_UPDATE` keeps its CPU copy, so such a write is not lost before its `AddDirtyRect`;
  and other games no longer run the managed texture pass.
- **A host memory census** (runtime patch 0023): the opt-in `rtx.profiler.memory.requestSnapshot` also
  accounts the process's host memory by Vulkan memory type, mapping and purpose, and its committed
  address space; [host_memory_census.py](tools/qa/host_memory_census.py.md) turns it into an account.
  It found that the driver maps the game's VRAM into its address space as write-combined memory that
  counts in its commit, so VRAM the game holds also holds system commit.
- QA: the [GPU probe](tools/qa/build_managed_texture_probe.ps1.md)'s `r13` sequence and a
  [VRAM pressure tool](tools/qa/build_vram_pressure.ps1.md), which showed that a background process
  holding VRAM does not lower a foreground game's budget here (WDDM pages the tool instead).

### R12

- **NPCs after removing and importing a character again:** prepared carriers restore missing
  metadata before ragdoll/NPC/player spawning; deletion forgets reusable rig/conversion lookups
  in both realms while existing entities keep their bound carrier
  ([R12-A](docs/decisions/0094-reimported-carrier-metadata-and-state.md)).
- **Choose an imported character's eye-white materials by hand**: the button beside eye-white
  brightness lists spawned characters' materials with thumbnails, automatic/manual status and live
  toggles. Manual marks and exclusions survive map changes, restarts and same-asset re-imports;
  returning to automatic detection clears a choice. Unspawned library characters load no textures
  for this feature. All seven interface languages are supported
  ([ADR 0097](docs/decisions/0097-manual-eye-white-materials.md)).
- Imported game PBR can match renamed character textures by their UV features, with name support
  and conservative abstention. Its RTX menu panel lets players select map families/files, disable
  game maps for a texture, or return to automatic; choices follow that texture across characters
  and survive a missing source. Library enumeration checks drawn hashes before loading a material
  ([R12-B](docs/decisions/0095-texture-features-and-imported-pbr-overrides.md)).
- Imported game maps retain their packed colour channels when transparent images are resized.
  Name-confirmed data masks recover 阿芙2.0 hair, and corrected decoding recovers its accessories;
  a broken or ambiguous map family no longer suppresses the whole folder. Existing conservative
  thresholds remain, with explicit exported-family and self-vote guards (R12-B2, ADR 0095).
- **Imported-model catalogs no longer need GPU backing for every unused managed texture.** The
  runtime keeps static managed texture data ready in CPU memory and creates its original GPU image
  on first sampling, upload or `PreLoad`. Dimensions, mips and captured hashes stay the same;
  `d3d9.deferManagedTextures` provides a compatibility override. Local GPU tests compare exact
  pixels and texture hashes against the original runtime
  ([ADR 0096](docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)).
- **Unused imported-character materials stay unloaded by the MMD alpha classifier.** It now waits
  for a real draw record before looking up a material or texture. Local memory census tools report
  loaded Source texture names/groups and opt-in runtime allocation size/format/pool, so VRAM costs
  can be attributed without changing texture hashes or visual quality
  ([ADR 0096](docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)).
- QA tools no longer wait for the field game to go idle: the field game is a test session (the
  user, 2026-11-02). `tools/qa/mmd_reimport_session.py` ends a running field game before its PoC
  launch and records which; R12-C's `tools/game_activity.py` gate is not kept.
- **Imported game PBR no longer stops partway through a session** (the user's urgent fix,
  2026-11-03). ToPBR stopped writing game maps once a session had generated 1 GiB of them, so later
  characters (such as 洛茜) got none until a restart. Only the opt-in world conversion counts toward
  that budget now, and a budget or disk-space refusal logs a clear warning. Published without the
  usual tests at the user's request; compact maps and reuse across versions follow.

### R11

- **Imported game PBR survives a missing source folder** (the user: keep game maps working after a
  character's source folder is gone). After one successful conversion, ToPBR records the character's
  live texture and material; when the folder is later moved or deleted, it restores them as long as
  every cached map still validates. The setting still turns them off, real replacements still win,
  clearing ToPBR's cache keeps the records, and a damaged record file is backed up and rebuilt. A
  texture shared by several materials now converts once per session, and ToPBR no longer leaves a
  `materials.usda.before-r11-*.bak` copy of its own output at every game start (R11 did)
  ([R11-B](docs/decisions/0093-cached-imported-game-materials.md)).
- **Imported game characters use their own PBR maps automatically** (the user: Wuthering Waves,
  Arknights: Endfield and Silver Palace models ship packed PBR maps that should be detected and applied
  in RTX with the aggressive look, with an on/off setting). For a character imported with the Model
  Hotloader, the maps beside its model file are found by the games' naming (`_N`, `_MRA`, `_P`, `_E`...)
  and unpacked into normal, roughness, metallic, AO and emission maps; what a game does not ship comes
  from the aggressive preset. Skin, faces and eyes keep their look, and the R10 eye whites keep working.
  It needs the folder the character was imported from to still exist. "Imported game PBR" in the RTX
  menu's character options (on by default, all seven languages)
  ([ADR 0091](docs/decisions/0091-automatic-pbr-fallbacks.md)).
- **Real PBR replacements always win over automatic PBR** (the user: "actual PBR replacements, if
  exists, should always overwrite the autoPBR result"). A character pack, a map's PBR mod or any other
  mod with a material for a texture is what renders, whatever the mod's folder is named, also when it is
  added or reloaded while the game runs; before, a pack whose folder name sorted after `~` (a Chinese
  name, for example) lost to the automatic material. Runtime patch 0020
  ([ADR 0092](docs/decisions/0092-generated-fallback-mods-rank-last.md)).
- **The automatic PBR for map and prop materials (ToPBR) is safer and looks closer to RTX:** its work
  moved off the frame (0.8 ms at most per frame instead of 23.5 ms on gm_construct), converted textures
  are reused safely, turning it off removes its materials, glossiness follows the material's Phong
  settings more naturally and dark plastic is no longer turned into metal. It stays off by default
  ("Enable ToPBR" in the RTX settings), as the user's map and add-on content has not all been checked.

### R10

- **Imported characters get steady eye whites** (the user: apply the eye-white correction to Model
  Hotloader characters, found by names such as 眼白, with a brightness option). Characters without a
  PBR pack used to show grey eye whites, shaded by the lids in every light. An eye white named 白目,
  眼白, 目白, Eye White or the like now gets the same light-following glow the character packs have,
  and only the eye white glows, even where it shares its texture with the face; characters with a
  pack keep the pack's look. The RTX menu has a "Steady eye whites for imported characters" checkbox
  and an "Eye-white brightness" slider (0-200 %, for every character, packs included), in all seven
  languages. Runtime patch 0019 ([ADR 0088](docs/decisions/0088-imported-character-eye-whites.md)).
- **VMD expressions drive the model's own morphs** (the user: 笑い drove a wink on Guinaifen, and
  many other expressions landed on the wrong morph, Robin too). A motion's 笑い now closes both eyes
  with the model's own 笑い, and はぅ no longer plays as なごみ: an expression the model has by name
  always drives that morph, the way MMD and nanoem match them, including morphs beyond the hotloader's
  first 96. Only an expression the model lacks is matched by meaning, checked against 1,225 of the
  user's models, with each eye's side measured on the model itself (the names' left and right are
  not reliable). A both-eyes expression never drives one eye. The mapping window shows the real
  PMX morph names, saved manual choices stay, and animations built with the old mapping are rebuilt
  ([ADR 0089](docs/decisions/0089-pmx-identities-and-geometry-checked-vmd-expressions.md)).
- **Imported characters spawn as NPCs after a map change** (the user: model not found). The spawn
  menu offers an imported NPC or player model only once its files are mounted and the new map has
  loaded the model, and the hotloader's own NPC spawn checks the same; a mount from the previous map
  is no longer taken on trust ([ADR 0090](docs/decisions/0090-ready-carriers-before-actor-publication.md)).
- `tools/poc_session.py` writes a relative `--allow-local` or `--allow-dev` path that exists from the
  current folder as an absolute path: the loader reads relative entries against the game root, so a
  package given as `out\...` deployed nothing ("file not found").

### R9 (the user's glass report of 2026-11-02)

- **Glass breaks realistically, down to tiny pieces** (the user: always square and uniform, never very
  small). Annealed panes break into long radial shards around a crushed core at the impact. Tempered
  panes dice into compact, irregular granules instead of a grid. A hit on a fallen piece cracks it
  into two to six irregular fragments around the hit, down to one square unit, instead of halving it
  ([ADR 0087](docs/decisions/0087-glass-shards-and-environment.md), [report](docs/handover/R9-G-report.md)).
- **No visible delay between the hit and the break.** The hole and every piece appear in the frame
  the hit arrives, nearest the impact first. Pieces whose physics bodies are still being built fly in
  shared previews meanwhile. Holes used to appear two frames late, and pieces came 12 a frame.
- **Glass sounds.** Pieces sound when they hit the map, props or each other, land, split and enter
  water. They use the game's own glass sounds, positional and limited to 4 a frame and 24 a second.
  A switch in the glass settings turns them off.
- **Water and explosions.** Pieces sink slowly in water, with drag, using the map's water brushes and
  Jolt's buoyancy. Every explosion near pieces pushes them, wakes sleeping ones and breaks weak ones,
  even when it damages nothing else: `util.BlastDamage`, `env_explosion`, grenades, barrels, rockets.
- **No more glass flying backwards.** Pieces created inside a moving player or prop, or moved into
  one by a teleport correction, were pushed out of it backwards. Such overlaps now wait until they
  separate, and fast pushes follow the body's actual travel.
- **"Clear broken glass" buttons** in the glass settings. One clears your own fallen glass; an admin
  of a single-player or listen server can also clear everyone's. All seven languages.

- **Glass no longer breaks other add-ons' traces.** A bullet penetration add-on traces with a function
  as its filter, which GMod allows; the melee observer passed it to `IsValid`, which indexes its
  argument, and the error ("attempt to index local 'object' (a function value)") surfaced through that
  add-on's `util.TraceLine` call. Only entities are now checked for a player, and each observation runs
  protected, so a failure is counted (`errors`, `lastError`) and the caller always gets its own result.
  The test harness's `IsValid` now throws as GMod's does.

### R8 (unreleased; [plan](docs/handover/R8-plan.md), [report](docs/handover/R8-report.md))

- **No more noise on Model Hotloader characters** (the user: frame-to-frame noise since the alpha fix,
  worst with DLSS). R7's runtime patch marked a tagged character's material as changed every frame (it
  compared a state that a later draw of the same frame, or a new instance, had replaced), so the
  denoisers and DLSS Ray Reconstruction discarded its history on every pixel. Patch 0018 compares the
  first draws of consecutive frames only. Remix's disocclusion debug view: 37 % of the frame before, 0 %
  after.
- **Vanilla characters in bind pose again** (the user: broken bones and meshes on non-Model-Hotloader
  characters). The Backrooms map add-on (`gm_br_rtx`, installed in the field the same day) forced
  `r_forcehwlight 1` on its maps, R3-016's cause: GPU-skinned meshes reach Remix without bones. The add-on
  no longer sets it (fixes clone, branch `claude/rtx-remix-map-enhancement-bda9ac`, `98d7682`; the field
  copy updated, the old one backed up), and the RTX guard pins `r_forcehwlight` at 0 against every Lua
  caller. RTX map remasters may still scope `r_novis 0` to their maps (the Backrooms remaster ran at
  9 FPS with the session's `r_novis 1` in the field).
- **Graphics add-ons under RTX without guard-made Lua errors** (the user: GShader Library still crashes or
  errors on a tester's machine). Blocked calls get safe fallbacks; GShader-style screen-space effects stay
  inert under RTX and keep working with RTX off; material loads stay native and the package's own Lua is
  exempt by exact paths; GShader's light-metatable edits stay private; Real CSM's and Quick Bloom's raster
  settings are pinned ([ADR 0086](docs/decisions/0086-inert-shader-effects-and-safe-guard-fallbacks.md)).
- **Falling glass costs far less.** Piece creation is spread over frames and crowded distant fragments fall
  as grouped bodies: the 50-pane scene falls at 10.9-11.9 ms instead of 26.3-28.6 ms (p99 35-36 instead of
  134 ms), settled unchanged ([ADR 0085](docs/decisions/0085-glass-load-collision-and-hits.md)).
- **Glass collision levels**, like the MMD physics: objects, ragdolls, players and NPCs each have a checkbox;
  living entities are off by default (one-time migration of archived settings, seven languages).
- **Bullets and melee break fractured glass at any time.** Clients' interest updates were always refused
  (the server required 128 bits per region; `net.WriteVector` sends 3-66), so bullets reached pieces only
  for 2 s after a break; a bullet now carries 60,000 energy per damage point (pistol rounds split whole
  slabs); crowbar, stunstick, fists and trace-based melee SWEPs are forwarded.
- **Glass mirrors keep up with Source when a step runs long** (CI red on `main` since R7). When the
  glass world's 4 ms catch-up budget dropped a substep, the mirror of a Source body stopped halfway
  through its motion and fed the backlog into the next snapshot as extra speed: a 30 FPS client that
  dropped every catch-up step pushed glass at twice the real speed and left every second snapshot of a
  very fast body unswept. The 2-vCPU CI runner failed `nl_glass_tests` on it. Dropped time now moves
  mirrors as a pose correction, and the native tests pin the budget (`World::set_catch_up_budget`, C++
  only) instead of racing the clock. The Lua scene harness had the same race against the 0.5 ms
  shape-cook budget and now runs on its simulated clock.
- **The Backrooms work's native fixes in the RTX fixes DLL**: a cache of models without a SW VTX, lazy model
  transforms and default-off PAS visibility for the room next door, ported onto the packaged fixes source
  (corresponding source in `packages/fixes/licenses/oversized-skinning/backrooms/`).
- **The game window no longer turns "Not Responding" during long loads** (the user: the game still drew
  and the menu updated while Windows called the window unresponsive). GMod's main thread stops reading
  window messages while it remounts Workshop add-ons or loads a big map, minutes for gm_br_complex with
  765 add-ons, so after 5 s Windows replaced the window with a greyed copy offering to close it. Loader
  0.12.1 turns that window ghosting off for the game process (user32 loaded at run time; the bootstrap
  still imports only KERNEL32); `NATIVE_LOADER_WINDOW_GHOSTING=1` keeps it. `tools\poc_session.py` takes
  `--hang-grace <seconds>` for such loads.
- **The exit observer no longer refuses a fast start** (the other CI failure on `main` since R7, and the
  `v0.12.1` tag build). The observer refused a session start earlier than the game's creation time. The
  start comes from `GetSystemTimeAsFileTime`, which moves once per clock tick (15.625 ms at Windows'
  default, on the CI runner), while the creation time is finer. A loader that recorded its session within
  a tick of the process starting therefore lost its crash observer, and start-up waited the full 3 s.
  Two ticks of slack now cover that. A refusing observer exits with `0x4E4C0000` plus its reason, and
  start-up stops waiting at once and logs it (`exit observer refused: pid=..., <reason>`).

### R7 (unreleased; loader 0.12.0, [plan](docs/handover/R7-plan.md), [report](docs/handover/R7-report.md))

- **Transparent MMD materials show under RTX** (the user: Columbina's blindfold rendered black, only
  its shadow showed). Model Hotloader draws partly transparent texels blended; Remix skipped a blended
  opacity below 0.79 in primary rays while still shadowing by it, and Source's fixed-function path
  alpha-tests lit models at about 0.7. A runtime texture category gives Model Hotloader textures MMD's
  rule: an alpha test at 0.5, and blended opacity at or above 0.5 solid in every ray type, below it the
  existing blend. The companion fills it at runtime from the hotloader's public materials and its soft
  copies (a part drawn only through its soft copy, like the mask, has no hash under its public name).
  Map glass and other blended surfaces are unchanged
  ([ADR 0081](docs/decisions/0081-mmd-alpha-texture-category.md), runtime patch 0017).
- **A message after a crash.** An external observer from the same `winmm.dll` reports an abnormal
  exit once the game has closed, with the reason (out of memory, GPU device lost, allocation failure,
  rendering-thread exception, crash), advice, the exit code and the evidence folder, in seven
  languages; the next start reuses its conclusion. `NATIVE_LOADER_EXIT_REPORT=quiet` keeps automated
  sessions window-free ([ADR 0083](docs/decisions/0083-external-exit-observer-from-the-proxy.md)).
- **Diagnostics.** The memory warning needs less than 18 GiB of free commit or a commit limit under
  24 GiB (64.0 / 90.6 GiB no longer warns); the panel lists `gmod-rtx-remix` in full and counts the
  other enabled add-ons ([ADR 0082](docs/decisions/0082-map-commit-headroom-and-addon-summary.md)).
- **Broken glass reacts to the world, one way.** Players, NPCs, props and ragdolls push and break
  pieces; bullets, blasts and hard landings break them; nothing pushes back. Fast props are found by
  swept bounds and swept against the pieces. A per-player switch turns it off
  ([ADR 0084](docs/decisions/0084-glass-one-way-interaction.md)). Found in game at integration: the
  search for nearby bodies tests regions on plain numbers (a Source vector component costs 35 ns per
  read; 512 bodies against 32 regions went from 3.13 to 0.30 ms), and a client physics body's coarse
  box takes the body's pose (`PhysObj:GetAABB` is in the object's own frame, so client ragdolls and
  props were placed near the map origin and dropped).
- Decision records numbered in parallel were renumbered at integration: R7-A's MMD alpha record is
  0081 (it had used G1's 0080), R7-C's interaction record 0084 (R7-B kept 0082 and 0083).

### G1 (unreleased)

- Glass breaks are no longer always the same shape (the user: "always an octagon"): each hit takes
  6–16 rays at uneven seeded angles, every ray has its own ring radii, and a break also drops a few
  small cells at the hole's edge. Still seeded, so every player sees the same pieces.
- Walking into glass no longer breaks it, for two reasons found in game. The player's physics
  shadow reported a collision that took the prop energy rule (85 kg at 200 units/s is far above
  the breaking energy); bodies now always use the 250-unit/s contact speed. And Glass-Rewrite-Remix
  archived `rtx_glass_player_break_speed` (default 100) and `rtx_glass_velocity_transfer` (2) under
  the names this system reuses; the first start resets those two once and keeps later choices.
- The RTX package gains its eleventh part, `glass`: the MIT add-on (`nlglass`) with the Jolt
  licence and the `gmcl_nlglass_win64.dll` module, replacing Glass-Rewrite-Remix
  ([report](docs/handover/G1-report.md)).
- G1-B's decision records 0074–0077 are now 0073 and 0078–0080: the parallel tasks had used the
  same numbers.

- G1-A break handlers defer/coalesce remaining-pane meshes and prediction collision to later
  client frames, bounded to two builds/frame with a soft 1 ms budget. Shared extrusion/vertices
  cut duplicate geometry work. Whole breaks and cleanup cancel stale work; pieces still spawn
  immediately. The mocked client's total break CPU mean drops from 13.59 to 2.88 ms locally.

- G1-A crack strips use a lit shader and white texture so Remix can shade them in dark scenes.
  Body contact defaults to 250 units/s, above walking and below running; menu guidance is
  translated and Reset to Defaults restores the new threshold. Archived choices remain intact.

- G1-A second pass bounds breaks at 200 annealed / 300 tempered pieces, including large and
  repeatedly hit map windows. Small impact rings and large far pieces remain; tempered grids
  evenly cover the pane without exceeding their budget or dropping glass area.

- G1-B debris draws bind material once per group, reuse matrices after pose/scale changes, and
  cull outside the current view, beyond 8192 units or below a distant subpixel threshold.
  `NLGlassDebris.Stats()` reports averaged Think/draw milliseconds, peaks, draw calls per frame,
  culled pieces and pile upload timings for game QA.

- G1-B second pass consolidates settled glass into larger material-based areas and 24,000-vertex
  meshes. Bounded reusable upload scratch replaces temporary transformed vertices; timed rebuilds
  and staged GPU-resource retirement reduce allocation/rebuild bursts
  ([ADR 0079](docs/decisions/0079-glass-pile-consolidation.md)).

- G1-A clients build a break once, reuse unchanged pane meshes, cache stationary transforms and
  cull distant/rear panes. Revision repair targets one pane; joining clients request one initial
  state. Player sweeps include scripted base velocity, and blast impulses follow deferred native
  breaks. All fix-pass items have before-failing regressions; the full Release gate passes.

- G1-A fracture now refines locally and coarsens complete distant groups under its 512-cell cap,
  preserving hit locations and existing holes. Weak hits accumulate under a capped crack floor;
  tempered glass shows local spiderwebs before full shatter. Cached topology/snapshots remove full
  history replay; clipped vertices merge below 1/256 and cracks omit the window perimeter.

- G1-A fix pass: require actual approaching body contact; use incoming player movement to catch
  a stopped-by-collision runner; create replicated settings in both realms; dispatch captured map
  OnBreak outputs without engine shatter; record weak native hits, push blasts after their new
  debris and match the settings budget slider to 8,192. Offline regressions cover each path.

- G1-B performance fix pass: prepare maps and step Jolt on a polled worker; consume changed poses,
  avoid full settled-piece scans, retain old pile chunks through staged rebuilds, allocate scratch
  from demand and continue safely when Jolt's contact tables fill ([ADR 0078](docs/decisions/0078-glass-background-work-and-staged-piles.md)).

- G1-B fix pass: skip/count refused brush and prop convexes without losing Jolt for the whole map;
  clip brush hulls in double precision, correct displacement indexing and retain ordinary terrain
  triangles whose SURFACE bit is absent.

- The fixes packager omits Glass-Rewrite-Remix and its exclusive interface catalog entries/source
  references. Other add-ons/translations and the existing glass VMT/Remix replacement remain;
  the new MIT glass part is assembled separately by G1 integration.

- A new MIT glass add-on implements server-owned convex panes, one damage pipeline for bullets,
  melee, blasts, props/ragdolls and bodies, synchronized growing cracks, deterministic radial/ring
  annealed holes and full tempered shatter. Remaining cells supply frozen server/client collision;
  debris uses G1-B's client API. Map glass, late join, cleanup, property-only saves/duplicates, the
  glass tool, spawn presets and seven-language settings are covered by offline LuaJIT tests.
  Actual game/material/output and performance acceptance remains with G1 integration
  ([implementation and defaults](glass/README.md), [damage decision](docs/decisions/0071-glass-impact-model.md)).

- Vendor Jolt Physics 5.3.0 (MIT) for the dedicated client-side broken-glass world (G1-B).
- Add `gmcl_nlglass_win64.dll`: bounded BSP brush/displacement/static-prop collision import,
  worker-thread glass physics, fixed stepping, sleeping and reusable Lua pose output. Bad maps or
  missing modules select a capped client physics fallback ([ADR 0072](docs/decisions/0072-glass-debris-world-and-batching.md)).
- Add the client debris manager: per-player budget/lifetime/collision settings, oldest-first
  eviction, last-second shrink, explosion impulses and settled area mesh batching. A client QA
  [probe](tools/qa/glass_debris_jolt_probe.lua.md) compares empty/falling/settled frame times.

### C-16 (unreleased)

- Anime characters' eye whites no longer glow at night or turn grey by day: with Robin's pack, the eye
  white's luminance over the cheek's went from 0.52-0.88 by day and 46 at night to 0.77-1.38 by day,
  0.70 at night and 1.04 in a lamp-lit room ([ADR 0069](docs/decisions/0069-tuned-adaptive-eye-emission.md)).
- Guinaifen's pack (Workshop item 3829348717) has the steady eye whites too (2026-11-02): her two face
  materials carry the adaptive input 15 beside the fixed 0.6. Her display name `Guinaifen (桂乃芬)`
  stays as published, as the user chose; `check_pack.py --keep-name` reports such a kept name as a
  warning instead of refusing the update ([report](docs/handover/C16-report.md)).
- Opaque materials can opt into scene-adaptive emission with `emissive_adaptive_intensity`: it
  follows auto exposure's scene luminance to steady eye-white brightness, with a fixed-intensity
  fallback, configurable scale/clamps and luminance/exposure logs for tuning
  ([ADR 0067](docs/decisions/0067-scene-adaptive-emission.md)).
- The MMD PBR tool writes optional scene-adaptive eye emission alongside its fixed older-runtime
  fallback. The publish-time ratio is tunable without regenerating textures; its default 25 was
  tuned in game on Robin ([ADR 0069](docs/decisions/0069-tuned-adaptive-eye-emission.md)). A
  byte-preserving script updates staged copies of existing packs, and character packaging verifies
  that the published shader inputs survive unchanged
  ([content decision](docs/decisions/0068-adaptive-eye-emission-publishing.md)).
- QA: [`eye_white_probe.lua`](tools/qa/eye_white_probe.lua.md) photographs a Model Hotloader
  character's face at noon, golden hour, dusk and night from one placed spawn point, and
  [`eye_white_patches.py`](tools/qa/eye_white_patches.py.md) measures its eye whites against the cheek.

### Fixed (after R6)

- The git hooks' background Workshop publish no longer opens a window for every step it runs; with
  Windows Terminal as the default terminal each step had left a finished tab open (about 60 per push).

### Added (R6: performance and stability; loader 0.11.0, [plan](docs/handover/R6-plan.md))

- **Remix settings that fit your graphics card.** At each RTX start the loader picks a performance
  tier for the NVIDIA card with the most video memory. `high` keeps the package's settings, tuned on
  an RTX 5090. `medium` (10 to 12 GB, or an x70 model) and `low` (8 GB, or an x50/x60 model; a laptop
  GPU counts one step lower) use fewer light bounces (8 instead of 12), a lighter neural
  radiance cache and smaller memory budgets: micromaps, sky probe, volumetric fog grid and terrain
  atlas; `low` also uses Remix's low-memory mode and 4096-pixel night-sky images. Settings saved in
  Remix's menu still win. `"remix": { "performance_tier": ... }` in `config.json` picks a tier
  yourself; the RTX Remix tab's Start here page shows the tier and why. Measured at 4K on an RTX
  5090: medium and low are 5-9 percent faster than high and use 170-750 MiB less video memory
  ([ADR 0062](docs/decisions/0062-loader-layers-performance-tiers-and-gpu-dumps.md),
  [ADR 0064](docs/decisions/0064-performance-tier-defaults.md)).
- **On AMD and Intel, Remix's own preset for your GPU takes effect.** The loader's Remix settings
  now come before the package's copies, which used to override it.
- **GPU crash dumps when asked for.** `"diagnostics": { "gpu_crash_dumps": "next_start" }` turns on
  NVIDIA's GPU crash diagnostics for one RTX start (`always` for every start; `off` by default). The
  dumps go to `native-loader\logs\gpu`; the config file is never edited to consume the request.
- **What a crash leaves behind is kept.** At the next start the loader copies the previous
  session's Remix log, the crash dumps already on disk and the memory history into
  `native-loader\logs\sessions` (five sessions, at most 200 MiB), before the runtime overwrites its
  log. Nothing is uploaded or deleted at its source. The home menu, `status.json` and
  `nlctl status` say what probably went wrong and where the copies are
  ([ADR 0063](docs/decisions/0063-local-session-evidence-and-memory-telemetry.md)).
- **Memory history.** The loader records process, system and GPU memory every ten seconds in
  `native-loader\logs\memory.csv` (the last one to two hours; `"diagnostics": {
  "memory_telemetry": "off" }` stops it). The companion records Remix's own VRAM categories every
  30 seconds in `garrysmod\data\native-loader\vram*.csv` (`nativeloader_vram_telemetry 0` stops it).
- **A warning before Windows runs out of memory.** Once per start, before the first map, the home
  menu warns when the system commit charge is over 70 percent of its limit, or the limit is under
  32 GiB, and explains page files and closing other programs.
- **The runtime says what memory looked like when the GPU was lost.** Its log reports driver
  budgets and use for every heap at camera cuts, every five minutes and at a device loss, and
  `rtx-remix\logs\last_gpu_crash.json` keeps the last device loss's numbers and how it was
  detected for the next start. Repeated micromap budget warnings appear at most once a minute,
  with a count, and a dropped micromap budget says how much VRAM was free and what the limits
  were ([ADR 0065](docs/decisions/0065-runtime-memory-diagnostics.md)).
- **A Memory and stability page in the guide** (all seven languages; the new translations are
  agent-written and marked for review) and a [player checklist](docs/STABILITY.md): settings for
  8 GB cards and 16 GB of RAM, reading memory during a session, and what to send after a crash.
- **No more rejected memory limits at each map load.** The RTX fixes stopped asking Remix for cache
  and VRAM limits it does not have; `RemixResource.SetMemoryLimits` stays a no-op that returns `true`
  and logs once ([ADR 0066](docs/decisions/0066-fixes-memory-limits-compatibility.md)).
- **Smaller ToPBR textures.** The fixes' 83 `~gmod_topbr` normal and roughness maps are linear BC7:
  34.07 MiB instead of 136.25 MiB on disk, with the same names, sizes and materials
  ([measurements](packages/fixes/licenses/topbr-bc7/README.md)).
- An older loader (0.10.1 and before) rejects the new `config.json` keys and starts without RTX;
  the README, the guide and the checklist say to update `bin\win64\winmm.dll` first.

### Changed (R6, for developers)

- `poc_session.py` watches crash prompts throughout each run, detects GPU loss and persistent window
  hangs, bounds captures and shutdown, keeps the evidence, and names known crash exits;
  `release_qa.py` reports device loss and hangs explicitly in its output and JSON summary.
- Activation lists the tier layer and the non-NVIDIA layer first in `DXVK_CONFIG_FILE` (the first
  file wins for `rtx.*`) and the GPU diagnostics layer last (its `dxvk.enableAftermath*` keys: the
  last file wins for `dxvk.*`); an older package without tier files gets a built-in `low` fallback.
  `status.json` reports `activation.performance_tier` and `previous_session`; a wrong diagnostics
  value costs only that diagnostic (a note), never the loader.
- `runtime\build_runtime.ps1` refuses a missing or non-Release Meson configuration before building
  or importing, and a fresh setup calls Python's Meson directly in the repository's MSVC
  environment; patch 0015 records the six unit-test sources the fork snapshot had left out. The
  crash marker is written through a per-process temporary file, with two short retries.
- `tools\tests\test_runtime_tiers.py` checks every tier key's name, type and range against the
  patched runtime; `tools\sky\drop_top_mip.py` removes a DDS top mip losslessly. The classic layer
  still holds 15 keys this runtime no longer has (old exposure, local tonemap and bloom options,
  `occluderTextures`, `finalizeWithACES`).
- The MMD PBR skill requires a 2048-pixel variant for 8 GB players.
- The task-by-task record of R6 is in [docs/handover/](docs/handover/README.md) (R6-T1 to R6-T6).

### Fixed (R5: the user's QoL report of 2026-10-31, [handover](docs/handover/R5-qol.md))

- **No more line across the night sky on modern_house.** Modern House RTX puts its settings back 23,
  43 and 63 s after the map starts, its afternoon sun among them. Once you had set your own sky, the
  companion took it back only on its 10-second timer: up to 10 s of afternoon in the middle of the
  night, and the daylight then lingered in the image's history where the camera had looked, a haze
  over the stars with a straight edge, stars on one side only. The companion now takes the sky back
  in the same tick, and a map's add-on can run the hook `NativeLoaderSkySet` after setting its sky.
- **Broken glass is interactive.** Map window debris and the glass add-on's pieces are real physics:
  players walk through them, props push them, bullets and explosions knock them about, and the
  physgun, gravity gun and +use pick them up
  ([ADR 0061](docs/decisions/0061-loose-glass-breaks-again-and-expires.md)).
- **Broken glass breaks again.** Shooting a piece, an explosion or a hard impact cracks it into
  fragments, again and again, until they turn into dust. All broken glass shares one 256-piece
  budget, oldest first.
- **Broken glass goes away after a while.** New setting `rtx_glass_debris_lifetime` (seconds, default
  120; 0 keeps pieces until map cleanup), with a slider in the glass settings. Expired pieces shrink
  away. Its translations are agent-written and not yet reviewed.
- **A subscribed Workshop model pack always provides its models**, even a model you had imported
  yourself (the user, 2026-10-31). Model Hotloader installs it again from the package (only files
  that differ are written) and shows it as the package's; your settings for it are kept aside and
  come back, with the model, if you unsubscribe. Before, such a model counted as your own import and
  the package never showed as installed.
- **"Recalculate normals for RTX" sits under the import button** on External Models, one switch for
  characters and props, and its note says to turn it on only if a model looks wrong in RTX Remix
  (translations agent-written, unreviewed).
- **The content pack skill refuses what the Evernight and March 7th pack got wrong:** a display name
  that is not the character's plain ASCII name, and a model without a terms-of-use record; its upload
  step now starts with a check in the game.

### Fixed (after the 0.10.1 release)

- **No more "RTX package ... was updated: restart Garry's Mod" at every start.** GMod's
  `steamworks.FileInfo` returns Workshop update times rounded to a 32-bit float (128 s steps today),
  and the companion compared that with Steam's exact time, so the version already deployed looked
  newer for about half the items, and an item such as Evernight and March 7th looked never installed.
  Only a time more than one such step later counts as a newer version now.

### Fixed (review R4 of the QoL batch and field QA; loader 0.10.1, [review](docs/handover/R4-review.md))

- **Breaking glass no longer ends the game.** Shooting a window on modern_house, or spawning any
  procedural glass, crashed RTX sessions on the material system's render thread (`studiorender.dll`
  +0x6603b) with the user's `mat_queue_mode 2`: shards were drawn through DrawModel and
  GetRenderMesh. They now draw their own mesh, and meshes a queued frame may still use are destroyed
  eight frames later. Reproduced and bisected in the field install, fixed there.
- **The toolgun screen's scrolling text is sharp.** The QoL redraw rendered the screen through a 3D
  camera into a render target, which Remix takes into its path-traced scene, so it never reached the
  screen. The screen is now drawn as projected 2D triangles after upscaling
  ([ADR 0057](docs/decisions/0057-toolgun-screen-as-2d-overlay.md)).
- **"Recalculate normals for RTX"** shows its label on the External Models tab: two Model Hotloader
  keys lacked the `mmdhl.` prefix in all seven catalogs. `check_addon_i18n.py` now checks every phrase
  Model Hotloader looks up.
- **The Motion importer tab is the motion importer.** It used to hold one button opening the Motion
  Manager. It now fills the tab like External Models: section buttons for the importer and the Motion
  Manager, Open in window, and each section built in place by the add-on itself. The importer shows
  the desktop importer's inputs in its order (body motion VMD, music, camera VMD, audio offset, the
  motion metadata, face/flex VMDs) beside the bake, its options, the progress and the log; the Motion
  Manager shows the library beside the selected motion's music, playback and build controls. Without
  Model Hotloader's file access the importer says why, with Resolve. The floating windows,
  `mmdvmd_import` and `mmdvmd_menu` use the same builders
  ([ADR 0060](docs/decisions/0060-motion-tab-hosts-the-importer.md)). Its text and controls follow the
  screen as External Models does (twice the size at 4K, where they were half the spawn menu's), times
  the player's `mmd_vmd_npc_menu_scale`, and opt out of the GUI Scaler add-on's second scaling as Model
  Hotloader's panels do.
- **The RTX package carries the motion importer's current version (fcd56f4)**: in-game VMD import
  (`mmdvmd_import`, the tool's Import Animation button), dances blending in from the T-pose, scene-cut
  holds and the stage placement and movement options. The part had been imported from a clone stuck
  at 318b054; this repository's translations are kept, with Traditional Chinese for the 98 new phrases
  (machine-written, not yet reviewed by the user).
- The legacy Remix migration never blocks the package: links in a former installation (Mount HL2
  RTX's) stay and are never followed; a junctioned game folder, a library under a mount point and a
  linked `d3d9.dll` no longer stop the apply; on another GMod build or beside an unknown edit Steam's
  files stay as they are, with a note, while the rest is archived; files an RTX-off deployment adopted
  are archived too; a migration that cannot be planned is a note
  ([ADR 0055](docs/decisions/0055-legacy-migration-never-blocks.md)).
- RTX activates when its early render-guard view cannot be prepared (a game update changed
  `includes/init.lua`); the companion guard then installs from its autorun, and a changed owned cache
  is kept aside and rewritten. The view installs only on the machine whose loader wrote it, so a listen
  host no longer gives it to vanilla clients. The guard reports original Lua errors with their stack,
  quarantines only after three consecutive failures and never a gamemode method (hands keep drawing),
  and resynchronizes scopes left open by other add-ons. With `patch_sets.allow_rtx_render_patches:
  false` and no `-insecure` the start stays vanilla instead of running the renderer without its fixes.
  The multiplayer bootstrap has its own menu trigger, no longer runs the RTX scripts twice on listen
  hosts and `sv_allowcslua 1` servers, and reaches the client realm only protected; the helper is
  rebuilt ([ADR 0056](docs/decisions/0056-guard-and-startup-fallbacks.md)).
- RTXDebug 0.2.1 decides "single-player" from the engine (loopback net channel, one slot), not from
  the client realm's Lua, which a server's scripts could replace while replicating `sv_cheats`: a
  malicious insecure server could otherwise reach memory writes for a player launched with
  `-insecure`. Outside local single-player it no longer returns module addresses, file probes, the
  console list or non-rendering convars to server-sent Lua.
- Outline suppression does bounded work per frame and hides only the outline materials of loaded
  models: entities are looked at in turn (256 material slots per frame), texture hashes are looked up
  for at most 16 names per frame and only for new names, names still without hashes (backing off) or
  after Remix's hash revision changed; a missing revision or a refused write no longer causes
  per-frame rescans or warnings, and a removed model's names are dropped. Map textures named
  `*_outline` (stock `white_outline`, `black_outline`) are no longer hidden map-wide. The runtime's
  front-cull shell rule is a separate, console-only opt-in, `nativeloader_ignore_outline_shells`
  (default 0), so flipped view models, their hands and mirrored geometry render by default;
  `nativeloader_ignore_outlines` keeps the name rule
  ([ADR 0059](docs/decisions/0059-outline-shell-rule-opt-in.md)).
- The RTX tab no longer turns the first-person player shadow (`rtx.playerModel.enablePrimaryShadows`)
  back on at every map start: it is requested when the body proxy is turned on, and at start only
  with `nativeloader_remix_reapply`, so a shadow turned off and saved in Alt+X stays off
  ([ADR 0044](docs/decisions/0044-remix-settings-persistence.md)). The menu no longer defines
  `rtx_pseudoplayer`; the RTX fixes own it (default 1).
- Glass Rewrite paces shard data per player: a joiner's full resync goes out at about 16 KB per tick
  instead of all at once (about 920 KB after 256 broken windows could overflow its reliable buffer),
  is granted once per 30 s per player, and single-shard answers are deduplicated and capped per tick.
- The first-person body proxy leaves out only a slot whose material cannot be copied (reported once)
  instead of not drawing at all, reuses its pose snapshot and material list between draws and
  registers each slot once; shared player materials whose legacy tags were removed are no longer
  looked up every second.
- `tools/remix_defaults.py` pins the 1-12 path bounces (ADR 0051) and the shipped layer is regenerated
  from itself (`GarrysMod_RTX_c` is no longer a classic install); `tools/classic_defaults.py` has no
  default reference. `tools/publish_workshop.py` counts `tools/companion_i18n.py`, `LICENSE`,
  `third_party/gmod/LICENSE` and `.gitattributes` as package inputs (a change to one of them alone was
  never published), and a fallback upload whose temporary folder cannot be removed yet is no longer
  reported as failed (the next hook run uploaded it again).
- Runtime patch 0014: Discard Changes and Revert All work without a `user.conf`; a settings file or
  the diagnostic preferences that exist but cannot be read at launch are never saved over; saves retry
  briefly held files, rewrite a linked target in place and show a failure; the outline-shell rule skips
  view models and mirrored geometry (`d3d9.dll` `40a50fd5`).
- **RTX starts no longer crash a few seconds into the map** (found on the PoC, 4 of 8 starts): the RTX
  fixes discard the models' hardware meshes one second after the map's entities spawn, while the
  material system's own thread may still draw them. That one flush now runs with queued rendering
  switched off for a moment, and the player's `mat_queue_mode` is put back.
- **The main menu's text is readable in every language.** GMod reads the loader's generated menu
  script as Windows-1252, which turned the diagnostics panel's separator and every translated label
  into mojibake; the script is now written as ASCII with `\u` escapes.
- `poc_session.py`: `--menu-shot` captures the main menu; the runtime's crash-report prompts are
  declined (No, never Yes) instead of holding the next run until it times out, and the crash's
  minidumps are kept in the evidence first (Remix deletes them once declined). `install-loader.ps1`
  names the way out when a bundle was extracted over an installed loader. Loader version 0.10.1.
- [`tools/qa/release_qa.py`](tools/qa/release_qa.py.md) runs the release QA protocol in one command,
  on the user's install or on the PoC before a publish, and judges each session by its rules.

### Added (agent skills)

- [`skills/`](skills/README.md): `mmd-remix-pbr` (AI PBR materials for MMD characters with `rpai`),
  `remix-map-pbr` (map remasters for RTX Remix) and `workshop-content-pack` (characters and maps with
  their dependencies as hidden Workshop items), written so another agent can repeat the work.

- Loader 0.10.0 hardens RTX graphics-add-on startup (C13): verified early rendering guards,
  scoped later multiplayer installation, process-only stock D3D9 selection and vanilla fallback
  if required V2 preparation fails. Validate rendering resources, preserve session settings,
  quarantine recoverable callback errors and restore only known owned state. Preserve Steam
  files, user settings, native trust and server permissions. Release, actual-package and secure
  dedicated checks pass; original crash reproduction and unavailable add-on sources remain
  limits ([ADR 0054](docs/decisions/0054-rtx-rendering-startup-boundaries.md)).

- Fix Airi's oversized software-skinning rejection by drawing eligible compiled hardware groups
  with their bone weights and strip palettes intact, including the 40,509-vertex clothing fur
  and 62,049-vertex hair. Protect both dynamic and direct hardware entries from unsafe software
  fallback, and keep smaller weighted body meshes visible under existing user-forced hardware
  skinning. Validate oversized strip assignments and restore borrowed draw state; normal default
  draws, flex/eye behavior, the software limit and global skinning cvars stay unchanged
  ([ADR 0053](docs/decisions/0053-oversized-hardware-skinning.md)).

- Loader 0.9.0 adds the user-requested multiplayer bootstrap for verified scripts owned by the
  allowlisted RTX package, including servers with `sv_allowcslua 0`. Community add-ons retain the
  engine's normal permissions. The shipment no longer requests `-insecure`; seven exact rendering
  recipes have a separate opt-out while general patches keep their insecure gate. RTXDebug permits
  rendering configuration in multiplayer and retains its single-player, cheats and insecure gate
  for unsafe commands. A secure dedicated-server join, reconnect and map round trip pass. Scope
  absent-server-channel handling to owned scripts, and avoid late hardware-model cache flushes
  after the world is active; normal early loading keeps its reloads
  ([ADR 0052](docs/decisions/0052-scoped-rtx-multiplayer-bootstrap.md)).

- Default path bounces to minimum 1 and maximum 12 across runtime defaults, graphics presets,
  the packaged layer and the companion's opt-in override. Keep explicit saved settings authoritative.

- Loader 0.8.1 adds a local main-menu diagnostics panel: system hardware, game version/branch,
  loader version/file hash and deployed add-on versions/manifest hashes, with an explicit copy button.
- Point the top-left startup message to this project's GitHub repository and load its text from
  editable UTF-8 templates, in English and six translations. User-edited installed templates persist.

- Add optional geometry-based normals beside imported character/prop spawn controls for RTX,
  preserving imported files and saved texture tags.
- Show original imported material names in AME, retain raw paths in tooltips, and carry the
  current material selection between RTX and Source/VMT workspaces.
- Add a dedicated, translated Motion importer spawn-menu tab opening the existing VMD manager.

- Diagnostics default to declined, including legacy implicit grants. The welcome window closes
  after twelve seconds unless interacted with, and permanent dismissal is saved independently.
- Keep animated toolgun text readable by drawing its live screen after upscaling; the RTX tab
  provides a translated toggle, and custom screen animation remains active.
- Resolve layered alpha cutouts inside the original ray traversal so transparent layers cannot
  skip the valid face behind them, including before or without opacity micromaps.
- Hide incompatible outline meshes by default, including the supplied alternate-skin outline;
  the translated Model outlines panel provides an opt-out.

- Update the in-game Common Remix guide and its six translations to explain explicit startup
  overrides and saving through Alt+X.

- Fix Common Remix sliders turning unset settings into archived zeros. Remix's saved settings now
  win at launch unless startup overrides are explicitly enabled; numeric overrides require a
  selection. Runtime saves replace files atomically, retain unsaved state on failure, and failed
  reloads keep live edits ([ADR 0044](docs/decisions/0044-remix-settings-persistence.md)).

- Keep first-person arms visible independently of primary-space player bodies. Isolate local-body
  texture categories so shared-texture players and ragdolls stay visible, and add translated RTX-tab
  controls for local-player shadows and body height ([ADR 0043](docs/decisions/0043-player-body-viewmodel-and-shadows.md)).

- Loader 0.8.0 automatically archives a recognized prior RTXLauncher/Remix installation before
  deploying the shipment. Restore ten known legacy-modified Steam files from verified vanilla
  copies, archive obsolete runtime/addon files and factory configs, and preserve user.conf,
  personal mods and data. Backup and replacement share the crash-recoverable deployment
  transaction; uninstall retains the legacy archive ([ADR 0042](docs/decisions/0042-legacy-remix-migration.md)).

- Keep Lua sidecar documentation in source inputs and out of deployed addon scripts, fixing GMod trying to include `procedural_shard.lua.md` as an entity script.
- Fix Hotloader's unknown `DepthWrite` shader errors on RTX Remix: initialize backend detection before material registration, avoid unsupported depth clones/passes on the fixed-function path, and retain normal Source depth rendering ([ADR 0041](docs/decisions/0041-hotloader-remix-depth-materials.md)).
- Native map glass (`func_breakable`, including Modern House) now leaves scattered, persistent, networked physics shards when it breaks. Preserve native health and outputs, support horizontal/rotated panes, bound the debris pile, and batch late-join mesh updates ([ADR 0040](docs/decisions/0040-native-map-glass-debris.md)).
- Loader 0.7.0 presents deployed native Workshop packages through inert display archives: suppress their mount/whitelist warnings, show blue addon cards and the normal Workshop description. Steam/depot files and GMod's whitelist stay unchanged ([ADR 0039](docs/decisions/0039-native-package-addon-presentation.md)). The Workshop publisher can retry one reviewed build whose stale Steam process check fails, after real Steam API initialization succeeds.
- Complete the six-language companion and bundled RTX interfaces; add Korean to Destruction and
  separate Traditional Chinese to the remaining add-ons. Fix ambiguous material labels, untranslated
  motion-wheel states, weather status and migration buttons, and unclear terminology. Package/runtime builds now reject
  incomplete catalogs; new checks exercise language selection, placeholders and metadata updates.


### Fixed (emergency: frame generation off by default)

- **The RTX package no longer turns DLSS frame generation on at 3x**
  ([ADR 0037](docs/decisions/0037-frame-generation-off-by-default.md)). The classic install's settings,
  made on an RTX 5090, set DLSS-G with two generated frames, which crashed RTX 30, RTX 40 and AMD GPUs at
  start; Remix's menu hides the multiplier where multi-frame generation is unsupported, so RTX 40 players
  could not lower it. The package's Remix layer now has frame generation off and one generated frame (2x)
  for whoever turns DLSS-G on; RTX 50 players raise it in Remix's menu. `tools/remix_defaults.py` forces
  these three options whatever the classic install has.

### Fixed (R3-017: the package's Remix settings on every GPU; loader 0.6.0)

- **The runtime reads the package's Remix layers from short copies**
  ([ADR 0036](docs/decisions/0036-remix-layers-as-short-copies.md)). The runtime ignores a
  `DXVK_CONFIG_FILE` of 260 characters or more and then loads `dxvk.conf` alone; the published
  package's list was 237-241 characters on an NVIDIA GPU and 273-277 without one, so on AMD and Intel
  GPUs an RTX session ran without the package's settings. Each RTX start now writes the package's
  layers, byte for byte, to `native-loader\remix\dxvk-<n>.conf` (and `rtx-<n>.conf`) and lists those:
  73 characters, 109 without an NVIDIA GPU, whatever the version. `status.json` `activation.layer_copies`
  and `nlctl activation` give each copy's source; a copy that cannot be written falls back to its
  source with a note. `install-loader.ps1 -RemoveState` removes the copies.
- **`install-loader.ps1` keeps its rollback copies as byte arrays.** `$x = if (...) { ReadAllBytes }`
  enumerated the old DLL and PDB into arrays of boxed bytes: over a gigabyte for a Debug build's 35 MB
  PDB, 3.1 GB at the peak of the installer's tests, which failed with `OutOfMemoryException` while a
  game held most of the machine's memory. Now 236 MB at the peak.

### Changed (restore automatically; loader 0.6.0, R3-001)

- **The package's files are put back** ([ADR 0035](docs/decisions/0035-restore-automatically.md), the
  user's decision on R3-001). A `replace-owned` file the loader placed that changed since is replaced
  by the package's copy at the next start, also when the package has a new version; the changed copy
  is kept in `native-loader\backup\edits\<transaction>\`. Until now it stayed in place for good.
- **A file in a package's way is taken over** instead of stopping the package: it is kept in
  `native-loader\backup\originals\` (journal `originals`) and put back once no generation names its
  path, at once when its Workshop item is unsubscribed, and at `nlctl uninstall`. An identical file is
  still adopted, until it changes or a new version differs. Reports show `put-back`, `take-over` and
  `restore-original`. AGENTS.md rule 3 reads accordingly.
- **A module's `load_first` files load only as the loader deployed them** (journal record, size and
  time), with RTX and without; otherwise a session note says why one was left out (R3-001).
- **`install-loader.ps1` keeps a foreign `winmm.dll`** (another mod's loader) with its PDB in
  `native-loader\original\` and puts it back at `-Uninstall`, instead of refusing to install. The
  player README says to keep a copy before extracting the zip over one.

### Fixed (R3-016: limbs in bind pose on Modern House)

- **Modern House RTX** (test item 3829275998) no longer sets `r_forcehwlight 1`. With it, the RTX
  fixes light every model on the GPU, and with `r_forcehwskin 0` Source then skins a model without a
  `.sw.vtx` through a fixed-function path that never sets the vertex-blend state Remix reads, so the
  model was drawn rigid on its first bone: limbs, clothes and hair around the pelvis (new HSR models,
  ragdolls, the player). Found in the live game with a runtime probe; the item was updated.

### Fixed (review R3: robustness, stability, bugs; [triage](docs/handover/R3-triage.md))

- **Unpacking `packages/`** checks every file it keeps by SHA-256, not by size and time (R3-003), and
  refuses links and junctions anywhere in `out\inputs` before the first write, so its clean-up can no
  longer delete files elsewhere (R3-006). **Importing** hashes every source, so a change that keeps
  a file's size and time is stored, and refuses a source changed since the packager's inventory
  (R3-007); the index is written atomically.
- **The combiner** checks every part's file paths before writing anything: an absolute path in a
  part's manifest had emptied that file outside the package (R3-008).
- **Publishing** builds from the checkout that has the pushed commit checked out (`--commit`, which
  every hook passes): a push of `main` from a worktree on another branch had built that worktree's
  package (R3-004). The publish lock is a Windows file lock held for the whole run, so two runs can no
  longer both take it (R3-005).
- **The runtime build** (`runtime/build_runtime.ps1`) compares the worktree exactly with what it
  should hold, and `tools/check_repo.py` fails while `runtime/` differs from what the stored
  `d3d9.dll` was built from (R3-014, [ADR 0034](docs/decisions/0034-the-runtimes-build-inputs-recorded.md)).
  That check found the shipped runtime built with NVAPI R615, three uncommitted RTXDI shader changes
  and the DLSS and SHARC SDK clones, none of which `runtime/patches` held; `runtime/base.json` and
  `runtime/submodules/rtxdi.patch` now record them. `-Verify` checks a worktree without building.
- **Clearing the weather** ("leave to Remix") puts every option the weather set back to rtx.conf's
  value, or what Remix has without it, instead of leaving the last preset in place (R3-009).
- **The sky moves smoothly:** it updates 50 times a second instead of 4 (`nativeloader_sky_interval`,
  default 0.02 s, 0 for every frame; a slider under "Sky and weather", in all six languages), and the
  rain's fade under a roof follows the time passed (R3-015, the user's).
- **Licences travel with the package:** Model Hotloader's licence and its 27 libraries' licence texts,
  Character Motion Importer's licence, and the RTX fixes' GPL-2.0 text, beside their add-ons
  (`--add-to-addon` in `package_content.py` and `package_fixes.py`; R3-011).
- `install-loader.ps1 -DefaultConfig` checks the default settings before installing and writes them
  inside the same rollback (R3-012). `poc_session.py --workshop` waits up to 20 s for a remount after
  a partial first Workshop mount (R3-013).

### Changed (one repository builds everything: the package's inputs in Git LFS)

- **This repository alone builds the RTX package**
  ([ADR 0033](docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)). Every input of its ten
  parts now lives in [`packages/`](packages/README.md): text as it is, binaries xz-compressed in Git LFS
  (1.8 GB stored in 0.6 GB), each part indexed with sizes, SHA-256s, times and where it came from.
  `tools/workshop.json` names only paths in this repository. The first build from `packages/` gave the
  published package byte for byte, so the item did not change.
  - **New tools:** [`tools/inputs.py`](tools/inputs.py.md) (import from a packager's inventory,
    unpack into `out\inputs`, verify, also against LFS pointers) and
    [`tools/build_package.py`](tools/build_package.py.md) (the package into `out\dist`, optionally
    compared with the item's upload). `tools\workflow.ps1 -Package` runs it after the Release checks.
  - **CI:** [`.github/workflows/package.yml`](.github/workflows/package.yml) builds the package from
    `packages/` on changes to its inputs and by hand, with the LFS objects cached between runs.
  - **The runtime fork's changes are [`runtime/patches`](runtime/README.md)**, four `format-patch` files
    against the fork commit in `runtime/base.json` (the snapshot, the translated menus, the glossaries,
    the sky). [`runtime/build_runtime.ps1`](runtime/build_runtime.ps1.md) applies them in a fork
    worktree, builds twice and imports `d3d9.dll`; nothing is pushed to the fork any more.
  - **The sky texture tools** moved from scratch into [`tools/sky`](tools/sky/make_moon_textures.py.md).
  - **No more hooks in other repositories:** the ones ADR 0024 put in the five add-ons' repositories
    were removed and `--install-source-hooks` is gone. An add-on's new version reaches the item by an
    import here.
  - **The hooks run Git LFS's steps** (`pre-push` uploads the LFS files first and refuses a push
    without git-lfs). Reinstall them in every clone: `python tools\publish_workshop.py --install-hooks`.
  - AGENTS.md rules 6 and 7 changed with it: binaries only in `packages/`, through the import; the RTX
    fixes vendored unmodified with their GPL-2.0 licence.

### Added (the real Moon and night sky, eclipses, fog presets; runtime-b6)

- **The real Moon, the real night sky, and lunar and solar eclipses**
  ([ADR 0032](docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md)). The RTX package's
  runtime part is now `out\packages\sky\runtime-b6.gma`: runtime-b5 with a `d3d9.dll` from the runtime
  fork's branch `claude/sky-night` and an `atmosphere` folder beside it, with the credits in
  `CREDITS.txt`:
  - the Moon's albedo and relief maps, from NASA's Scientific Visualization Studio;
  - the night sky's star, galaxy and nebula layers, from the Skyrim mod Night Sky HD LE by
    PraedythXVI (its permissions allow reuse with credit), its nebulae edited from Era-7's free
    nebula images (used with permission).
  - **The Moon** has the real Moon's face, lit as a sphere from the sun's side of the sky, its relief
    showing along the terminator and earthshine on the night side. "Moon" has eight phases now,
    waxing and waning.
  - **The night sky** is a sharp image of small stars, a galaxy band, nebulae and constellations,
    drawn the way the Skyrim mod draws it, turning with the hour, the season and the map's north.
    "Night sky" switches back to the procedural stars. Under the image the weather's airglow drops
    to 5 %, so space between the nebulae is dark as in Skyrim. The image adds about 220 MB of GPU
    memory while it is on.
  - **The Moon's shadow edge stays smooth** close up: it follows the sphere, softened over about two
    pixels, the companion sets the relief to 0.6, and the sky's textures pick their mips the way the
    materials do under DLSS. Zoomed in to a few degrees the Moon still shows small blocks.
  - **Eclipses.** "Eclipse" (none, lunar, solar) and "Eclipse progress" (0 first contact to 100 the
    middle) in "Sky and weather".
    - A lunar eclipse darkens the full moon through the penumbra and turns it copper red in the
      umbra (total from 70), and the moonlight dims and reddens with it.
    - A solar eclipse covers a drawn sun disc and dims the daylight. At totality (from 90) it shows
      the corona and the stars.
    - Choosing one moves the clock to midnight or noon if the sun is on the wrong side of the horizon.
  - **Fog presets under Remix settings.** "Fog" offers Remix's own volumetric presets (Remix default,
    heavy fog, light fog, mist, haze, dust, smoke), applied as Remix's menu applies them. While one is
    chosen the weather leaves the fog alone.
  - The guide's settings page describes them, in the six languages too.
  - **Shaders compile on every hardware thread but two.** The classic install's `dxvk.conf` held
    `dxvk.numCompilerThreads = 1`, so a first start (or one after a runtime update) showed "Compiling
    shaders" for minutes. runtime-b6 adds a second dxvk layer, `02_compiler_threads.conf`, with `-2`.
    The fork now reads a negative count as "all threads but that many": 30 workers on a 32-thread CPU.
  - Facts and measurements: [RESEARCH.md](docs/RESEARCH.md) section 29.

### Added (sky and weather)

- **A physical sky with a time of day and weather** ([ADR 0031](docs/decisions/0031-physical-sky-time-and-weather.md)).
  RTX sessions now use the runtime's physical sky instead of a frozen afternoon. The companion's new
  module ([`nativeloader_sky.lua`](companion/nativeloader/lua/autorun/nativeloader_sky.lua.md)) adds
  "Sky and weather" to the RTX Remix tab:
  - **Sun, moon and stars from one clock.** The sun, the moon of a chosen phase and the stars are
    placed for a time of day and a season at latitude 40 ([`sky_model.lua`](companion/nativeloader/lua/nativeloader/sky_model.lua.md)).
    By default the sky follows the map's own sun (its `light_environment`): the time at which the sun
    stands that high, turned to stand where the map's does. Maps whose sky is named for the night start
    at night.
  - **Choosing.** A time of day, the sun's direction, the season, the moon, and buttons for sunrise,
    morning, noon, sunset and night. The clock can run (`nativeloader_sky_time_passes`,
    `nativeloader_sky_day_minutes`). Console: `nativeloader_sky_time sunset|noon|18:30|...`,
    `nativeloader_sky_status`, `nativeloader_sky_reset`.
  - **Weather.** The runtime's twelve presets, from clear to thunderstorm, snow, blizzard, sandstorm
    and smog, blended over a chosen time with their slow variation of cloud cover and wind. They are
    generated from the fork by [`tools/weather_presets.py`](tools/weather_presets.py.md).
  - **Scaled for GMod's maps.** Fog is set from a visibility in real metres, rain and snow fall
    around the player, and they fade out under a roof.
  - **Other changes to the look.** Cumulus-shaped cloud shadows move over the ground again. The moon
    is about three times its real size instead of seven, with its moonlight kept. That light fades
    in with the twilight, so a rising moon no longer lights the map orange at dusk.
  - **Modern House RTX** keeps its own sky on `modern_house` unless the player changes a sky setting.
  - "Remix settings" loses sun height, sun direction, clouds, fog distance and fog scattering: the new
    panel and the weather own them now. Saved values of those settings are no longer applied.
  - Translated into the six languages.
- **`poc_session.py --lua FILE` and `--lua-shots`**: a client Lua file sent through the console, which
  paces its own screenshots (`NL_SHOT <label>`, answered with `nl_shot_taken`), so one session can
  tour many views or settings.

### Added (round 8; loader 0.5.0)

- **ReShade in RTX sessions** ([ADR 0028](docs/decisions/0028-reshade-in-rtx-sessions.md)). RTX Remix
  draws through Vulkan, so a ReShade installed for Direct3D 9 has nothing to work on with RTX.
  - The Direct3D 9 ReShade (`bin\win64\d3d9.dll`) never loads into an RTX session: the game binds the
    runtime's `d3d9.dll`, preloaded at the entry point. Its files are never written, so without RTX
    it works exactly as before.
  - The RTX package carries ReShade 6.8.0 (by crosire, BSD 3-clause), unchanged from the official
    setup, as the Vulkan layer `VK_LAYER_nativeloader_reshade` ([`package_reshade.py`](tools/package_reshade.py.md),
    manifest section `reshade`, kind `reshade`).
  - In RTX sessions the bootstrap enables it (`remix.reshade`: `"auto"`, the default, when the game
    has a ReShade or RTX sessions have settings of their own; `"on"`; `"off"`), with its own settings
    folder `native-loader\reshade`. The first RTX session copies the game's `ReShade.ini` there, paths
    made absolute and presets copied; later sessions keep it. `status.json` `activation.reshade` and
    `nlctl activation` say what happened.
  - The RTX package now needs loader 0.5.0.
- **The companion in six languages** ([ADR 0029](docs/decisions/0029-companion-translations.md)): the
  RTX Remix tab, the guide and the update notice in Simplified and Traditional Chinese, Japanese,
  Korean, French and Russian. The language follows Garry's Mod's; "Start here" can choose another
  (`nativeloader_language`). The text is in gettext files in [`companion/i18n`](companion/i18n/README.md)
  for review; [`companion_i18n.py`](tools/companion_i18n.py.md) makes and checks them, and the RTX
  package's build puts them into the add-on.
- **`poc_session.py run --fps SECONDS`** times every frame in the game (a client `PostRender` hook)
  and records frames, the frame rate, the median, 99th-percentile and longest frame.
- **Computers without an NVIDIA GPU start from Remix's own preset** ([ADR 0030](docs/decisions/0030-non-nvidia-gpus-and-late-runtime-dlls.md)).
  The package's classic settings pin the Custom preset, tuned for an RTX 5090. With no NVIDIA adapter
  (DXGI), the bootstrap adds `native-loader\remix\non-nvidia.conf` (`rtx.graphicsPreset = 5`) above the
  package's layers and below the user's own files. NVIDIA systems see no change. The player README
  says what was tried on AMD: a Ryzen's integrated Radeon loses its GPU about a minute into an RTX
  session (RESEARCH.md section 27); no Radeon card was available.

### Fixed (round 8)

- **FSR and the Neural Radiance Cache never loaded under the loader** (since M5, ADR 0030). The
  runtime loads `amd_fidelityfx_vk.dll` and CUDA's `cudart64_13.dll`, `nvrtc64_*.dll` and
  `nvrtc-builtins64_*.dll` late, by bare name. By then no search finds the runtime folder: the process's
  `PATH`, where the loader had put it, has been rewritten without it (the Steam folder in front), and
  the game's standard search never reads `AddDllDirectory` folders. The Remix log said "FSR ... could
  not be loaded" and "Failed to initialize NRC" in every loader session. The bootstrap now loads these
  four right after the runtime, by absolute path, and the late loads bind to them (`status.json`
  `activation.preloaded`). AMD players get FSR; NVIDIA players get NRC back, as in the classic install.
- **Labels of the RTX Remix tab no longer cut off**: "Post effects", the fog sliders, the guard and the
  language choice have short labels, with the rest on a help line.
- **The Workshop publish checks packages with the main checkout's built `nlctl.exe`**, so the merge of
  round 8 failed to publish until that build knew the `reshade` manifest key. AGENTS.md rule 5 and
  `publish_workshop.py.md` now say to build Release in the main checkout after a manifest change.

### Added (the RTX Remix menus in six more languages)

- **The Remix menus (Alt+X) in Simplified Chinese, Traditional Chinese, Japanese, Korean, French and
  Russian.** The RTX package's runtime part is now `out\packages\i18n\runtime-b5.gma`: runtime-b4 with
  a `d3d9.dll` built from the runtime fork's branch `claude/remix-i18n`.
  - A language combo at the top of the graphics settings window's General tab and of the developer
    menu (`rtx.gui.language`, English by default; **Save Settings** keeps it in `user.conf`). The menus
    switch at the next frame.
  - Translated: labels, buttons, headers, combo entries, messages, tooltips, and the descriptions of
    the options the menus show (3,293 messages). The text is one UTF-8 `.po` file per language in the
    fork's `i18n` folder, which the build embeds: an edited file is in the next build.
  - Chinese, Japanese and Korean glyphs come from subsets of Noto Sans SC, TC, JP and KR (SIL Open
    Font License 1.1); the font atlas holds only the selected language's glyphs.
  - Facts and measurements: [RESEARCH.md](docs/RESEARCH.md) section 25.

### Changed (the seventh field round; loader 0.4.0)

- **Content packages from any subscribed Workshop item load without the allowlist**
  ([ADR 0027](docs/decisions/0027-content-packages-from-any-subscription.md)). Players cannot change
  the allowlist after installing, so a PBR package someone else publishes (such as 3829348717) never
  loaded.
  - Start-up now opens every subscribed item whose `.gma` lists `native/manifest.json`.
  - Such a package may hold only Remix mods (USD, textures, MDL) and Lua add-ons (GMod's Workshop
    whitelist). One with native code is skipped with a reason telling how to allowlist it; native code
    still comes only from `allow.workshop` (the RTX item).
  - `"allow": {"subscribed_content": false}` turns it off. Deployed content keeps keep-last-good, and
    unsubscribing or disabling the item removes it.
  - The subscriptions are read from the library the game sits in. Steam's library list is used only
    for an allowlisted Workshop item, so a game copied elsewhere scans none.
  - `nlctl plan` marks such candidates as "(subscribed, content only)".

### Fixed (the seventh field round)

- **"Disabling motion blur will break addons' effects..." every second.** Draconic Base (1847505933)
  checks motion blur once a second and asks for it again; the RTX session guard keeps it off for
  Remix, so the line came back every second. In RTX sessions, Lua that reads `mat_motion_blur_enabled`
  (through `GetConVar`, which `GetConVarNumber` also uses) now sees it on, while the engine keeps it off.
  Measured on the PoC with Workshop add-ons: no such line in a whole session, and no Lua errors.
- **`poc_session.py run --workshop` no longer loads a map before the Workshop is mounted.** A map
  requested while GMod still fetched the ~755 subscriptions waited on the fetch, and the game stopped
  answering (or exited -1). The run now starts at the menu, waits for the second "Mounted N of M
  workshop addons!" and a quiet log, then sends `map`.

### Fixed (the sixth field round)

- **Model Hotloader no longer warns about its runtime in RTX sessions**
  ([ADR 0026](docs/decisions/0026-addon-file-from-its-repository.md)). It printed "Missing
  bin/win64/mmdhl_runtime_win64.dll" and "The loaded runtime DLL is not the file that was checked" on
  both realms in every session, because its check looked only in `bin\win64` while the loader loads the
  runtime from `garrysmod\lua\bin`.
  - The check now accepts the copy in `lua\bin` when the game loaded that copy. That fix is commit
    `bed4582` on Model Hotloader's `main`, pushed at the user's request.
  - The RTX package takes that one file from there until the classic install has it.
  - Measured on the PoC: no runtime warning, the native module live on both realms
    ([RESEARCH.md](docs/RESEARCH.md) section 23).
- **`package_content.py --addon-file PATH FILE`:** one file of a bundled add-on from elsewhere. Only a
  file the add-on has can be replaced, and FILE counts as a publish input.
- **Commits in the add-ons' and the fork's repositories now update the Workshop item.** The source
  hooks of round 4 ran `publish_workshop.py` with git's hook environment (`GIT_DIR`, `GIT_INDEX_FILE`),
  which pointed its git calls at the source repository.
  - Every such run therefore refused ("uncommitted changes in the packaging inputs") and left its log
    in that repository's `out\workshop\logs`. Found when the Model Hotloader fix was committed.
  - The script now drops git's repository-local variables first.

### Changed (the fifth field round; loader 0.3.1)

- **Unsubscribing from a Workshop item uninstalls its package**
  ([ADR 0025](docs/decisions/0025-unsubscribe-removes-the-package.md)). Before, RTX Remix kept running
  after an unsubscribe, without updates: keep-last-good took the missing item for a download in
  progress.
  - Discovery now marks an item unsubscribed when `appworkshop_4000.acf` lists it in neither
    `WorkshopItemsInstalled` nor `WorkshopItemDetails` and its folder is gone. That is what Steam leaves
    once it cleans up, at the next launch from Steam, before the game starts
    ([RESEARCH.md](docs/RESEARCH.md) section 22).
  - Start-up treats that as the user's removal, like an item disabled in GMod's addon list.
  - The deployer keeps no rollback copy of such a package. Its payload folders and the root files it
    moves aside are deleted in the same run, so nothing of the package is left.
  - Files the user changed after the loader placed them stay, as on every removal.
  - Tested with unit cases, the synthetic activation test, and a kill or a failure at every change
    (`nl_tests_faults_unsubscribe`).

### Added (the fourth field round; loader 0.3.0)

- **The RTX package bundles the user's five add-ons**
  ([ADR 0024](docs/decisions/0024-bundled-addons-and-module-dependencies.md)):
  - Model Hotloader 2.3.1 with its binary modules, runtime, worker and CoACD;
  - Advanced Material Editor with its RTX bridge module;
  - Advanced Bodygroup Tool, Procedural Bodygroup Destruction and the Character Motion Importer.

  Each is a part of `workshop.json` rebuilt from its source at every publish. Commits in their
  repositories, and on any branch of the fixes fork and of Model Hotloader's repository, start a
  publish (`publish_workshop.py --install-source-hooks`). The fixes module another session rebuilt
  with a tuned visibility rule ships the same way.
- **Module dependencies (loader 0.3.0):** a manifest's `module_dependencies` names files a binary
  module needs loaded first. Model Hotloader's modules import `mmdhl_runtime_win64.dll`, which Windows
  looks for next to `gmod.exe`. The bootstrap loads it from `garrysmod\lua\bin` by absolute path just
  before the game loads the module, in every session, so nothing goes into `bin\win64`. Reported in
  `status.json` and `session.json`; tested in the synthetic M5 session test.
- **`package_content.py`:**
  - add-ons as gmad publishes them (GMod's whitelist and the add-on's `addon.json` ignore list);
  - `--addon-as` for another folder name, and `--ignore`;
  - `--lua-bin` for binary modules, and `--load-first` for their runtimes;
  - hard links only with `--link`.
- **`package_workshop.py`** merges `module_dependencies`.

### Fixed (the third field round)

- **The player's own model was drawn in first person again** (the pseudo player). The classic
  install's `server.vdf` keeps stale `1`s for `rtx_pseudoplayer`, `rtx_pseudoweapon` and
  `rtx_disablevertexlighting`, against `0` in its `client.vdf`. In single-player both realms share
  these variables, so applying the server table switched the pseudo player back on.
  - The generated table now keeps a name saved for both realms in its client table only.
  - Version 3 applies the corrected values once more, where they are still at their defaults.
  - [RESEARCH.md](docs/RESEARCH.md) section 20.

### Added (the third field round)

- **The Emissives Remix mod ships in the RTX package**
  ([ADR 0023](docs/decisions/0023-content-packages-and-modern-house-item.md)). HL2's fluorescent tube
  lights (gm_construct's basement and elsewhere) now light their rooms: measured twice as bright as
  without it. The classic install's Water mod does not ship: its textures are on the ignore list, so it
  never draws.
- **The user's `Remove_halo` add-on ships in the RTX package**: in RTX sessions `halo.Add` does
  nothing, so no add-on creates halos. It is rebuilt from the user's folder at every publish
  (`publish_workshop.py` gains the `package_content` builder).
- **`tools/package_content.py`:** content packages, Lua add-on folders and Remix mod folders with no
  native code. For an archive alone it hard-links its work folder, so gigabytes of textures are not
  copied twice.
- **Modern House RTX as its own package**, `modern-house-rtx` (the remaster's Remix mod and Lua,
  3.3 GB). It is uploaded as the hidden Workshop test item 3829275998, subscribed, and played in the
  field install from there.

### Fixed (the second field round: rendering parity with the classic install)

- **Remix settings saved in the menu came back at the next start.** In the runtime fork the first
  entry of a layer list is the strongest, so the package's layer beat the player's saved `rtx.conf`
  ([ADR 0021](docs/decisions/0021-remix-defaults-in-one-low-layer.md)).
  - The package now ships its Remix defaults as one low `DXVK_CONFIG_FILE` layer and leaves
    `DXVK_RTX_CONFIG_FILE` unset.
  - The player's `rtx.conf` and `user.conf` now win.
- **The classic RTX install's settings are now the defaults**
  ([ADR 0020](docs/decisions/0020-classic-rtx-settings-as-defaults.md)).
  - Its `dxvk.conf`, `rtx.conf` and `user.conf` are merged into that layer
    (`tools\remix_defaults.py`). Texture-hash lists combine as Remix layers do.
  - The RTX add-ons' settings get the classic values once, where still at their defaults (companion,
    `tools\classic_defaults.py`). Examples: no pseudo player or pseudo weapon, the light updater
    instead of hundreds of API map lights, and the classic flashlight and water.
  - This fixes the MMD player model drawn in first person through the pseudo player, the fog-filled
    pool rooms, and the colour cast.
- **The runtime is forced windowed** (`DXVK_FORCE_WINDOWED=1` in the package), so even an in-game
  switch to fullscreen cannot reach the crash of ADR 0018.

### Added (the second field round)

- **A guard for RTX sessions in the companion**
  ([ADR 0022](docs/decisions/0022-companion-rtx-session-guard.md)). Lua from other add-ons can no
  longer undo the session's settings or switch motion blur on (FPS Boost, Draconic Base). Stock
  post-processing no longer paints over the path-traced image. `nativeloader_guard 0` turns it off.
- **One "RTX Remix" spawn-menu tab.** The RTX add-ons' panels are gathered there, with "Start here"
  and "Remix settings" (preset, upscaler, DLSS, frame generation, indirect lighting, bounces, fog,
  sky, sun, clouds, post effects). Those settings are kept across sessions.
- **An in-game guide** (`nativeloader_guide`, opens once). It covers the Remix menu and how settings
  persist, the classic defaults, lights, and troubleshooting with the log files.
- **The companion reports whether the RTX fixes reached the Remix API** ("Remix API: ready").
- **The RTX debug module ships with its add-on** (`rtx_debug`; `package_fixes.py --with-debug-module`).
- **Loader:** a layer list of 260 characters or more, which the runtime would ignore, is reported in
  the session notes.
- **`poc_session.py`:**
  - `--change-map` loads a mounted Workshop map without a save;
  - `--mount-workshop` takes several items;
  - `--no-window` uses the game's own window settings;
  - console commands wait for the console to go quiet.

### Fixed (the first field test of the release bundle; loader 0.2.1)

- **RTX sessions crashed to the desktop about 9 s after start** when the game ran in exclusive
  fullscreen. The Remix runtime crashes in its window procedure when the engine switches the
  fullscreen device; reproduced on the PoC with the field's launch options.
  - The loader now starts RTX sessions in a borderless window the size of the primary display:
    `-windowed -noborder -w <width> -h <height>`, as RTXLauncher does.
  - A window mode in the player's launch options is used as it is
    ([ADR 0018](docs/decisions/0018-rtx-sessions-in-a-borderless-window.md)).
  - The loader version is 0.2.1.

### Added (local build workflow)

- **`tools\workflow.ps1`** runs CI's build job on this machine: the Release checks (or `-SkipTests`),
  then the end-user bundle in `out\dist`. `-Install <game root>` puts the build into a game.
- **`install-loader.ps1 -ReplaceUntracked`** replaces a loader no receipt records, such as a bundle
  extracted by hand. It keeps a copy in `native-loader\replaced` first.

### Changed (rules)

- **Agents push `main` and update the project's Workshop items without asking** (the user,
  2026-10-28; [ADR 0019](docs/decisions/0019-agents-push-main-and-update-workshop.md)). Other branches,
  tags, force pushes and item visibility still need the user.

### Fixed (CI's first run)

- **`nl_activation_integration` failed on GitHub's runner** (run 40779899329).
  - The test read `nlctl`'s UTF-8 output in the runner's code page, cp1252. A non-ASCII config-file
    name came back garbled, so the CLI's plan seemed to differ from start-up's. The loader was right.
  - Tests now read `nlctl` and the C++ test hosts as UTF-8, and open journals as UTF-8.
  - With text decoded as cp1252, the test passes all 17 cases.
- **The workflow uses the Node 24 versions of its actions** (checkout v5, setup-python v6,
  upload-artifact v6, download-artifact v7). This ends GitHub's Node 20 deprecation warning.

### Added (CI and the release bundle, ADR 0017)

- **GitHub Actions** (`.github/workflows/build.yml`) builds `winmm.dll` on every push of `main`, every
  pull request, and on demand.
  - It runs `tools\test.ps1 -Config Release` on `windows-2022` and keeps the end-user bundle as an
    artifact.
  - A `v*` tag makes a GitHub release with it.
- **The end-user bundle** (`tools/package_loader.py`): a zip to extract into the Garry's Mod folder,
  holding `bin\win64\winmm.dll`, a default `native-loader\config.json` that allows Workshop item
  3829070317, and a README. The PDB ships in a symbols zip. Tested as a player would use it on the
  PoC: the loader found the item by itself, deployed it and activated RTX.
- **`install-loader.ps1 -DefaultConfig`** writes the same default config for a developer install,
  never over an existing one.

### Added (the Workshop distribution item, ADR 0016)

- **Workshop item 3829070317 now carries the RTX package subscribers use.** It is one combined
  package, `gmod-rtx-remix`: the RTX Remix runtime (runtime B, as tested in M5, M7 and R1) and the
  RTX fixes with the Lua companion. A subscriber needs only the loader's `winmm.dll`, a
  `config.json` that allowlists the item, and the subscription.
  - **First upload,** 2026-10-28: version `0.0.0-dev.20261028213205+1e486ed0`, 1,426,861,733 bytes.
  - **Checked as a subscriber** would get it, on the PoC: Steam's download was byte-identical. The
    loader deployed it from the Workshop folder. RTX on path-traced (7 of 7 patch sets, the shader
    override, 33 session variables). RTX off was vanilla, with the 9 add-on folders hidden. All
    depot files were OK afterwards.
- `tools/package_workshop.py` merges native packages into one, from folders or `.gma` archives.
- `tools/publish_workshop.py` builds the package from `tools/workshop.json` and uploads it with
  `gmpublish` only when its content changed. Its git hooks run it in the background after commits
  and merges on `main` and before pushes of `main`.

### Added (M6 follow-up: the Workshop route, tested)

- A private Workshop upload test, run with the user's approval.
  - **Upload:** GMod's `gmpublish` accepted a native package packed with `tools/gmapack`.
  - **Download:** Steam served it back byte for byte.
  - **Deploy:** the loader deployed it from Steam's Workshop folder.
  - **Update:** an update deployed at the next start.

  GMod itself does not mount an archive holding native files, so such a package's Lua comes through
  the loader's add-on folders ([ADR 0015](docs/decisions/0015-workshop-route-for-native-packages.md),
  superseding part of ADR 0012; ADR 0011 confirmed by the user).
- `tools/gmapack` is recorded as the user's own code under this repo's MIT licence (R1-025).
- **Corrected:** GMod's Steam Workshop rules do not forbid DLLs or other runtime files; they have no
  rule about file types. The wiki's `.dll`/`.exe` list describes what `gmad.exe` packs. ADR 0012
  (in a correction note), ADR 0015, the M6 report, the R1 triage and the roadmap had said otherwise.
- **New rule (AGENTS.md rule 5, the user's instruction):** agents may upload and update hidden test
  items for this project on the Workshop without asking. Nothing on the Workshop is removed or deleted
  until the user says the project is done, so test item 3829070317 stays. The earlier advice to delete
  it is withdrawn.

### Changed (R1: whole-repo review)

Codex reviewed the whole repository and reported 29 findings. All of them are triaged and fixed, or
answered ([R1 report](docs/handover/R1-report.md), [triage](docs/handover/R1-triage.md),
[ADR 0014](docs/decisions/0014-r1-hardening.md)).

- **Package areas are narrower.**
  - `garrysmod/cfg` is no longer a package area: it holds 18 of Steam's files, and a package could
    recreate one that was missing.
  - In `rtx-remix/mods`, `garrysmod/addons` and `garrysmod/data`, every file must be inside a named
    folder.
- **Activation checks deployed files.** It checks the journaled size and time of every runtime,
  config-layer and override file. A file changed since deployment is not loaded.
- **The session-variable restore keeps the user's changes.** It runs only with a readable journal, and
  puts a value back only while `config.cfg` still holds what the RTX session set.
  `session_cvars.json` is schema 2; schema 1 is still read.
- **`uninstall-loader.ps1 -RemoveConfig` keeps changed files.** It deletes the loader's own files
  only. A payload file the user changed stays, and a warning lists it.
- **`tools\test.ps1` builds first**, so the Python tests' native cross-checks run.
  **`tools\build.ps1`** puts the caller's environment back when it ends.
- **`field_snapshot.py`** (snapshot schema 3):
  - rollback never deletes; an entry it cannot move stays and is listed;
  - nothing is written through a link;
  - every saved copy is checked before anything changes;
  - the registry is pruned only after a verified import;
  - a Steam-managed install needs its depot manifests (or `--no-depot-check`), and Steam's files are
    never written back;
  - `native-loader/config.json` is kept;
  - older snapshots are refused.
- **`poc_session.py`:**
  - it sends client Lua through the console, hex-encoded, and writes nothing into an install;
  - it ends only the game it started, and that game's children;
  - `install` refuses to replace a different `config.json` without `--replace-config`, which backs
    it up first.
- **The packagers** refuse files that look private (`user.conf`, logs, `.env`, dumps) unless
  `--allow-private` names them, and write an inventory beside each output. Map compile logs are left
  out of the fixes package as junk.
- **`verify_install.py`** fails a depot path that passes through a link, and a depot file it can
  check only by size. **`poc_parity.py`** keeps every path inside the PoC.

### Fixed (R1: whole-repo review)

- `loader.log` appends and `session.json` are never written through a junction or link.
- Module hooks:
  - they stay safe while they are being removed, and after a failed install;
  - slots are recorded before they change;
  - import tables without a name table are hooked by address;
  - every PE offset is bounds-checked.
- `session.json` now has `utc` and `notes`, and each override entry has `module`, which the companion
  was already reading.
- PowerShell started by the Python tools no longer inherits PowerShell 7's `PSModulePath`, which made
  `install-loader.ps1` fail under Windows PowerShell 5.1.
- Three Python test files keep their scratch under `out\tmp` when run directly.

### Added (M7: field install)

- Field test on the user's install ([M7 report](docs/handover/M7-report.md)): RTX on next to the
  user's DXVK `d3d9.dll` and `bin\win64\vulkan-1.dll` (the package's and System32's were loaded), RTX
  off identical to the no-loader baseline, MMD Hot Loader unaffected, and a clean one-command rollback.
- `tools/field_snapshot.py`: a snapshot of what the loader and a test session can change in a real
  install (every non-depot file in the folders packages and sessions write to, by copy: the user's
  DXVK `d3d9.dll`, `vulkan-1.dll`, MMD Hot Loader and Jolt files, configs, logs, databases; folder
  listings; size and time of everything below `garrysmod/data` and `garrysmod/settings`; GMod's
  shared registry key), and a one-command rollback: uninstall, move whatever is new into the
  snapshot's debris folder (links moved, never followed), write changed files back in place (hard
  links hold), make the registry key equal to the export again, then check listings, hashes, registry
  and depot files. Tests in `tools/tests/test_field_snapshot.py` on a synthetic install.

### Added (M6: Workshop route)

- Distribution route ([ADR 0012](docs/decisions/0012-distribution-route.md)): native packages are
  released as downloads and allowlisted as local sources; the Workshop stays a supported source. GMod's
  `gmad.exe` refuses the package format ("Not allowed by whitelist" for `native/manifest.json` and a
  DLL); nothing was published.
- `status.json` lists each deployed package with its source and, for a Workshop item, the update time
  installed at start-up; the Lua companion compares it with `steamworks.FileInfo` (at start and every
  ten minutes) and asks for a restart once when Steam has a newer version. Tested under LuaJIT
  (`tools/tests/test_companion.py`).

### Added (M5: RTX fixes)

- RTX-session extras ([ADR 0010](docs/decisions/0010-rtx-session-extras.md)), applied only when a
  runtime activates: **patch sets** (byte patches written when an engine DLL is mapped, before its code
  runs, only where the pattern occurs exactly once; `-insecure` sessions by default), **module
  overrides** (a game load of `bin\win64\stdshader_dx6.dll` loads the package's copy, through import
  hooks installed at map time) and **session console variables** (a generated
  `cfg/nativeloader_session.cfg` run with `+exec`; the user's archived values recorded first and put
  back once at the next start without RTX). `nl::patch`, `nl::session`, the bootstrap's DLL-load
  watcher (`loader/proxy/modules.cpp`), `session.json`, and the manifest and journal fields.
- Add-ons of RTX-only packages are hidden from sessions without RTX
  ([ADR 0013](docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)): manifest flag
  `requires_remix` (kept in the journal); when no runtime is active, import hooks on
  `filesystem_stdio.dll`'s `FindFirstFile*`/`FindNextFile*` leave those packages' folders out of
  GMod's searches of `garrysmod\addons`, in memory, reported as `session.hidden_addons`. Found by
  the PoC: with RTX off the fixes' Lua still ran. Tested in `nl_session_integration` with a fake
  `filesystem_stdio.dll`.
- Package areas `garrysmod/addons/<addon>/` (kind `lua-addon`, [ADR 0011](docs/decisions/0011-lua-addon-folders.md):
  GMod x64 mounts add-on folders but not a loose `.gma`) and `garrysmod/data/<folder>/` (create-only
  seed data). `remix.launch_args` accepts `-insecure`; `package_runtime.py --insecure` adds it.
- Loader version 0.2.0. Tests: `test_m5.cpp` (129 core cases) and the synthetic
  `nl_session_integration` (a fake engine DLL patched before its DllMain, the override, the session
  cfg and its restore).
- `tools/poc_session.py` talks to the game through `WM_COPYDATA` console text to Source's `Valve001`
  window: a normal `quit` in single-player, a pinned camera and a hidden HUD through client Lua hooks,
  save loading (`--mount-workshop` mounts the save's Workshop map from Lua in a `-noworkshop`
  session); console text waits out a busy window, and Lua sent after a map change is checked and sent
  again; `--reference` (and `--allow-steam-managed`) leaves the install's `console.log` in place.
- `tools/poc_parity.py`: copies the reference install's user content (user.conf, saved Lua settings,
  mounts, Remix mods, a save and its Workshop map; on request its add-on folders, including the ones
  linked to working copies, and named native files such as the MMD Hot Loader's) into the PoC for a
  like-for-like comparison, in layers, and restores the PoC exactly afterwards.

- `tools/package_fixes.py`: builds the RTX fixes package (folder and/or `.gma`) from the fixes repo,
  read only: every add-on folder as kind `lua-addon` (submodule `.git` files, `*.bak` and other junk
  left out; `--exclude-addon`), the Remix mods, the built `gmcl_` modules, `stdshader_dx6.dll` as a
  `module-override`, the seven `patches64` patch sets and the RTX section of `autoexec.cfg` as
  `session_cvars` (every skipped line reported); marks the package `requires_remix`, and deploys the
  ToPBR converter's mod `~gmod_topbr`, which the fixes rewrite at run time, create-only (a reinstall
  was refused otherwise). The Steam files the fixes overwrite and the root
  `rtx.conf`/`dxvk.conf` (runtime-package layers) stay out. Reproducible; tests in
  `tools/tests/test_package_fixes.py`.
- `tools/compare_frames.py`: the user's block-difference measure for two screenshots (mean absolute
  difference of 32x32 block means) with masks and a threshold exit code, plus mean RGB and Rec. 709
  luminance percentiles per image; needs Pillow. Tests in `tools/tests/test_compare_frames.py`.
- Lua companion `companion/nativeloader`, shipped in the fixes package as the add-on
  `garrysmod/addons/nativeloader`: prints the loader's `status.json` and `session.json` to the console
  at client start and on `nativeloader_status`, and marks a report older than the session as stale.

### Added (M4: activation)

- `tools/poc_session.py`: drives PoC sessions without anyone at the keyboard (install, config, launch,
  wait for the map, `PrintWindow` screenshots, module list, a normal quit through a local remote
  console, logs, uninstall and depot verification). Used for M4's remaining real checks and M5.
- Review fixes (Claude): a successful activation is committed before the report is written, so a
  status or log write failure no longer unloads an initialised runtime; a deployment that fails and is
  undone in process activates the committed generation (`startup::after_deployment`, ADR 0009);
  `package_runtime.py` no longer adds `+mat_disable_d3d9ex 1`, which the game archives into
  `config.cfg` and so would carry into RTX-off sessions (`-nod3d9ex` remains).

- Bootstrap startup now deploys and activates the committed generation, validates runtime/layer
  files, applies reversible environment/arguments/Vulkan/DLL-search changes, and preloads the runtime
  by absolute path. Atomic status schema 1 and matching log fields report active and vanilla outcomes;
  uninstall removes generated status. CTest checks KERNEL32-only imports and a packaged fake runtime
  with static/delay dependencies, rollback and startup policy scenarios.
- `tools/poc_activation_check.ps1`: individual approved PoC launches, package A/B preparation,
  module/log/status evidence, vanilla/dxlevel comparisons, visual confirmations and cleanup. The
  user-approved `-Multirun` mode permits the other install to remain running, never another PoC.
- Loader version `0.1.0` identifies M4 activation support and satisfies the runtime packager's
  `requires_loader >=0.1.0` contract (root project version bump approved by the user).
- Startup deployment policy ([ADR 0009](docs/decisions/0009-startup-deployment-last-good.md)) keeps
  the last good generation when an allowlisted source fails, including during staging, distinguishes
  explicit addon disable, and excludes only the current process from the running-game check.
  Explicit CLI apply retains its M3 behavior. Steam registry lookup loads its system library on demand.
- Corrections before integration: command-line swaps validate and update the complete cached
  string descriptors, roll back partial failures and expose explicit/scoped restoration. A separate
  process tests the real kernelbase/PEB round trip. Package config layers now precede existing user
  lists, retaining the user's final editable layer; ordinary environment values remain untouched.
- `nl_core`: `nl::activate::plan` ([ADR 0008](docs/decisions/0008-activation-at-startup.md)), a pure
  function turning the deployed generation, config, environment and command line into the start-up
  steps: the `d3d9.dll` to preload and the folder to add to the DLL search, the config-file layer
  lists (package layers below the user's root `rtx.conf`, relative to the game root), the package
  environment (the user's own values winning) and the launch arguments to add (those the user did
  not pass).
- `nl_core`: `nl::cmdline` — command-line tokenising, and `append_arguments`, which adds the
  runtime's launch arguments in memory by pointing kernelbase's `GetCommandLineW`/`GetCommandLineA`
  caches and the PEB at longer strings, after checking each getter is the expected
  `mov rax,[rip+disp]; ret` shape and points at this process's command line.
- `nlctl activation <game root>`: read-only, prints what start-up would load, set and add.
- Tests: 12 new `nl_tests` cases (106 in all) for `activate::plan` and `nl::cmdline`, the latter
  including the command-line swap against this process's real kernelbase.
- `tools/package_runtime.py`: builds an RTX Remix runtime package (a package folder and/or a `.gma`)
  from the fork's runtime build folder (`_output`), hashing every file as it is copied. Excludes
  `.exp/.lib/.ilk/.bak` and (unless `--with-pdbs`) `.pdb`; `--d3d9-from` overrides `d3d9.dll` from
  another build folder; `--rtx-conf` / `--dxvk-conf` add config layers; `--env`, `--id`, `--version`
  and more set the manifest. The default version derives from `d3d9.dll`, so the output is
  reproducible. Tests in `tools/tests/test_package_runtime.py`.

### Added (M3: deployer)

- `nl_core`: the transactional deployer `nl::deploy` (`apply`, `rollback`, `uninstall`, `recover`,
  `status`; [ADR 0007](docs/decisions/0007-transactional-deployment.md)):
  - each run is one journaled transaction;
  - staging checks every file's size, CRC-32 and SHA-256 before anything in place changes;
  - the intent is written first, renames stay on one volume, and recovery rolls an unfinished
    transaction back;
  - two generations are kept, and rollback holds the previous one;
  - one deployer at a time, refused while the game runs;
  - runs with nothing to do write nothing.
- `nl_core`: SHA-256 through Windows CNG (`bcrypt.dll` loaded from System32 on first use; the
  bootstrap still imports only KERNEL32). Also:
  - `nl::fs`: every change goes through one countable layer, with write-through renames, retries
    while a scanner holds a file, long paths and refused links;
  - the journal `native-loader\state.json` schema 1;
  - one-pass, bounded-memory extraction (`gma::extract`, `Contents::extract`).
- `nlctl apply | status | rollback | uninstall`, with `--dry-run` and `status --verify`.
- `tools/uninstall-loader.ps1`: `nlctl uninstall`, then `install-loader.ps1 -Uninstall`; keeps
  `config.json` unless `-RemoveConfig`.
- `tools/poc_deploy_check.ps1`: the M3 acceptance run on the PoC without starting the game. It
  passed on 2026-10-27: 3,113 entries identical afterwards, 2,877 depot files OK.
- Tests:
  - 32 new `nl_tests` cases (94 in all);
  - fault injection at every file-system change of a first deployment, an upgrade, a rollback and
    an uninstall: interrupted and failed in process, and killed for real (`nl_fault_host`,
    `deploy_faults.py`; 174 kill points);
  - `nlctl_e2e_deploy`;
  - `nlctl_uninstall_loader`: `uninstall-loader.ps1` in synthetic game folders.
- Docs: ADR 0007; the `state.json` schema in `ON_DISK_LAYOUT.md`; the deployment section of
  `ARCHITECTURE.md`; M3 checks in `TESTING.md`; measurements in `RESEARCH.md` section 9.

### Fixed (M3, after an independent review, before the merge)

Each fix comes with a test; ADR 0007 records the resulting rules.

- Recovery could move a whole new payload folder back into staging, which is then deleted, taking a
  file someone had put into that folder with it. Payload files are now moved one by one, each with
  its hash.
- A file the loader had adopted, then put back itself after the user deleted it, stayed "adopted"
  across a rollback. A later clean-up could then delete a file the journal still listed. It now
  belongs to the loader.
- Paths the deployer builds can be longer than the 1,024 bytes a package path may have, which made
  `state.json` unreadable. The journal now accepts up to 4,096 bytes.
- A retired file that could not be deleted (read-only, open elsewhere) made every command fail. It
  now stays listed with a note, and uninstall keeps its journal until it is gone.
- The loader folds case only for ASCII, but NTFS ignores case for every letter, so a renamed
  non-ASCII path broke ownership. Deployed package paths must now be ASCII.
- An undo skipped because a file had changed left its backup copy behind, untracked for good. Such
  copies are now retired, and folders that cannot be removed stay listed.
- A run that changed nothing did not end a rollback's hold, and a package that was broken at check
  time could lift it. The hold is now compared with the plan before re-planning, and ends, recorded
  in the journal, once the plan differs.
- Putting back a deployed file that had gone missing left the previous generation claiming a copy
  that did not exist, so rollback always refused.
- Links were refused only for new targets. Removals, rollback moves, clean-up and undo now refuse
  them too.
- Test-found: the running-game check took a `gmod.exe` that exited during the scan for a running
  one. It now ignores processes that are gone.

### Changed (M3)

- `nl::package::Package` gains `manifest_sha256` (the package version's identity), and `Contents`
  gains `extract()`.
- Payload folders are `native-loader\packages\<id>\<version>_<generation>\`, refining ADR 0004's
  `<id>\<version>\`. The plan had a manifest-hash suffix; the generation number lets a damaged
  folder be replaced without a name clash.
- CTest runs six tests at a time (`CMakePresets.json`). `nl_tests` accepts `--skip=<text>`, and the
  three exhaustive fault cases are CTests of their own.

### Changed (M1 and M2 merged into `main`)

- `main` now holds the inert bootstrap (M1, Codex, reviewed) and the core library and CLI (M2),
  merged without conflicts; Debug and Release CTest pass 6/6 on the result. AGENTS.md, the roadmap,
  the component map, TESTING.md and the handover index describe the merged state; M3 (deployer) is next.

### Added (M1: inert bootstrap)

- Synthetic executable fixtures stay inside the build directory, respecting the user's chosen
  build location instead of copying binaries to the system temporary directory.
- Test discovery checks paths relative to the repository, so a worktree under an ancestor `out`
  directory still runs all Python suites.
- Chromium helpers using `gmod.exe --type=...` remain pure pass-through; only the main game writes
  the startup log. Smoke tests verify that log's PID, preventing helper logs from masking timing
  evidence or bypassing the command-line off switch.
- `loader/proxy`: x64 `winmm.dll` with generated MASM forwarding for all 181 system ordinals
  (180 names and one ordinal-only export), version identity, host gating, all three off switches,
  PE entry-point hook, guarded UTF-8 startup logging and five-log rotation.
- CTest export/forwarding tests, synthetic-host startup/off-switch/failure/rotation tests, and
  installer ownership/hash/Steam-managed protection tests.
- `tools/install-loader.ps1`: PoC-default DLL/PDB installation, SHA-256 receipt, foreign/user-edit
  refusal, opt-in Steam-managed protection and state-preserving uninstall.
- `tools/smoke_test.ps1`: five PoC map loads, strict console comparison, two inert console tools,
  evidence capture and restoration of prior loader state.

### Added (handover)

- `docs/handover/`: the M1 brief for Codex (scope, boundaries, definition of done, report format),
  the Codex set-up notes and paste-ready prompt, and the conventions for briefs and reports.
- AGENTS.md rule 8: parallel milestones run on their own branch and worktree and keep to their paths.

### Changed (repo rules)

- AGENTS.md rule 9 (user instruction): temporary and build files stay inside the repo under the
  git-ignored `out\` (builds, worktrees, test scratch, evidence). `tools/test.ps1` and
  `tools/build.ps1` point `TEMP`/`TMP` at `out\tmp` while they run.

### Added (M2 part 2: config, discovery, planner)

- `nl_core`: `config.json` schema 1 (the allowlist; strict, unknown keys and numeric Workshop ids
  rejected), a KeyValues reader, discovery of allowlisted sources without the Steam API
  (`libraryfolders.vdf`, `appworkshop_4000.acf`, `addonnomount.txt`, `*_legacy.bin`), and the
  planner (ADR 0006: dev folder > local > Workshop, one runtime, no overlapping root files).
- `nlctl plan <game root>`: what the loader would activate and why, read-only.
- CTest `nlctl_e2e_plan`: the whole chain on gmapack-built packages in a fake Steam library.
- `docs/ON_DISK_LAYOUT.md` specifies the implemented `config.json`.

### Added (M2 part 2: manifests and packages)

- `nl_core`: manifest schema 1 (`nl::manifest::parse`, strict, unknown keys rejected; SemVer; launch
  argument and environment allowlists; root areas and policies) and `check_contents`, which refuses
  unlisted native files. `docs/PACKAGE_FORMAT.md` now specifies what the code enforces.
- `nl_core`: packages from a `.gma` or a development folder (links and reparse points refused);
  `gma::read_entry` reads one file, seeking in plain archives and CRC-checking it.
- `nlctl manifest <file.gma|folder>`.

### Added (M2 part 2: LZMA, JSON, path rules)

- `third_party/lzma`: the LZMA SDK decoder (public domain, 7-Zip tag 26.05, unchanged, hashes in
  its README), built as `nl_lzma`.
- `nl_core`: streaming `lzma::Source` for LZMA-wrapped archives (Workshop `*_legacy.bin`),
  including GMod's 8-byte footer (size, then `0xBEEFCACE`); `open_archive` now reads them.
- `nl_core`: strict JSON parser for manifests and `config.json`; shared UTF-8 validation; path rules
  for anything a package names and the root areas packages may write to.
- `nlctl` reports container, stream size, completeness, CRC trailer and LZMA footer.

### Changed (M2 part 2)

- The 4-byte archive CRC trailer is optional: 19 legacy Workshop items have none and GMod mounts
  them. Only streams cut inside the contents or the trailer are truncated.
- Real data: all 753 installed Workshop archives parse; all 81 legacy items verify (4.4 GB, every
  CRC and footer). `tools/gmapack/gmapack.py` rejects GMod's LZMA footer, so it cannot read them.

### Added (M2 part 1: GMA reader and nlctl)

- `nl_core`: GMA reader for GMAD v1-v3 (header and index with gmapack-compatible limits and
  rejections, single-pass `verify` of every CRC and trailing data, container detection,
  share-all file reading), CRC-32, and JSON string quoting that replaces invalid UTF-8.
- `loader/cli`: `nlctl inspect | verify | scan` (read-only), with a CTest that checks it against
  `tools/gmapack/gmapack.py` on synthetic archives, including damaged ones.
- Test harness: `CHECK_THROWS_AS` and `scratch_dir()` (scratch beside the test executable).
- First real-data run: all 672 installed Workshop `.gma` indexes (98,656 entries) parse without
  errors; the 81 older `*_legacy.bin` items are LZMA-wrapped and wait for the decoder.

### Added (M0: repo scaffold)

- Repo initialised on top of `origin/main` (SheepyLord/-Gmod-Workshop-RTX-Remix).
- Agent-facing docs: `AGENTS.md` (rules, commands, documentation duties), `CLAUDE.md` importing it,
  `docs/` with architecture, components, package format draft, on-disk layout, testing, roadmap,
  environment, research notes and decision records 0001-0005.
- C++ build skeleton: CMake presets `win64-debug` / `win64-release` (MSVC x64, Ninja, static CRT,
  `/W4 /WX`), `nl_core` library and `nl_tests` with an in-repo test harness.
- `tools/build.ps1` (configure, build, CTest) and `tools/lib/VsDevEnv.psm1` (MSVC environment,
  works even when `vswhere` cannot see Build Tools).
- `tools/test.ps1` runs every check; `tools/check_repo.py` enforces the documentation conventions
  (a `.md` beside every script, module READMEs, working links, this changelog, the component map).
- `tools/steam/`: depot manifest parser, `verify_install.py` (is an install vanilla?) and
  `make_vanilla_copy.py` (byte-exact vanilla copy from an existing install, no download), with tests.
  `GarrysMod_PoC` was built with the prototype of this tool on 2026-10-27.
- `tools/diag/pe_imports.py`: lists PE imports/exports (hook-point research).
- `tools/gmapack/`: the GMA File Packer, vendored unchanged except for added script docs.

### Decided

- Bootstrap is a `winmm.dll` proxy that runs its set-up at the EXE entry point (ADR 0001).
- Payloads are source-agnostic; Workshop route decided after a private upload test (ADR 0002).
- Only allowlisted packages may deploy native code until signatures exist (ADR 0003).
- The Remix runtime is preloaded from a versioned folder instead of being copied into `bin\win64` (ADR 0004).
- Repo conventions: script docs, changelog, decision records, MIT licence (ADR 0005).
