# abtest.py

AABB test rig: compare RTX Remix material variants on a spawned Model Hotloader character.

Works through rpai's console bridge, so it needs no display: a scripted camera (a client
CalcView hook), optional part hiding through Model Hotloader's own API, variant model layers
swapped into the live mod, and every view shot N times back to back, so each comparison
carries its own noise floor ("AABB": A, A, B, B).

    python abtest.py bones   --asset 9cdc990f
    python abtest.py capture --asset 9cdc990f --model-key new_mmd_model_9cdc990f ^
        --variant A=layer_a.usda --variant B=layer_b.usda --views views.json --repeats 2 --out run1
    python abtest.py metrics run1 --baseline A --mask skin

With more than one game running, put --game-root <GarrysMod folder> before the command.

views.json maps a view name to a camera. The target is a bone position plus an optional
offset (or an absolute "target"); the camera sits at target + "camera", looking at the target:

    {"forearm": {"bone": "ValveBiped.Bip01_L_Forearm", "camera": [0.01, 0, 18], "fov": 40},
     "neck": {"bone": "ValveBiped.Bip01_Neck1", "target_offset": [-1, 0, 2], "camera": [-0.01, 0, 14],
              "fov": 32, "crop": [1100, 150, 2900, 1100]}}

A small horizontal component in "camera" picks which way is up in a straight-down shot.
"crop" (pixels of the game's screenshot) only affects the comparison sheets; leave it out in the
user's debug sessions, which keep frames whole. With several spawned copies of the model, "ent"
picks one by its order among them (0 = lowest entity index), e.g. a face-up and a face-down copy
for front and back views in one run; --hide then hides those parts on every copy.

capture always puts the original layer back, removes its camera hook and restores exactly the
parts it hid on each copy, even when the game stops answering partway (partial results are kept).

Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)); the full method and every option are in [tool/README.md](../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Drives the running game through rpai's console bridge: a client `CalcView` camera hook, parts hidden only through `mmdhl.SetMaterialVisible`, variant layers copied into the live `ai_pbr` mod one after the other. Everything it changed in the game and the mod is put back at the end. Writes screenshots, `metrics.json` and comparison sheets under `--out`.

## Exit codes

0 on success; 1 when a step fails (the reason is printed); 2 for a bad command line (argparse).
