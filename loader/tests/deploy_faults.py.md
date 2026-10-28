# deploy_faults.py

CTest `nl_deploy_faults` (registered in [`CMakeLists.txt`](CMakeLists.txt)). It kills the deployer
for real at every point of four deployments, and checks that the next run always leaves a
consistent install: exactly as before the deployment, or exactly as after it.

For each scenario it builds the state before the command, then runs the command once without faults
to get the state after it. Then, for every N from 1 until the command finishes, it does this on a
fresh copy of the "before" state:

1. Runs `nl_fault_host <command> <copy> --kill-at N`. The host ends itself with `TerminateProcess`
   (exit 99) just before its Nth file-system change.
2. Runs `nl_fault_host recover <copy>`, which undoes the interrupted transaction and finishes the
   clean-up.
3. Compares every file (SHA-256) and folder of the copy with the two states; the journal and the
   lock are left out. It also requires that nothing is pending, nothing waits to be deleted, and no
   staging folder is left.

Scenarios, on packages built with [`gmapack.py`](../../tools/gmapack/gmapack.py.md) (a runtime with
a payload folder, and a root-files package):

- a first deployment;
- an upgrade: a new runtime folder, and root files replaced, added and removed;
- a rollback of that upgrade;
- an uninstall.

On 2026-10-27 these made 54, 59, 26 and 35 changes. The test fails if a scenario makes fewer than 5,
since it would then no longer test what it should.

```powershell
python -I -B loader\tests\deploy_faults.py --host out\build\win64-debug\loader\tests\nl_fault_host.exe `
  --gmapack tools\gmapack\gmapack.py --scratch out\tmp\deploy_faults
```

## Inputs, outputs, exit

- `--host`: the `nl_fault_host.exe` build. `--gmapack`: `tools/gmapack/gmapack.py`. `--scratch`: a
  folder it may delete and recreate (CTest passes one in the build tree).
- Writes only below `--scratch`, and removes it on success.
- Exit 0 when every interruption ends in the old or the new state; otherwise it exits with a message
  naming the scenario and the change number.
- Takes about 20 s with a Release host and 35 s with a Debug one under parallel CTest. The
  in-process tests in `test_deploy.cpp` add interrupted recoveries and a failure at every change.
