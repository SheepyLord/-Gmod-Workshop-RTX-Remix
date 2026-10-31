# model_layers_harness.lua

GPU-free client fixture for the shipped outline module. Called by
[test_model_layers.py](test_model_layers.py.md) with the production Lua path and scenario.
Mocks only engine/native boundaries; verifies late hashes, ordinary-image protection, model/skin
caching, submaterials, private proxies, cached bindings, toggles, missing APIs and retries. No files,
network or user settings are changed. Exit zero on success; assertion failures are nonzero.
