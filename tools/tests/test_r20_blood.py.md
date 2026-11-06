# test_r20_blood.py

The controller matrix executes fourteen Lua scenarios, including explicit server delivery of the
screen marker/panel adapter and independent-part panel relocation.

Also validates the final imported index and USD: exactly the owned VTF/DDS names and 76 material
hashes (72 patterns, four analytic sprites), lazy loading, non-emissive world stains, and the audit
excluding the old blood8-derived droplet. PNG/CRC round-trip and output-path refusal cover the
sprite-opacity generator without invoking NVTT in normal tests.

Runs the R20-C Lua harness with installed LuaJIT and checks the provenance filter's source allowlist,
rejection of originals/derived DDS paths, deterministic new droplet/mist VTF coverage and two-part
configuration without native/trust changes. `python -I -m unittest` from tools is not supported by
unittest path isolation; use the repository test driver or an isolated runner adding tools to sys.path.
Reads repository sources; launches only LuaJIT subprocesses. No game, source-project or network writes.
Exit 0 success, nonzero unittest failures. Lua execution skips when LuaJIT is unavailable.
