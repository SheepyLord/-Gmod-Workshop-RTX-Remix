# 0062: loader layer precedence, performance tiers and GPU crash dumps

- Status: Accepted 2026-10-31
- Decided by: the user, approving R5 proposals 1, 2 and 4; R6 plan's tier decisions

## Context

The package's Custom preset was tuned for an RTX 5090. The runtime's automatic memory policy
does not run under Custom. Loader-written Remix layers were listed after package layers,
although Remix takes the first DXVK layer containing an `rtx.*` option. This prevented ADR 0030's
non-NVIDIA preset from winning. See [R5's research](../handover/R5-stability-proposal.md) and
[the R6 plan](../handover/R6-plan.md).

## Decision

Amend ADR 0030's placement: put loader Remix layers before the package's short DXVK copies
(ADR 0036), then loader diagnostics read by DXVK's merged config, then the user's root `dxvk.conf`.
Keep `rtx.conf` and `user.conf` priorities and the 259-character list budget. Report the actual
list in status. Do not mix the two kinds of loader option in a shared file.

Implement the R6 plan's automatic high/medium/low GPU tiers and explicit config override, using
the NVIDIA adapter with the most dedicated VRAM. Use package tier files when available and the
approved built-in low fallback for an older package. Non-NVIDIA systems retain their Auto layer.

The VRAM limits are inclusive 8.5/12.5 GiB. A recognized four-digit consumer `RTX <generation><class>0`
name limits classes 8/9 to high, 7 to medium and 5/6 to low; Laptop lowers that class tier one
step. Ti and Super do not change it. Select the lighter of class and VRAM; unmatched names use
VRAM alone. `remix.performance_tier` defaults to auto and can select high/medium/low explicitly.
An invalid value, including a wrong JSON type, becomes auto with an activation note. An unknown
GPU query applies no tier layer, preserving the existing failure behavior.

Tier files are ordinary journaled runtime payload at `config/dxvk-tiers/<tier>.conf`, not a new
manifest kind. The selected medium/low file becomes the short copy `native-loader/remix/tier.conf`
and goes first in DXVK_CONFIG_FILE. The pure plan selects from the runtime's journal records;
activation checks payload metadata before using it. Missing low uses exactly the five approved
fallback options; missing medium lists no tier layer. High lists none. Inactive/stale copies are
never listed. The existing source-path fallback for an unwritable package copy also updates I2's
layer field so it matches the list. Status/log/CLI expose I2 and config notes; the menu previews
the same pure selection before its generated script is prepared, without reading last session's
status or consuming diagnostics. The six new menu translations are agent-written, awaiting review.

GPU crash dumps remain off by default, with `next_start` and `always` config modes. Keep the
one-start consumption record in a loader-owned file instead of editing the player's config.
Aftermath and `rtx.enableGpuCrashState` belong together after the package copies: all three
are startup `Config` reads in `dxvk_options.cpp:36-39`, not Remix RtxOptions.

The loader prepares `native-loader/remix/diagnostics.conf` and `native-loader/logs/gpu/`, then
uses CREATE_NEW for `native-loader/remix/gpu-crash-dumps.used` before applying the environment
and initializing the runtime. This consumes the first prepared RTX activation attempt, including
one that crashes or fails later during startup; an interrupted/empty marker counts as consumed.
Only one simultaneous start wins. RTX-off starts and read-only CLI/menu previews do not claim it.
The player can request another one-start capture by removing that loader-owned marker while the
game is closed, leaving config set to next_start. Off and always do not clear the marker.

The absolute DXVK_AFTERMATH_DUMP_PATH is set only for this process and is restored on activation
rollback. An existing destination is noted and replaced for the diagnostic session. A failed
diagnostics preparation disables the diagnostic layer/request with a note and leaves RTX usable.
The generated layer and consumed marker can remain as inert caches. The loader writes dumps to a
local folder, but Remix passes Aftermath dumps to its Sentry crash reporter, which uploads them
when the player accepts Remix crash reporting. R6 does not change that consent or upload behavior.

## Consequences

The non-NVIDIA preset can override the package as intended. Smaller NVIDIA GPUs get lighter
defaults without changing the high tier's look. Diagnostics are opt-in, with local dump files and
Remix's existing consent-controlled Sentry upload; runtime environment variables and the root
DXVK config can still override diagnostic options.

## Alternatives considered

- Keep appending loader Remix layers: the package wins the affected keys.
- Force Remix Auto on small NVIDIA GPUs: changes more of the look than the approved tiers.
- Rewrite config to consume `next_start`: the player's configuration is not loader-owned state.

## Review corrections (2026-10-31)

The user's T1 fix-pass instructions supersede the implementation details above in these cases:

- A failed built-in low-layer write costs the tier defaults, not RTX. Remove every occurrence of
  that fallback from the effective DXVK list/environment, clear I2's layer and report a note, so
  an old file cannot silently apply. Package-copy source fallback remains as already described.
- Invalid `diagnostics.gpu_crash_dumps` values/types become off with a note, like invalid tier
  settings become auto; they do not reject the whole configuration.
- An RTX start with diagnostic mode off removes the one-start marker, best effort with a note on
  failure. Thus next_start -> off (one RTX start) -> next_start captures again without manual
  deletion. Always and read-only previews leave the marker alone; RTX-disabled starts do too.
- An empty GPU query honors explicit tier overrides and says "GPU not read". Known non-NVIDIA
  adapters still receive no tier layer. An override always reports source config, including a
  built-in fallback; source fallback identifies an automatic low selection using built-in text.
- The menu row requires a listed tier layer and an adapter description. Startup supplies the
  effective plan after writing layers; vanilla fallback supplies an inactive plan. A read-only
  preview applies the ADR 0056 render-recipe refusal. High and pre-R6 medium list no tier row.
- Driver description conversion failures keep the adapter's vendor/VRAM with an empty name;
  unrecognized model classes, including professional laptop names, use only the VRAM rule.
