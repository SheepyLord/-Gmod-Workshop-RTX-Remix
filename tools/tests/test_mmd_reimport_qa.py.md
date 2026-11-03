# test_mmd_reimport_qa.py

Windows-only unittest regression for the R12-A PoC driver. Mocks Win32 input/foreground observation
and process enumeration to cover recent input, foreground field games (including helpers), ten
minutes of idle background activity and no field process. Mocks the entire session to prove it
refuses another task's lock, releases its own after restoration, preserves it after a restoration
failure, and never removes a replaced lock. No game, UI, registry or installed data is accessed.

Run through `tools/test.ps1` or `python -m unittest discover -s tests -p test_mmd_reimport_qa.py`
from `tools`. Generated source/lock fixtures stay in `out/tmp` and are removed afterwards.
Exit 0 on pass, nonzero on failure. Non-Windows hosts skip these two tests.
