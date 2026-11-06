# R20-C report: packaged screen, owned blood PBR and realistic impacts

Branch: `r20-blood`, from `r20-int`. Item 48. Implemented by Codex (gpt-6.1-sol).

Status: **done** on `r20-blood`. Implementation, single-player, both corrected multiplayer runs and
the final idle `tools/test.ps1 -Config Release` check passed. No C implementation work remains.

## What is built

- **`toolgun-screen`** ships Dynamic Toolgun Screen 1.3.1, its thirteen languages and original
  picture/modules. A small packaged autorun adapter retains the original initializer verbatim at a
  private path and skips repeat initialization. The tracking tool/full settings live in RTX Remix /
  Rendering beside Toolgun screen; the Utilities shortcut is suppressed. The independent part has
  the same tab placement without the full companion. Multiplayer explicitly receives its marker.
- **`blood-overhaul-rtx`** ships only eighteen generated patterns, their 36 natural/neutral VTFs,
  72 original PBR DDSs, two new analytic particle VTFs, two small sprite-opacity DDSs, twelve colour
  schemes and owned Lua/materials. There are 76 material hash entries (XXH64 and XXH3). No Crunchy
  original/derived texture, flesh/stain map, old blood8-derived droplet, PCF or source reference image
  is redistributed. The two parts' READMEs/licences/credits, original generation prompts and hashed
  selection/exclusion audit are committed. Crunchy's 2022 Blood Overhaul is credited as base/style;
  AI generation of the eighteen patterns is disclosed. Crunchy is optional.
- **One client implementation** handles the existing `BloodImpact` dispatch and biological ragdoll
  hits through `Impact`, `Impact_GMOD` and `RagdollImpact`. It preserves native physics, sounds,
  decals and previous Lua effects, and adds no server damage hook or network message. Direction is
  the event's incoming ray, not the observer's camera. Wider back spatter, narrower/faster forward
  spray, short fine mist and several droplet sizes use ordinary ParticleEmitter/DecalEx paths.
- **Hard bounds:** 80 admitted impact events/s, 640 particle admissions/s, 512 live, 42 per event;
  48 stains/s and 384 per cleanup/explicit-clear epoch. Ragdoll observation allows 160 checks/s and
  64 recent cross-name duplicate entries. Toggles cannot reset budgets. Impact amount is 0–2;
  master off, impact off or amount zero forwards the same native effect data with overrides disabled.
  Mechanical/unknown colours keep native behavior. Existing stains stay until explicit clearing.
- **Settings and guide** cover the twelve schemes, custom RGB, size/variety, droplet recolouring,
  impact on/off and amount in RTX Remix / Blood. New companion titles/help/guide text have all six
  translations; Dynamic Toolgun Screen retains its own thirteen. Original folders remain beside
  distinct deployed folders `nlblood`, `nldynamic_toolgun_screen` and `nl_blood_overhaul_rtx`.

The two sprite opacity materials retain dark unlit particle colour in path tracing with a low .05
scene-adaptive intrinsic fill; physical world stains remain non-emissive. They affect only the two
owned analytic hashes. No global alpha cutoff/category preference or per-add-on Lua registration
was added. The analytic VTFs were not changed after their first import.

## Provenance, size and decisions

The source projects and field were read only. `prepare_blood.py` selected 109 source files and
excluded 270 output files; its audit explains each exclusion. `prepare_blood_particles.py` authors
the two sprite DDSs from the unchanged analytic VTFs, with a native-cache-verified XXH64 hash for
each. Both tools have sidecars and tests; normal builds need neither the old project nor NVTT.

Added LFS content: blood **55,523,212 bytes**, screen **24,316 bytes**, total **55,547,528 bytes
(52.97 MiB)**, 113 compressed binary inputs. Each binary was imported once through `inputs.py`;
the last two DDSs add only 4,768 compressed bytes. No native binary or trust/allowlist change is in C.

Decisions: [0118](../decisions/0118-bundled-toolgun-screen-and-owned-blood-patterns.md),
[0119](../decisions/0119-client-blood-impacts-with-bounded-spatter.md). New callers deliberately stay
outside the old bundled-material exemptions, using normal rendering APIs for D's general support.

## Tests and evidence

All evidence is under this worktree's `out/r20c/`, not committed binaries/screenshots.

- **Final required Release check: passed**, exit 0 (`final-release.log`, `final-checks.json`).
  All **27 CTests** passed; **689 Python tests** ran (29 gmapack, 26 Steam, 634 tools), with two
  existing optional skips. Deep inputs, i18n and conventions each returned 0 too. The final run
  held the shared lock with no game running, avoiding the earlier large-I/O timing interference.

- `test_r20_blood.py`: nine Python tests, including fourteen executed production-Lua scenarios:
  rolling windows/live limits; duplicate and server-preloaded initialization; server marker delivery;
  both menu routes; exact stock forwarding; stock colours/schemes/LOD; saturated collisions and
  epoch limits; world traces with invalid entities; ragdoll inference, colour retention, native/custom
  effect forwarding and cross-name deduplication. Also checks owned-only assets, PNG/CRC round-trip,
  output-path refusal and isolated packager startup.
- Input verification: thirteen parts, zero problems; the deep run is in `inputs-verify.log`.
  Companion check: 494 entries translated in each of six languages, existing bundled catalog intact.
- The complete local `.gma` is built and validated with Release nlctl, compared with the published
  record copied to `out/workshop/published.json`. Content is intentionally different; comparison
  exit 3 is expected. `package-final-verified.log` and the artifact's JSON retain its version/digest.
  Final artifact: `out/dist/gmod-rtx-remix-0.0.0-dev.20261106130400_d02cc199.gma`, **1,450 files,
  1,954,574,816 bytes**, content digest beginning `fd14c078507a110d`.

`acceptance.json` collects the three accepted combat sessions' assertions and measurements;
`final-checks.json` records all four final command exit codes. The completed game runs contain
**82 screenshots**. Their generated-root/config/registry restoration receipts all pass; both later
matching-pin depot checks return 0. No C-owned game is left running and C released every lock it created.

### Final game acceptance

Every session used the shared lock, `-multirun`, `-noworkshop`, local packages, and the normal crash
prompt watchdog. Only each session's own console text was read. Actual pistol, shotgun and AR2 hits
targeted citizens, Combine, zombies, antlions and ragdolls. Colour 1/2/6 overrides complement native
red/antlion/zombie and scheme tests. Multiplayer adds a bot player and a remote NPC shooter.

| Session | Setup and evidence | Result |
|---|---|---|
| `on-final-clean` | C's complete package and its own 0.14 runtime; SP; no Crunchy/standalone copies; 27 frames | All three ragdoll weapon profiles hit; colours 1/2/6 reached the override; panels blood=1, screen=1, old shortcut=0; normal quit, no shipped-controller errors, cloud settings restored. |
| `off-final-legacy3-mp` | The two independent parts; vanilla D3D9; both legacy copies (including Crunchy's base content); 27 frames | Bot/player and remote shooter; panels 1/1/0; native fallback and all schemes; normal quit, no shipped-controller errors, original directories/configs/registry restored. Matching depot verification passed. |
| `on-final-legacy3-mp` | Corrected server-marker delivery; full C package and its own 0.14 runtime; both legacy copies; multiplayer; 28 frames | Bot hit is a player hit; all three ragdoll profiles hit; panels 1/1/0; 2,418 landing callbacks, no trace misses, native fallback retained; normal quit, cloud settings restored, matching depot check 0. |

Stress: six synthetic impacts per rendered frame, normal simulation speed, fixed 60 FPS cap:

| Run | Frames / seconds | Median | p99 | Peak accounting |
|---|---|---|---|---|
| RTX clean | 240 / 4.011 | 16.65 ms | 23.70 ms | 512 live; 333 recent; 192 new stains in four seconds |
| Vanilla + legacy MP | 241 / 4.001 | 16.66 ms | 17.28 ms | 512 live; 313 recent; 192 new stains in four seconds |
| RTX + legacy MP | 241 / 4.011 | 16.66 ms | 21.05 ms | 512 live; 339 recent; 192 new stains in four seconds |

The stress run explicitly clears decals first. Thus cumulative stats can exceed 384 across the two
epochs; each epoch remains bounded. Screenshots `shot-03-npc_citizen_weapon_shotgun.png` in the clean
RTX run show directional droplets/mist; scheme, colour, ragdoll and panel frames accompany them.

Each accepted combat log retains three **test-fixture diagnostic** errors after ragdoll creation:
GetBloodColor can return zero Lua results, so `tostring(target:GetBloodColor())` received no argument.
Spawning/aiming was already complete and all three real weapon profiles subsequently hit; no
production controller failed. The fixture now stores the return in a local first. The collector
explicitly permits only those three known print errors, and rejects any other probe error; the
raw logs are preserved. The session driver's generic Lua-error count did not recognize this add-on
prefix, which is why the explicit post-run audit matters.

### Findings corrected during QA

- Ragdolls dispatch ordinary Impact with unit scale and flesh metadata, not BloodImpact. The
  adapter now uses those existing client messages and leaves physics/sounds/decals intact.
- The PoC's world entity fails IsValid despite a valid HitWorld trace. Accepting HitWorld fixed
  landing stains; the corrected runs recorded thousands of callbacks and zero trace misses.
- Raw analytic sprites were correctly decoded/tinted in vanilla but black under path tracing.
  Separate material/HUD probes (`off-probe`, `integration-pbr-probe`) isolate the issue and verify
  the authored opacity material solution. Temporary C+D fixtures never changed D's branch, imported
  its DLL into C's package inputs, or merged code. Final C acceptance uses C's own packaged runtime.
- MP clients needed AddCSLuaFile for the private screen marker; disk presence alone only worked
  in SP. The explicit delivery regression and corrected MP repeat cover the original extra shortcut.
- Retaining multiple identical 24.7 GB snapshots filled H:. Failed snapshots never launched a
  game. Verified copies were removed; the current driver proves zero depot files under generated
  roots, temporarily renames those originals, restores them and checks every hash. This preserves
  original bytes and avoids repeated large copies. No original user data was deleted.

### Depot/version verification and restoration

The PoC is `261026 / 2156 / x86-64`; the field is now `261104 / 1744 / x86-64`. The first verifier
borrowed the newer field manifests and correctly reported 21 size and 25 hash differences. It did
not establish a C regression: C never touched these version/binary paths. The correct cached PoC
manifests are 4001/**7488132547021413298** and 4002/**7341198560151933050**.

`off-final-legacy3-mp/vanilla.json`: **2,877 files, 7,279,873,012 bytes matched; zero missing, size,
hash, reparse or unverified failures**. Only the pre-existing user-config autoexec difference is
reported separately. Restoration receipts retain byte equality, registry equality and unchanged
user.conf/rtx.conf/dxvk.conf. Field settings were reapplied before every normal quit. The field was
never launched, written or ended. No Steam settings/launch options were changed.

## What remains

- No C implementation item remains. Earlier disk-exhaustion/I/O-timing retries are retained as
  diagnostic history and are not counted as passing verification; the final idle run passed.
- Integration/review on `r20-int`, the combined round's field QA and release/publication remain the
  manager's steps. C has not merged, pushed, tagged, published, started Actions or touched Workshop.
- The stock dispatch has no reliable damage/penetration/exit-wound data. Blood amount is a bounded
  proxy; ragdoll unit scale uses 12 and material/source blood metadata. Forward spray is a visual
  approximation. The map-total stain cap intentionally stops until cleanup/explicit clearing because
  individual engine decals cannot be retired safely without clearing other add-ons' decals.
