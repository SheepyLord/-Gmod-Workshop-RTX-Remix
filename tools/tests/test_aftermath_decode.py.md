# test_aftermath_decode.py

Runs the local GPU-dump decoder against a fake Aftermath API, without a GPU/SDK DLL. Checks that
binary hashes are distinguished from shader-instance hashes, unavailable hashes remain unknown,
the SDK JSON survives even without shader information, and decoders are destroyed after success
and SDK/JSON failures.

Run `python -I tools/tests/test_aftermath_decode.py` from the repository root. No persistent files
or external side effects. Exit 0 on success, 1 for a failed test.
