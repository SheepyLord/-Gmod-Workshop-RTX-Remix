# loader/client/tests

`test_catalog.cpp` exercises the actual `catalog::prepare` policy in synthetic game folders under
the test build's scratch directory. `CMakeLists.txt` builds `nl_client_catalog_tests` with the
existing `loader/tests/test_main.cpp` / `nl_test.h` harness. No game, network, real install, or user
configuration is opened.

Cases cover exact RTX package/source ownership, local/dev-folder/Workshop allowlists, unrelated
files and add-ons, disabled policy, module binding, byte/size/NUL limits, missing files, case
collisions, junctions and immutable snapshots. Committed-journal parsing is checked separately for
unsafe paths, preserving the loader's existing path and protected-folder rules. Junction creation
uses a generated directory and is skipped if the platform refuses it; the target is never followed
during cleanup.

The secure-render policy cases use independent copies of the seven shipped recipe specifications,
not accepted digest values. They require the exact owner/module/name/find/offset/replace fields,
and reject altered ordering, additional patches and every proper subset. The separate config
suite checks the opt-out's boolean type and that it does not alter native allowlists or the general
insecure patch gate.

Build with `cmake --build --preset win64-release --target nl_client_catalog_tests`, then
`ctest --test-dir out/build/win64-release -R ^nl_client_catalog_tests$ --output-on-failure`.
