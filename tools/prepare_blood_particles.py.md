# prepare_blood_particles.py

Linked/junction output directories are refused before encoding; resolved targets must stay under
this worktree's out. Game/source folders cannot become outputs through a linked textures folder.

Authors the original analytic droplet/mist's BC7 DDSs and four XXH64/XXH3 opacity material overrides.
It reads only the unchanged one-mip RGBA8888 VTFs produced by `prepare_blood.py`. Run after that tool:

```powershell
python -I tools/prepare_blood_particles.py --addon out/r20c/prepared/nlblood --mod out/r20c/prepared/nl_blood_overhaul_rtx --nvtt "C:/Program Files/NVIDIA Corporation/RTX Remix/exts/omni.flux.resources/deps/tools/nvtt/nvtt_export.exe"
```

Requires Python xxhash and NVIDIA's installed NVTT export CLI for **asset preparation only**. Normal
package builds use the indexed outputs and need neither dependency. Writes only under this
worktree's out: two DDSs, a marked idempotent section of replacements.usda and a PNG/hash provenance
record in particle-pbr-work. It never changes a VTF, package input, game, runtime option or source
project. If the sibling `provenance.json` has preparation schema 2, refreshes its final layer/DDS
generated hashes. Import only final DDSs with `inputs.py import` after visual verification.

Opacity comes from the authored coverage rather than a legacy modulate state. Metallic is zero,
roughness .18; a small scene-adaptive intrinsic fill (`--adaptive`, default .05, range 0–1) retains
unlit Source sprite colour through path tracing. The physical world stains keep their original
non-emissive PBR. Colour remains the Source material's live tint. Prompts are unnecessary: both
sprites are analytic, authored by this repository. Exit 0 success, 1 validation/encoder/I/O failure,
2 bad arguments. PNG generation uses the standard library; no source image is edited.
