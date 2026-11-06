# test_r20_blood.py

The controller matrix executes fifteen Lua scenarios, including explicit server delivery of the
screen marker/panel adapter and independent-part panel relocation.

Also validates R21-A's final imported index and USD: 93 VTFs, 179 DDSs and 186 material
hashes (182 source entries, four analytic sprites), exact DDS dependency closure, lazy loading,
non-emissive world stains, permission date, original MD5 comparisons and byte-identical selected
source inputs. The audit still excludes the unused old blood8-derived droplet. PNG/CRC round-trip and output-path refusal cover the
sprite-opacity generator without invoking NVTT in normal tests.

Runs the R20-C/R21-A Lua harness with installed LuaJIT and checks complete 26-shape selection,
rejection of unexpected texture/DDS paths, deterministic droplet/mist VTF coverage and two-part
configuration without native/trust changes. `python -I -m unittest` from tools is not supported by
unittest path isolation; use the repository test driver or an isolated runner adding tools to sys.path.
Reads repository sources; launches only LuaJIT subprocesses. No game, source-project or network writes.
Exit 0 success, nonzero unittest failures. Lua execution skips when LuaJIT is unavailable.
