# test_compare_frames.py

Unit tests for [`compare_frames.py`](../compare_frames.py.md). The test images are drawn with Pillow
in a temporary folder under `out\tmp`; no screenshots are read. Skipped when Pillow is not installed.

```powershell
cd tools; python -m unittest tests.test_compare_frames -v    # or tools\test.ps1
```

Covers: `block_diff` on a pair of 70x66 images that differ in one whole block and in the margin the
crop removes; per-image mean RGB and luminance percentiles against values worked out by hand;
identical images and the text output; `--mask` (a block left out, a mask outside the image),
`--threshold` (exit 1 when over, `over_threshold` in JSON) and `--block`; exit 2 for different sizes,
images smaller than a block, unreadable or missing files, everything masked, and bad `--mask` or
`--block` values; on random images, block means, `block_diff`, mean RGB and percentiles against a
slow pure-Python computation (numpy's linear percentile method) for block sizes 32, 16 and 7.

Side effects: only the temporary folder, removed afterwards. Exit code: unittest's (0 when all pass).
