# test_r20_blood.py

Also validates the final imported index and USD: exactly the owned VTF/DDS names and 72 material
hashes, lazy texture loading, and an audit explicitly excluding the old blood8-derived droplet.

Runs the R20-C Lua harness with installed LuaJIT and checks the provenance filter's source allowlist,
rejection of originals/derived DDS paths, deterministic new droplet/mist VTF coverage and two-part
configuration without native/trust changes. `python -I -m unittest` from tools is not supported by
unittest path isolation; use the repository test driver or an isolated runner adding tools to sys.path.
Reads repository sources; launches only LuaJIT subprocesses. No game, source-project or network writes.
Exit 0 success, nonzero unittest failures. Lua execution skips when LuaJIT is unavailable.
