# R15 report: painted shadows, solid hair, and the release candidate

The user's items (2026-11-04), in the [plan](R15-plan.md): 43, hide 目影 in imported models
automatically, more robustly; 44, better handling of materials with alpha, with Laevatain's hair as the
example ("I removed Alphatest to make it look correct ... You are allowed to switch away from Alphatest
if needed"); then the most recent loader release, as the release candidate.

Claude did the work in the main session on `r15`; Codex only translated (R14's rule for this session).
Decision: [ADR 0104](../decisions/0104-painted-shadows-and-solid-hair.md).

## What changed

**Painted shadows** (item 43). [`painted_shadows.lua`](../../companion/nativeloader/lua/nativeloader/painted_shadows.lua.md)
finds them by name and by their properties; [`nativeloader_imported_parts.lua`](../../companion/nativeloader/lua/autorun/client/nativeloader_imported_parts.lua.md)
leaves them out of the draw in RTX sessions through a new, `pcall`-guarded hook in the Model Hotloader's
`mmdhl.SyncMaterialState` (`mmdhl.RenderHiddenParts`). Bodygroups, saves, dupes and files do not change.
Rendering > Model outlines: **Hide painted shadows**, on by default.

**Solid hair** (item 44). [`solid_hair.lua`](../../companion/nativeloader/lua/nativeloader/solid_hair.lua.md)
samples a hair part's texture alpha (a few rows per frame). When the texture is mostly opaque but the
0.5 alpha test cuts holes into it, the part's material loses `$alphatest` and its soft copy loses
`$translucent`, in memory: the user's own fix, put back when the setting is off. Rendering > Model
outlines: **Solid hair**, on by default.

**Also.** A client joining a server now receives the eye-white rule modules (only `include`d before).
The guide's Characters page has a section on both settings, and Troubleshooting a question that points to
them. The render guard's table lists the three new companion files (354 paths; its docs said 345, but
it held 351 already).

## How the rules were chosen

**Painted shadows.** The field library (159 models, 6,684 parts, read only) shows how varied they are:
untextured black at alpha 0.2-0.5 (Endfield, Wuthering Waves), a plain 黑.jpg or 灰.jpg (Star Rail), a
region of the face atlas (まぶた影, 髪影), an untextured grey (ホタル), Tda's `hairshadow`, and Laevatain's
`Moyin` and `Hair+`. Run over all of them, the rules hide 92 parts, all of them shadows; only `Hair+` is
found without a name. Kept: coloured make-up (Evanescia's lavender `Mat_EyeShadow_01`), two 眼影 painted
from a coloured texture, parts hidden as authored, glasses.

**Hair.** In the hair textures with partial alpha, 85-100 % of the partial texels lie in regions over 16
texels wide, and almost none touch a clear texel: masks and fades inside the strands, not anti-aliased
edges. The runtime replaces the alpha-test reference of these draws with 0.5
([ADR 0081](../decisions/0081-mmd-alpha-texture-category.md)), so a lower reference cannot help; only an
opaque draw is solid. The rule: 10 % or fewer clear texels (no strands cut out of the texture), 20 % or
fewer partial ones (not see-through on purpose), at least 0.2 % below half (the test cuts holes). In the
field library that makes the Endfield hair of Laevatain, JEPT and Yvonne solid, and a few others with
fades below half (Tda式初音ミクV4X's twintail ends, 芙提雅, 薇薇安); cut-out hair (刻晴), binary alpha and
see-through hair (灵可's bangs) keep the alpha test.

## Proven in the PoC

The branch's own package (0.0.0-dev.20261104093820+2ca407eb, through `allow.local`), gm_construct, RTX,
six characters copied from R13's read-only field cache and removed afterwards; the PoC's loader config
was put back byte for byte each time and every session quit with the field's settings. Evidence:
`out/r15/poc1`, `poc2` and `poc3` in the `r15` worktree.

| Character | Painted shadows hidden (R15 on) | Hair drawn solid | Measured |
|---|---|---|---|
| Laevatain | `Moyin` (name), `Hair+` (untextured black, alpha 0.5) | `Hair`: flags 536881424 -> 536881168, soft copy 2107408 -> 10256 | clear 3.6 %, cut 1.5 %, partial 5.0 %, 2048², 85-123 ms over the frames |
| JEPT | `EyeShadow`, `HairShadow` | `发2` | clear 1.9 %, cut 4.5 %, partial 8.2 %, 1024² |
| Yvonne | 目影, 发影 | (no alpha channel) | |
| Robin | 目影 (painted from 黑.jpg) | (no alpha channel) | |
| Linlong | 目影, 髮影 | (no alpha channel) | |
| New MMD Model (Alf) | `MI_AlfDefault_U_LashShadow01_A` | `Hair01_A01`, `Hair01_A02` | clear 0.1 %, cut 3.4 %, partial 5.6 %, 2048² |

With both settings off nothing was hidden and no flag changed; turned on, the parts were left out within
the hotloader's 8-frame sync and the hair changed within its 2-second check.

**What it looks like.** In `poc3`, Laevatain is a frozen ragdoll and each view is shot twice in a row,
both settings off and then on. Off, her fringe shows dark see-through patches over the eyes, the shapes
of the alpha test's holes and the blended `Moyin` overlay; on, the fringe is solid and the eyes are clean
(`zoom_eyes.png`, `zoom_fringe.png`). From the side and the back the hair looks the same, slightly more
solid. In `poc2` (same camera, the characters turn their heads between the two shots) every character
with a painted shadow loses a dark band across the eyes: JEPT, Yvonne, Robin, Linlong and the Alf model.
JEPT's solid hair shows no dark spots where its texture has clear texels.

**Tests.** `tools\test.ps1 -Config Release` passed on `r15`: conventions, 556 Python tests (11 new LuaJIT
scenarios among them), 26/26 CTest.

## Publication and the field check

`r15` was merged into `main` as `1d1ee9d` and pushed (the first push got GitHub's Internal Server Error;
the second went through). The merge's hook published Workshop item 3829070317 as
0.0.0-dev.20261104095452+f59fb84b; the two push hooks found the inputs unchanged.

Before the field starts no other session's lab or game was running, and
`tools\steam\verify_install.py` found the field install intact (only the user's `autoexec.cfg` differs).
Evidence: `out\r15\field\` in the main checkout.

| Start | Package | Result |
|---|---|---|
| 01-download | f59fb84b downloaded | Map loaded; the harness's 5 s screenshot limit ran out on the 3840x2160 window, so it ended the game instead of quitting it (no settings written) |
| 02-r15 | f59fb84b deployed, active | Passed, through a scratch wrapper that gives `poc_session.py` 30 s per screenshot: normal quit, no Lua error, the field's own Laevatain as a frozen ragdoll, three views shot with both settings off, then on |

In the field, `Moyin` and `Hair+` were hidden and the hair solid (clear 3.6 %, cut 1.5 %, partial 5.0 %,
123 ms over the frames). The scene is dark under the user's sky settings; brightened, the pair shows the
same as the PoC: dark shapes over the eyes with both off, a solid fringe and clean eyes with both on.

The spawn wrote to the user's library: its use history (`recent.json`), the approved rigs and a new rig
for Laevatain as a ragdoll. All of it was put back as it was (`out\r15\field\backup`), and the new rig's
files removed. The session quit with the field's own settings.

## The release candidate

The user asked for the most recent loader release after R15, as the release candidate. Loader 0.13.0
(R13-C's memory profiles, after 0.12.1, the last release) was never released. It is tagged
`v0.13.0-rc.1` on `main`; CI's release job builds the bundle (`winmm.dll`, the default config, the
README, the symbols) and creates the GitHub release "Native loader v0.13.0-rc.1", which becomes the
latest. The RTX package itself reaches players through the Workshop item, already published above.

The tag's CI run built and tested the bundle (`gmod-native-loader-0.13.0+6a68fc68.zip` and its
`-symbols` zip) and uploaded both, but GitHub's API answered HTTP 500 to the job's last call, which
publishes the release, so it stayed a draft (GitHub had answered the first push of `main` with the same
error). The draft was published with `gh release edit --draft=false --latest` (one more 502, then it
went through), and the notes gained a release-candidate summary: the loader's memory profiles, and what
the Workshop item brings since v0.12.1.
<https://github.com/SheepyLord/-Gmod-Workshop-RTX-Remix/releases/tag/v0.13.0-rc.1>

## Open items

- **Hair that turns solid besides Endfield's.** A few models whose hair has a fade below half also become
  solid (Tda式初音ミクV4X's twintail ends, 芙提雅, 薇薇安 in the field library); they were not seen in a game.
  If one looks worse, the Solid hair checkbox turns the rule off for every character; a per-part choice,
  like the eye-white chooser's, would be the next step.
- **Parts the rules leave.** Star Rail's `眼睛1` (alpha 0.3, painted from the face texture) and two 眼影
  painted from a coloured texture are kept; whether they are shadows is not known from their data. Their
  bodygroups can hide them.
- **The guide's Model outlines picture** ends at Choose eye-white materials; the two new checkboxes are
  below it, named in the text, not pictured.
- **`poc_session.py`'s 5 s screenshot limit** is short for a 3840x2160 field window; the field check used
  a scratch wrapper with 30 s.
