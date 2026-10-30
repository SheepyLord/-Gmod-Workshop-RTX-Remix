# 0036: The runtime reads the package's Remix layers from short copies

- Status: Accepted 2026-10-29. Amends [0008](0008-activation-at-startup.md) (how the layer lists name
  the package's files), [0021](0021-remix-defaults-in-one-low-layer.md) (its consequence that the list
  stays far below the limit) and [0030](0030-non-nvidia-gpus-and-late-runtime-dlls.md) (the layer
  folder it writes into).
- Decided by: the user, on R3-017 ("Yes, fix R3-017", to copying the package's layers under short
  fixed names into `native-loader\remix` at each RTX start), Claude choosing how. Loader 0.6.0.

## Context

The runtime reads `DXVK_CONFIG_FILE` and `DXVK_RTX_CONFIG_FILE` into a `MAX_PATH` buffer
(`src/util/util_env.cpp:47-54` in the fork). A value of 260 characters or more reads as empty, and
`RtxOptionLayer::resolveConfigPaths` then loads `dxvk.conf` alone: every layer of the package is
dropped without a message ([RESEARCH.md](../RESEARCH.md) sections 19 and 32). ADR 0021 kept the list
"near 120 characters" and made the loader note a longer one; since then the package's version grew to
33 characters (`0.0.0-dev.20261030022927+8beef27e`), the payload folder's path to 74 (87 with
`/config/dxvk/`, which every layer repeats), the package to two layers, and ADR 0030 added a layer
without an NVIDIA GPU. Measured for the published
package: 237-241 characters on an NVIDIA GPU, 273-277 without one. So on AMD and Intel GPUs an RTX
session ran without the package's settings, and a probe build with a longer version started with a
black screen on this machine (R3-017, [R3-triage.md](../handover/R3-triage.md)).

## Decision

1. **The lists name copies.** `activate::plan` lists each package layer as
   `native-loader/remix/dxvk-<n>.conf` or `native-loader/remix/rtx-<n>.conf` (`n` from 1, in the
   manifest's order) and records each copy's source (`Plan::layer_copies`). The published package's
   list becomes `native-loader/remix/dxvk-1.conf,native-loader/remix/dxvk-2.conf,dxvk.conf` (73
   characters; 109 with the non-NVIDIA layer), whatever the version or generation.
2. **The bootstrap writes them at every RTX start**, after it has checked each source against the
   journal (size and time, as before), byte for byte, and only when a copy differs. A copy changed by
   hand is written again.
3. **A copy that cannot be written falls back to its source** in the list (`activate::use_sources`),
   with a session note, and a note when the list is then too long for the runtime.
4. **Reporting:** `status.json` `activation.layer_copies` (and `nlctl activation`) gives each copy with
   its source; `activation.layers` stays what the runtime reads. The length note stays, for a long list
   of the user's own.
5. `install-loader.ps1 -RemoveState` removes the copies with the loader's other files in
   `native-loader\remix`.

## Consequences

- The package's layers reach the runtime on every GPU, and a longer version, package id or more layers
  cannot push them out. Only a long `DXVK_CONFIG_FILE` of the player's own still can, and is noted.
- The order of the layers, and so Remix's layer names and priorities (which depend on the position in
  the list, RESEARCH.md section 19), are unchanged; so is the player's `dxvk.conf` and `rtx.conf` on top.
- An RTX start reads the layer files and compares them with the copies: a few hundred kilobytes.
- The Remix log's "Using config paths from DXVK_CONFIG_FILE" line names the copies; `status.json` maps
  them back to the package.
- A copy whose package no longer has that many layers stays in the folder, unused, until
  `-RemoveState`.

## Alternatives considered

- **Raise the buffer in the runtime** (`getEnvVar` sized from `GetEnvironmentVariableW`'s answer): the
  root fix, but it needs a runtime rebuild and a new 363 MB DLL in Git LFS, and helps only runtimes
  built after it. Worth doing with the next runtime change; the copies work with every runtime.
- **Copy only when the list would be too long:** keeps today's paths on NVIDIA GPUs, but the copying
  would then run only on the machines nobody here tests on, which is how R3-017 went unnoticed.
- **Shorter payload folder names** (`<id>/<generation>`): changes the deployer's layout (ADR 0007) for
  every file, and a longer id or more layers would reach the limit again.
- **One merged file:** the runtime's layers keep their own priorities (texture-hash sets combine across
  layers), so a merge would not be the same configuration.
