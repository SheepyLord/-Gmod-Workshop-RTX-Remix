# test_memory_limits.py

Offline regression for the deprecated memory-limit API. Run in a VS 2022 x64 developer shell:

```powershell
python tests/test_memory_limits.py --out <aggregate-worktree>/out/tmp/memory-limits-test
```

`--source` optionally selects another checkout with the same source layout. The test reads the
actual `ResourceManager::SetMemoryLimits` and Lua binding function bodies into a minimal fake SDK
harness, compiles it with MSVC C++17 `/W4 /WX`, then runs it without loading any game or runtime.
It checks repeated/concurrent calls, a disconnected runtime, zero configuration writes, a single
explanatory message, the retained Lua `true` result and both invalid argument cases. It also
rejects a startup call or unsupported option keys remaining in the resource source.

Inputs: native source files and installed `cl.exe` on PATH. Outputs: one C++ harness, object and
executable in `--out`; no other side effects. Set TEMP/TMP to the aggregate worktree's `out/tmp`.
Exit 0 and a PASS line mean success; any source, compiler or assertion failure exits nonzero.
This does not test game loading or renderer output; those need separate integration acceptance.
