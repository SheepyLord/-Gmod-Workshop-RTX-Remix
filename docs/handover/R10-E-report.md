# R10-E: imported-character eye whites (report)

Implementation, runtime build and the six-condition PoC measurements are complete on `r10-eyes`.
Acceptance is partial: exact Robin brightness parity is not achieved, and the repository gate awaits
Claude's explicitly deferred runtime import. Design:
[ADR 0088](../decisions/0088-imported-character-eye-whites.md),
[brief](R10-E-eye-whites.md).

## Implementation

The companion identifies separate eye-white surfaces from native/English names, gives only their
public material a distinct texture identity, and registers a transient proxy/original hash alias
before rebinding it. The runtime resolves original PBR replacements first. Otherwise it emits the
eye's own albedo at adaptive intensity 0.625 through C-16. Alpha and normal categories inherit the
original atlas through revisioned per-thread snapshots. Faces sharing the atlas are not rebound.

RTX character settings add the archived checkbox (default on) and live 0–200% brightness slider
(default 100), in English and the six translated catalogs. Brightness scales automatic and C-16
authored eye emission once; it does not overwrite saved Remix options. Older runtimes and unsupported
textures fail closed. Existing edits are preserved by owned binding/cache checks. No hotloader file
or package input is changed.

## Catalogue and C-16 reference

The real Lua matcher finds 522 surfaces in 493/1,225 corpus models (470 share an atlas), all five
PoC characters, and 121 surfaces in 118/143 read-only field manifests. The other 732 corpus models
and 25 field models are unclassified, including unnamed/combined surfaces; these are not proven
false negatives. UV review admits exact `eyeball` and `目白底`, excludes dark rims `目白框`/`目白边`,
pink `eye_back` and iris/cornea `眼角膜`. The named audit cases have no remaining known false positive.

Robin's shipped layer has fixed/adaptive intensities 0.6/15. Its decoded DDS maps yield
0.627605 × linear albedo over 131,891 eroded sclera texels. Nominal `.025/.6*15 = .625` is within
0.417%, the DDS/sRGB quantization difference. Evidence: `out/r10/catalogue.json`,
`ambiguous-materials.json`, `uv-*.png`, `robin-reference.json`.

## Runtime artifact

Built by `runtime/build_runtime.ps1 -NoImport`, base `c6b48ed1` plus patches 0001–0019:

```text
H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r10-eyes\out\runtime-src\_CompRelease_x64\src\d3d9\d3d9.dll
397853184 bytes
SHA-256 3e5c848611c10e7d24d40d5a395abae4c7936ab22c5fa0769c258b413349f315
source commit 381271b1636b153848ba12ff75e51261c50e0e4b
source tree   9f4ba79e25fd49288c5dc7f92f3f72e78f189016
```

Release/Ninja, optimization 3, release DLL CRT, Tracy/shim off, `download_apics=false`, four jobs.
Recorded dependency commits and cached SDK junctions were verified; no fork checkout was changed.
The unit suite passes **30/30**, including new alias, lifetime/invalidation, normalization, material
and snapshot tests. No shader/ABI/schema resource change is needed for patch 0019.

## Delivery gate

`tools/test.ps1 -Config Release` was run before delivery: **26/26 CTests and 545 Python tests pass**
(two existing skips). The separate companion suite passes 20/20. The new Lua suite has 26 scenarios,
including six soft-copy cases; catalogue/comparison tests and the existing eight measurement tests
also pass. The runtime suite is 30/30. Full wrapper result: **exit 1, only packaged-runtime provenance**.
Logs: `out/r10/release-tests-final.log`, `companion-tests.log`, `runtime-unit-final.log`, `runtime-verify.log`.

The branch deliberately leaves `packages/runtime` and `runtime/base.json` unchanged, as requested.
The repository provenance convention consequently rejects the added patch until Claude imports the
reviewed DLL. The gate is not bypassed and no packaged provenance record is fabricated. The brief's
NoImport/unchanged-base rule and a green full wrapper are incompatible with
`tools/check_repo.py:126-151`; following the instruction to report outside-scope blockers and finish
the rest, this branch delivers source and evidence for Claude's single import. No push, merge,
Workshop update, tag, field write or package-input import was performed.

## PoC measurements

The local 1,062-file combined package passed `nlctl` validation and ran runtime
`remix-main+381271b1`. All sessions use `-multirun`. Player placement is the C-16 console line:
outdoors `(831.235,576,-143.08)`, view `(0,180,0)`; room `(1227,-1669,-144)`, view `(50,45,0)`.
Linlong falls face-down in the original protocol, so both characters use a frozen pose and a front
camera 22 units from the head, aimed from the placed player's horizontal direction, FOV 38.
Each setting waits 10 seconds after the time/setting change. One actor stays in the same pose for
all on/off/0/100/200/repeat shots in each run.

These are **linear display luminance of eye whites over cheek**, measured in fixed, visually
inspected boxes. They are not the older C-16 top-down pose's numbers.

| Condition | Linlong off | Linlong 0% | Linlong 100% | Linlong 200% | Robin pack 100%, on |
|---|---:|---:|---:|---:|---:|
| Noon | 0.179 | 0.181 | 0.738 | 1.212 | 0.921 |
| Golden hour | 0.269 | 0.269 | 0.937 | 1.417 | 1.092 |
| Dusk | 0.241 | 0.233 | 0.773 | 1.164 | 0.958 |
| Night | 0.263 | 0.265 | 1.017 | 1.691 | 1.160 |
| Lamp room, day | 0.304 | 0.312 | 0.910 | 1.413 | 1.247 |
| Lamp room, night | 0.321 | 0.319 | 0.930 | 1.422 | 1.274 |

The automatic emission has the measured C-16 coefficient and responds live; zero returns to the
original diffuse/shadowed result. **Strict numerical parity is not met.** Source painting, socket
occlusion and local lighting differ; C-16's frame-average luminance does not compensate for those.
The night result also slightly exceeds the cheek in this pose. I retained the measured C-16 level
instead of introducing a Linlong-specific gain that would change the reference for all other
characters. Further tuning/local-light work needs Claude's review; these measurements are not an
assertion that the brief's complete visual acceptance passed.

Robin's checkbox check, with brightness kept at 100%:

| Condition | Checkbox off | Checkbox on | Off repeat |
|---|---:|---:|---:|
| Noon | 0.925 | 0.921 | 0.940 |
| Golden hour | 1.093 | 1.092 | 1.108 |
| Dusk | 0.962 | 0.958 | 0.954 |
| Night | 1.168 | 1.160 | 1.180 |
| Room, day | 1.267 | 1.247 | 1.247 |
| Room, night | 1.275 | 1.274 | 1.267 |

The on/off differences are within repeated-frame variation (maximum ratio change 1.56%). Pack
brightness also responds: 0% ratios are 0.385/0.489/0.457/0.419/0.490/0.499; 200% gives
1.396/1.598/1.382/1.868/1.821/1.866 in the same order. Authored emission was preserved without
adding automatic emission.

**Scope evidence:** Linlong changes only `mmd/801f3bcf7491bc1e/eye_white_4`; the other **29/30**
public materials remain bound to their original textures. Robin changes only `eye_white_25`; the
other **82/83** remain unchanged. Eye aliases are respectively
`0x72639b3251418d43=0xbd866dd56ce2dd0e` and `0xfde583aebfcc1eec=0x06ddf9d48a2dc2b1`; neither
original atlas is an emitter key. `out/r10/scope-and-performance.json` records before/after names.
Face-control pixels are not bit-identical: Linlong's 100% control varies −5.2%..+1.8% across conditions
(the noon off-repeat already drifts −4.6%; golden on shifts −3.3%). Auto exposure, indirect light and
sampling affect displayed skin. This is a measured limit, not evidence of a face-atlas material override.

Three visible frozen Linlongs, alternating twice, without concurrent builds/tests:

| Setting | Median ms | p95 ms | Frames |
|---|---:|---:|---:|
| Off | 12.249 | 12.930 | 811 |
| On | 12.196 | 12.853 | 817 |
| Off repeat | 12.169 | 12.626 | 820 |
| On repeat | 12.208 | 12.799 | 816 |

Mean of the medians: **12.209 off / 12.202 on**; p95 means **12.778 / 12.826**. No measurable steady
cost in this workload. The three instances share one proxy. Preparation is a real one-time hitch:
Linlong's **22,369,700-byte** atlas reached **153.208 ms**; Robin's **5,592,484 bytes**, **36.004 ms**.
The clone duplicates an atlas allocation, not one allocation per instance/eye part. Limits are
128 MiB per atlas, 256 MiB per Lua session; unsupported layouts/oversized atlases fail closed.

## Reproduction and evidence

`out/r10/measurements.json` includes per-box mean/std, every ratio, feature-off comparisons and frame
timings. `scope-and-performance.json` has material bindings and the three-character timing samples.
Raw captures/logs are under `out/r10/poc/{linlong-final,robin-outdoor,linlong-room-final,robin-room-final,three-linlong,robin-scope}`.
The initial room runs faced the back of the head and are excluded; the probe was corrected and both
room matrices repeated. Source console lines above about 4 KiB truncated large actor binding JSON;
the final probe emits one material per line, and Robin's scope check was repeated.

The prefix is `NL_EYE_SETTINGS={{"off",0,100},{"zero",1,0},{"default",1,100},{"double",1,200},{"off-repeat",0,100}}`,
with `NL_EYE_FROZEN=true`, `NL_EYE_FRONT=true`, the relevant `NL_EYE_ASSET`, and room conditions noon/night.
Run through [eye_white_probe.lua](../../tools/qa/eye_white_probe.lua.md), with the console placement
above. The [catalogue tool](../../tools/qa/eye_white_catalogue.py.md) executes the shipped matcher.

Measurement boxes (`x0,y0,x1,y1`), via [eye_white_patches.py](../../tools/qa/eye_white_patches.py.md):

| Model | Sclera left / right | Skin | Face control |
|---|---|---|---|
| Linlong | 715,332,730,346 / 1193,332,1205,346 | 840,460,880,490 | 1045,470,1085,500 |
| Robin | 741,309,750,323 / 1184,307,1196,319 | 842,435,872,465 | 1045,445,1075,475 |

Runtime receipt/build logs: `out/r10/runtime-built.json`, `runtime-final-build.log`,
`runtime-verify.log`; local package config/build receipts: `workshop-eyes.json`, `package-final-build.log`.
All scratch/evidence stays in this worktree's `out/`; the corpus was read from the main checkout.

## Integration and remaining checks

Claude imports the reviewed DLL once, updating the packaged provenance with the existing build
wrapper, then reruns the full Release gate and rebuilds the combined package. No USD schema/plugin
resource import is required for 0019. The runtime's exact-source verifier passes against the artifact
listed above. The shared PoC lock was held for deployment/sessions and released only after the
Workshop-only restoration check. `out/r10/poc-restored.json` records exact original config SHA-256
`bb27c0d8a80658431ba9394d54e1e458603bf38bcddefdbb84a6aa10c19249a1`, all package sources Workshop,
and restored runtime SHA-256 `c3c6e72692af2a18bc11072191712da5c35a7cb25863b930a0f3fddc45605257`.
The test companion files are removed by journal reconciliation. No Remix user.conf existed or was
created in the checked locations. Only this task's PoC sessions were closed.

Generated soft-copy lifecycle behavior has six unit scenarios. After R10-H released the shared lock,
`linlong-soft-scope` and `robin-soft-scope` repeated off/on/off with the final controller: exactly one
eye part changes in each, including comparison of every existing soft binding. Ratios are
0.174/0.727/0.190 and 0.947/0.939/0.931 respectively, consistent with the longer matrices. These two
fixtures have no naturally soft eye-white copy; that path has six Lua cases, rather than a claimed
GPU acceptance case. `workshop-restored-final` verifies the original configuration/runtime again,
before releasing the lock. Unnamed/combined eyes, unsupported texture
layouts, texture budget limits, exact local brightness parity and the preparation hitch remain
explicit limitations. No silent atlas-wide emission or runtime import is used to hide them.
