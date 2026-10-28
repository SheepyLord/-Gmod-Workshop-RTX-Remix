# check_imports.py

Reads the built AMD64 PE import and delay-import directories using Python's standard library.
CTest passes the absolute path of winmm.dll as its sole positional argument. Prints the exact
KERNEL32-only confirmation and exits 0; any other DLL, malformed PE or file error exits nonzero.
Read-only, no network, third-party packages, game launches or filesystem changes. This catches a
new core-library dependency becoming a static bootstrap import during activation integration.
