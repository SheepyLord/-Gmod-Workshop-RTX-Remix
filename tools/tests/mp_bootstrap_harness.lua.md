# mp_bootstrap_harness.lua

Loads the complete production loader/client/bootstrap.lua under LuaJIT with standard-Lua catalog
fixtures and mocked engine APIs. Arguments are production source and scenario. The fixture denies
unrelated local includes/requires, allows one engine-approved fallback, and records every native
catalog read. Cases check scoped file/require/include behavior, owner-relative and cross-owned
resolution, caching, case-insensitive file/directory discovery, unchanged globals, shared/client/
entity initialization order, tracked string/object hook replay, temporary API removal, status/error
completion, and realm/readiness/single-player exits. No game, networking or filesystem writes.
Exit zero with PASS, nonzero on an assertion. Invoked by test_mp_bootstrap.py.

The network scenario mocks registered/unregistered channels and the original engine message
buffer. It exercises the actual scoped adapter across caller/helper environments: absent-channel
Start/Write/BytesWritten/finish suppression, each send/abort reset, a subsequent registered Start,
late channel registration, argument/multiple-return forwarding, receive/read fallbacks and genuine
engine errors. Global net/util tables and net functions remain identical, and an unscoped absent
channel still fails. Missing-channel status records only the owned attempts.

Owned include/require/entity code and a replayed callback assert the verified multiplayer marker
is true in their environment and absent from the global table. Six model_reload scenarios also
read the actual cl_rtx.lua supplied as the third argument, extract only its hardware-skinning model
reload section and execute it with queued timer/hook/convar mocks. Normal nil/false markers retain
the initial zero-delay reload and final one-second reload, including a restored-convar retry. The
verified late marker prevents both reloads and further retries with matching, mismatched or missing
convars. No production implementation is copied into the fixture.
