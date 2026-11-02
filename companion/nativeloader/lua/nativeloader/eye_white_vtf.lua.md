# eye_white_vtf.lua

Pure Lua validator and texture-identity encoder. `proxy(bytes)` accepts the hotloader's one-frame,
one-depth, non-cubemap RGBA8888 VTF 7.2 layout (80-byte header, no thumbnail), up to 128 MiB. It validates
dimensions, mip byte counts and truncation before returning a copy with **one RGB low bit** toggled
in the top mip, preferring a transparent pixel among its first 1,024 pixels. Header, alpha, remaining
pixels and all lower mips remain identical. Unsupported formats fail closed, returning nil and a
reason. Exports `maxBytes` for preflight size checks.

This creates a distinct Remix image identity for an eye-only material; it does not generate an
emissive mask. Inputs/outputs are byte strings, without file or rendering side effects. No exit codes.
