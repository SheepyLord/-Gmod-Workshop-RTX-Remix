# test_upscaling_readback.py

The R20-Q follow-up extends the SDK-free publisher test with 5,000 unrelated dirty notifications
and intervening reads, plus immediate failure invalidation. The separate runtime target
`test_upscaling_options` runs 20,100 writes through actual `RtxOption::readOption`, including writes
after resolution/before present, dependent selectors/preset callbacks, and a failed resolver. It
runs in the runtime's dedicated unit build and needs the pinned SDKs; this aggregate runner stays
SDK-free.

R20-E regressions for the live upscaling readback (ADR 0123). Run from the repository root:

```powershell
python -I tools/tests/test_upscaling_readback.py
```

Extracts the complete production game-state store and its unit test from runtime patch 0040, then
builds/runs that test and the fixes' GPL `upscaling_state_test.cpp` with MSVC x64, C++17, optimization,
warnings as errors and assertions enabled. The publisher test checks startup and pending readiness,
failed callback convergence, reserved writes, all effective enums, device replacement/shutdown and
100,000 concurrent publications. The readback test checks every enum/capability combination and
missing, malformed, future-version, oversized, failed and unterminated API results. No game, GPU,
runtime checkout or network is needed. The source-copy check runs on every platform; compilation
is skipped when Windows/MSVC Build Tools are unavailable.

Inputs: the committed runtime patch and GPL source files. Writes: temporary compiler inputs/outputs
only under `out/tmp`, removed afterward. No settings, game or package mutation. Exit 0 on success,
1 on failure. Included in `tools/test.ps1`.
