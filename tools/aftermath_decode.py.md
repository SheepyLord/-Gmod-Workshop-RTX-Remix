# aftermath_decode.py

Decodes a local NVIDIA Aftermath `.nv-gpudmp` with the installed SDK's decoder API. Keeps its full
JSON (device/engine reset, page faults, active shaders and markers) and adds active shader binary
hashes, optionally matched to compiled Remix SPIR-V files. Does not upload anything or require a GPU.

```powershell
python -I tools/aftermath_decode.py out/r21c/crash.nv-gpudmp --dll '<SDK>/lib/x64/GFSDK_Aftermath_Lib.x64.dll' --out out/r21c/decoded.json --spirv-root '<matching-runtime>/_CompRelease_x64'
```

Requires 64-bit Windows Python and a trusted local Aftermath DLL. ABI defaults to Aftermath 2026.3,
API 2.27 (`0x21b`); `--api-version` selects another compatible ABI. No SDK headers or DLLs are
redistributed. Decoder flags are `ALL_INFO`; unavailable shader/source debug data stays unavailable.
`--spirv-root` is optional. Missing active-shader data is recorded as a warning while keeping the
rest of the decoded dump. A match requires the SDK's binary hash to match exactly; an active shader
or matching hash alone does not establish the cause of a GPU timeout. Unknown/internal shaders keep
their hashes and numeric shader types. The original SDK JSON remains under `sdk`.

Reads the dump (nonempty, at most 1 GiB), the DLL and optional `.spv` tree. Writes only `--out` and
a PID-specific temporary sibling, atomically replacing an earlier output on success. SDK errors,
invalid JSON and unreasonable sizes fail without replacing a previous output. Exit 0 on success,
1 on decoding/input failure, 2 on argument errors. Tests: [tests/test_aftermath_decode.py](tests/test_aftermath_decode.py.md).
