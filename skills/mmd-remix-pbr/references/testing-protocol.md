# Testing in game: compare, AABB, and the rig

The user wants measured verification, and decides any change to a standard themselves. Three levels:

| Situation | Tool | Evidence |
| --- | --- | --- |
| A new character was published; show the effect | `rpai compare "<pmx>"` | before/after of the user's current camera, plus floor-corner noise |
| Tuning one model's preset (a pin, a region, a class value) | `scripts/abtest.py` with 2–3 variant layers | AABB sheets and metrics |
| Changing a default or standard (anything in `classify.py`, skin, face) | full-body AABB with `scripts/abtest.py` | sheets and a metrics table, presented for the user's decision |

## Getting the game ready

- The game must be running with the character spawned in Model Hotloader. Check with
  `abtest.py bones --asset <id8>`, which also lists the bone positions for framing.
- There may be no desktop display: everything goes through the console bridge. Do not restart the
  game yourself. If it stops answering (the window rejects console messages, or the process shows
  "Not Responding"), wait once (about 90 s), then continue with what you have and tell the user.
- The user may change the scene while you work: hide parts, set morphs, respawn the model (new
  entity index, new position), or quit the game. Re-read bones before every capture, and never
  assume an entity index.
- **The player must be near the target.** If the user has walked away (5,400 units on
  2026-10-27), the ragdoll is not drawn, its client bones go stale and the scripted camera films
  bare floor; a PVS hook alone did not fix it. With the user's consent, teleport the player beside
  the target for the capture and put them back:
  `H:\BACKUP_20260815\Modding\ipg\zzz_33_c\pbr\tools\capture_teleport.py`.
  - It saves the player's position and view, then freezes the player during the capture.
  - Before capturing, it checks that the target is drawn, its bones are where expected, and the
    capture camera really takes the view.
  - Afterwards it returns and unfreezes the player.
- **Several games may run** (another session's `GarrysMod_PoC` test beside the user's game, with
  `-multirun`). The bridge takes the first window it finds, so pass the game's folder: `rpai ...
  --game-root <GarrysMod>` and `abtest.py --game-root <GarrysMod> capture ...`. Screenshots are
  found as new files in `garrysmod/screenshots`, so a game started without `-condebug` (no
  `console.log`) works too.
- The user may add, hide or remove copies mid-session (2026-10-30: a second Evernight with the
  outfit hidden, a second March 7th, then removed). Frame from bones with `"ent"`, re-read copies
  before each capture, and judge from same-run patches with an A2 bracket: frame-wide means picked
  up a moved ragdoll as 16.6/255 of "change".
- Other sessions run `abtest.py` captures in the same game, with the same camera hook name.
  Check for running `abtest.py` processes before you start, and never overlap captures.
- Keep mod reloads few: one per variant, not one per view. The mod preloads every texture, including
  Firefly's 124 MB stockings sheet, and each reload stalls the game briefly. Twice on 2026-10-25 a
  capture ended right after a reload: once "Not Responding", once an orderly quit. When the console
  stops answering, `abtest.py` stops, keeps the partial shots and puts the live layer back. Report
  that rather than retrying.

## Camera

`abtest.py` installs a client `CalcView` hook (`rpai_abtest_cam`) per view and removes it at the
end. Frame from bones: the target is a bone plus an offset, and the camera sits at target plus an
offset. For a straight-down shot, a 0.01 horizontal component picks which way is up in the image.
A camera cut needs about 4 s for the denoiser to settle. Repeats on the same view need about 1.5 s
between shots.

## Several copies, front and back

The user may spawn more than one copy of a model (Guinaifen: one face-up, one face-down). They share
every Remix material, so one capture covers both: give each view an `"ent"` (copy order by entity
index, 0 first) and frame front features on the face-up copy and the back on the face-down one.
`--hide` hides the listed parts on every copy for the capture and restores exactly what was visible
on each. Skin tests on a dressed scene hide the clothes this way (Guinaifen: 33 parts per copy); the
morphs stay untouched. Skin tests themselves run only when the user asked for skin work; afterwards
publish the state the user chose, and the standard (body skin left to Remix) when they keep none.

## Hiding parts (to see skin or an inner layer)

Use only Model Hotloader's own API: `mmdhl.SetMaterialVisible(ent, materialIndex, bool)`. The index is
0-based in PMX material order (`classes.json` keys). Model Hotloader draws natively and stores parts
as bodygroups; parts from index 32 up live in networked ints (`MMDHLPart<n>`). `SetSubMaterial`
does nothing here.

- Record visibility before you change it, and restore only what you changed. `abtest.py --hide`
  does this.
- If a part stays invisible while every flag says visible, check the material morphs before
  debugging. Guinevere's `[Fullbody]` morph (#164) hides the whole outfit:
  `mmdhl.Decode(mmdhl.native.GetState(mmdhl.GetInstance(ent))).morphs` holds the weights, and
  `mmdhl.GetRig(ent).morphs` the names. Do not get stuck: the user explicitly asked not to loop on
  side-debugging.

## Framing R18 models

These models are adult (R18). They keep a base body under their clothes for layered rendering, and
the user may unclothe them or set morphs for a test. Aim each view at the surface under test, for
example:

- the neck and collarbones (target about 1 unit toward the head from the clavicles, narrow fov of
  about 32);
- the abdomen and waist;
- the arms, from above and from the side at a low angle (shows the terminator);
- the knees and shins; for stockings, the inner and outer side of each leg, where the front and
  back UV halves meet.

**Keep every frame whole (user decision, 2026-10-25).** In these local rendering-debug and AABB
sessions, do not crop ("chop") screenshots, and do not delete or reframe a shot because the base
body is in it. Do not change morphs or part visibility to hide it either: uncropped frames and the
user's untouched morph state are what make the AABB shots comparable. Leave `crop` out of
`views.json`; a zoomed inset for inspection may sit next to the full frame, never replace it.

## AABB capture

1. Build one complete model layer per variant.
   - For a class or preset change: `rpai generate --settings variant.json --only <textures>`, then
     `rpai publish --settings variant.json --no-prune`. Copy
     `mods/ai_pbr/models/<key>.usda` to `variant_X.usda`, and repeat for each variant.
     `--no-prune` keeps every variant's DDS, because names are content digests.
   - For "original Remix", delete that texture's `over "mat_<HASH>"` block from a copy of the layer.
   - Per-model presets merge after `--settings`, so a value set in `presets/models/<key>.json`
     wins over your variant file. Put variant values somewhere the model preset does not override.
2. Run the capture:
   `abtest.py capture --asset <id8> --model-key <key> --variant A=... --variant B=... --views views.json --repeats 2 --out <dir>`.
   It swaps each layer in, waits for Remix's "swapped in" log line, shoots every view twice back to
   back, then puts the original layer back.
3. Run `abtest.py metrics <dir> --baseline A --mask skin` (or `--mask all` for non-skin materials).
   It writes `metrics.md`, `metrics.json` and `sheet_<view>.jpg`:
   - **noise:** the mean |shot1 − shot2| on the mask, the floor every effect is compared with;
   - **change:** the mean |variant − baseline| on the mask;
   - **detail kept:** the spread of band-passed redness R − (G+B)/2 (σ 2–40 px), and the same for
     luminance, relative to the baseline. This is what showed de-light fading painted body detail.
4. Finally publish the chosen state normally (`rpai publish`, without `--no-prune`). That prunes the
   variant DDS files.

Lighting drifts over minutes: the floor once brightened 25% between two runs. Only compare shots
taken in one capture run, and quote the noise floor next to every effect. Auto-exposure also
re-adapts after every swap; the defaults (`--settle 20 --camera-settle 6`) keep the repeat noise at
about 1-2/255, where 8 s let the first shot of a variant come out 8/255 darker.

**Bracket the baseline** when an effect is small or a surface must not change (body skin):
`--variant A=... --variant B=... --variant A2=<copy of A>`, then compare B with the mean of A and
A2, and quote |A2 − A| as the drift. Repeat noise (back to back) does not see drift: on Robin it
was 0.05-0.3 on patches while A2 − A reached ±5 over 4 minutes, and an unbracketed A-then-B run
put 2.4-6.1/255 of change on the untouched floor. Bracketed, her shin skin moved −1.6 against a
drift of −2.2.

**Thin lines (seams, creases).** Frame-wide means hide a 3-6 px line. Build the line mask from two
variants that differ only by the fix (Guinaifen: A before vs B fixed, same roughness), then
measure each variant's band-passed luminance (1-6 px) on the mask minus a ring 4-12 px around it,
inside its own frame, so exposure cancels. Guinaifen's crease measured 1.7-5.9 before and -0.6 to
0.35 after, against -0.2 to 0.06 for the original Remix render.

## Presenting a decision

Send the sheets (non-explicit) with `SendUserFile`, then ask with `AskUserQuestion`. Each option
carries its measured trade-off, for example "B keeps 95–101% of the detail and is visually
indistinguishable from A". Recommend the conservative option when nothing beats the original by
more than the noise. The user's standing rule: if no variant is accepted, revert to the original
RTX Remix look. Record the decision and its evidence in `references/standards.md`, the tool README
and `classify.py` comments.

## Single-view sweeps and screenshots

For a quick parameter sweep (emissive intensity, roughness), change only the layer: for example
`rpai publish --emissive-intensity X`, or a layer patch replacing a texture input with a constant.
That needs no regeneration. Screenshots come from Source's `jpeg` console command, which captures
the Remix frame at the game's resolution (4K here) into `garrysmod/screenshots/`. Fixed screen
patches with hair and floor reference patches worked well for face and eye checks.
