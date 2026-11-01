# test_eye_white_patches.py

Unit tests for [`tools/qa/eye_white_patches.py`](../qa/eye_white_patches.py.md), on images the tests
draw: flat boxes at the default places, measured against an sRGB decode written independently in the
test. They cover the box means and ratio, the standard deviation of a box on an edge, `--shift`,
folder inputs (`shot-*.png` in order, other PNGs ignored), `--range` (`OUTSIDE`, exit 1), `--json`, a
black skin box (no ratio, outside every range) and every exit-2 error: a box outside the image, a
malformed or empty box, no `skin` or no `sclera*` box, a bad `--shift` or `--range`, a missing input and
a folder without shots.

```powershell
cd tools; python -m unittest tests.test_eye_white_patches
```

Skipped without Pillow. Scratch images go in a temporary folder under `out\tmp` (AGENTS.md rule 9),
removed afterwards. No game is started. Exit codes: unittest's (0 pass, 1 failure).
