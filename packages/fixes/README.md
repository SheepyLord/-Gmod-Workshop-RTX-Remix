# RTX fixes package inputs

The GPL-2.0 fixes are imported from the user's fork; [LICENSE](LICENSE) applies. Binary payload
changes go through [`inputs.py import`](../../tools/inputs.py.md). Part notes and corresponding
source under `licenses/` are reserved documentation, excluded from the payload index. The package
builder includes the existing `licenses/oversized-skinning/` tree in the remixbinary add-on as its
native source bundle, including the R6 change below.

## R6 T5 memory-limit compatibility

The current module uses fixes source commit `a2c8dbc5e00e3effe49a8de9609dd1b8af34d552`, a single
commit on the preceding packaged source `b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe`. The module
no longer submits unsupported resource-limit options at map load. The old Lua method is a
documented no-op that logs once when explicitly called, preserves the two numeric arguments and
`true` result, and never writes configuration. See the [source, pins and rebuild notes](licenses/oversized-skinning/memory-limits/Source.md).
