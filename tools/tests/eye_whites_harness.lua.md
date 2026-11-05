# eye_whites_harness.lua

R12-D extends the real-controller fixture with a spawned entity list, strict full asset ownership,
in-memory DATA/JSON round trips and a minimal Derma tree. Tests mark/unmark live bindings, saved true
and false outranking names, exclusions overridden manually, source-independent full asset isolation,
fresh controller/map/restart, remove/re-import, reset, unreadable/changed files, the saved-choice cap,
and the actual chooser's thumbnail, checkbox, reset and 24-row pagination. Metadata listing and
unspawned/preview/foreign assets must do no texture work. The JSON fixture round-trips deep copies;
GMod owns the actual JSON parser and file implementation, exercised separately on the PoC.
The missing-file size-0 regression models the measured GMod API result and must permit a first save.

Soft-copy cases cover immediate/late copies, a copy inheriting the proxy, foreign asset/slot rejection,
user edits and pruning/restoration. Public and soft eye draws share one alias, while the face stays original.

`cache_cap` (R19, companion F-03) names the cached proxies as the companion does (64 lowercase hex
digits) and adds older, larger files under other names (`my_edit`, 64 uppercase hex digits, 63 and 65
digits): the oldest digest-named proxy goes, and every other file stays. It fails on the controller
before R19, which counted and deleted every `.vtf` in the folder.

LuaJIT fixture executing the actual companion matcher, VTF validator/identity encoder and controller.
Invoked by [test_eye_whites.py](test_eye_whites.py.md), or `luajit eye_whites_harness.lua <repo> <scenario>`.
Exercises semantic positives/exclusions and English fallback, byte/alpha/mip preservation, shared-atlas
isolation, initialization/late resources and APIs, old-runtime refusal, option retry, live clamped
brightness, enable/disable/restoration, asset pruning, edited cache/foreign bindings, shutdown and a
4,096-material work-budget case. Input: source files and scenario. Output: PASS or assertion failure.
No disk writes or game required. Exit 0 on success, nonzero on failure.
