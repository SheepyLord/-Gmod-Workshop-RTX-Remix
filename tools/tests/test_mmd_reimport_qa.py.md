# test_mmd_reimport_qa.py

Windows-only unittest regression for the R12-A PoC driver. Mocks process enumeration, the close
request, the clock and termination to prove a running field game is ended rather than waited for
(the field game is a test session: the user, 2026-11-02): no field game means no action, a game
that closes on WM_CLOSE is not forced, and one still running after 60 s is terminated by its
recorded creation time. Mocks the entire session to prove it
refuses another task's lock, releases its own after restoration, preserves it after a restoration
failure, and never removes a replaced lock. No game, UI, registry or installed data is accessed.

Run through `tools/test.ps1` or `python -m unittest discover -s tests -p test_mmd_reimport_qa.py`
from `tools`. Generated source/lock fixtures stay in `out/tmp` and are removed afterwards.
Exit 0 on pass, nonzero on failure. Non-Windows hosts skip these two tests.
