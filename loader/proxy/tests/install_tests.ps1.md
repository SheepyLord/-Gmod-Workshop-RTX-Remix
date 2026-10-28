# install_tests.ps1

CTest installer regression tests. Inputs: `-Repo` absolute worktree root and `-Config Debug|Release`.
Uses the real built DLL/PDB but only synthetic game roots below `out/installer-tests/<UUID>`;
the dummy `gmod.exe` files are never executed. Checks WhatIf, install/reinstall, version identity,
SHA-256 edit protection, foreign DLL/PDB refusal, default state retention, explicit state removal
and Steam-managed manifest refusal/bypass. Prints the check count; throws/nonzero on failure.
Deletes only its verified absolute UUID scratch directory in `finally`. No actual game or Steam
settings are changed. No network, extra modules or third-party dependencies.
