# test_adaptive_emission.py

Offline regression tests for the [MMD PBR skill](../../skills/mmd-remix-pbr/SKILL.md): the USD writer,
publish-time eye-class selection and normalised emission levels, CLI/settings overrides, byte-range
edits to already published layers, dry runs, idempotence, preflight failures and packaging.

## Usage

From `tools/`: `python -m unittest discover -s tests -p test_adaptive_emission.py -v`.
Also runs in `tools\test.ps1 -Config Release`. Requires only Python's standard library.

## Inputs and outputs

Generates synthetic USD, DDS and rpai-cache fixtures under the worktree's `out/tmp/`, with DDS
encoding mocked. Verifies the exposure-1 derivation, existing fallback values, UTF-8 BOM, CRLF,
comments, non-emissive shaders and package byte equality. Temporary fixtures are removed after use.
Reads the skill's source files; never connects to or launches a game, loads AI models or downloads.

## Exit codes

0 when all tests pass; 1 on failure (unittest).
