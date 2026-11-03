# test_vram_census.py

Run from `tools/`: `python -m unittest discover -s tests -p test_vram_census.py`.
Generated log fixtures prove exact multi-GiB integer accounting, device locality, multiple
snapshots and rejection of missing/truncated/mixed/whole-frame allocation rows and missing Source
texture rows. No game, install, network or file is touched. Exit 0 pass, nonzero failure.

The telemetry case verifies exact large counters, null for unavailable fields, a timestamp
filter, an in-progress trailing write and rejection of malformed columns/counters/timestamps.
