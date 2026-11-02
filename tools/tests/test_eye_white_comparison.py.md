# test_eye_white_comparison.py

Tests [eye_white_patches.py](../qa/eye_white_patches.py.md)'s same-camera feature-off comparisons.
Uses generated PNGs under `out/tmp` to verify sRGB-to-linear deltas, an unchanged face control and
dimension mismatch rejection. Run `python -m unittest discover -s tools/tests -p test_eye_white_comparison.py`.
Needs Pillow; writes/removes only generated scratch images. No game or network. Exit 0/1 for pass/fail.
