# test_pending_runtime_patches.py

Checks `check_repo.check_runtime_record` with generated runtime records. Run
`python -I tools/tests/test_pending_runtime_patches.py` from the repository root, or the Release gate.
An exact declared new suffix patch passes; changed/missing pending files, an exemption for an existing
packaged input, an undeclared addition, changed source settings, malformed/empty records and stale
pending records after import fail. Clearing the pending record after import restores the normal check.

Inputs are generated text and SHA-256 records. Scratch stays under `out/tmp` and is removed afterward.
No real package, runtime, git, game, network or user setting is changed. Exit 0 on success, 1 on failure.
