# R20-F: published-package field QA

Branch `r20-field`, from `8332e03`; [brief](R20-F-field-qa.md), [shared plan](R20-plan.md).
Work in progress. Only this report is committed; scratch drivers and evidence stay under this
worktree's `out/r20f/`. No gameplay, package, loader or runtime change is authorized by this task.

## Baseline and decisions

The task-specific field-launch permission supersedes the shared plan's earlier PoC-only launch
rule. The existing game, Workshop content and standalone add-ons are exercised in place. No
installation, config replacement, graphics-option change or publication is performed.

The field has the actual release loader **0.14.0**, SHA-256
`256f245fbb6dde4b2b41cba070c1a4fcc4a88110865941ce781ea065cad40e5b`, matching R19's
release receipt and its previous `status.json`. Its `bootstrap-install.json` still says 0.13.0;
that stale receipt is recorded, not rewritten. The published receipt names
**`0.0.0-dev.20261106164627+a3df3af8`**, 1,955,100,507 bytes, archive SHA-256
`71aa0745f72da9ff6e69e14834c8c3d41cfe85d006406593974ea4f6a31c72a3`.
Steam initially has the older `20261106004558_ad5cf8e8` archive. A download-only start may
therefore precede the acceptance start, as the brief anticipates.

No `gmod.exe` or shared PoC lock was present at baseline. Field settings, the loader and watched
files were copied and hash-checked into `out/r20f/before/`; the registry was exported read-only.
The standalone Dynamic Toolgun Screen and Blood Overhaul contain **34** and **267** files,
respectively, indexed by SHA-256. No user console history was read.

## Checks

Evidence paths below are relative to this worktree's `out/r20f/`.

| Item | Result | Evidence |
|---|---|---|
| Steam depot baseline | **Pass**, verifier exit 0; full manifest results retained. | `verify-before.json`, `verify-before.log` |
| Loader, publication, coexistence baseline | **Recorded**; 0.14.0 release DLL verified, older cached package pending Steam refresh. | `before.json`, `status-before.json`, `published.json`, `preflight.log` |
| Published deployment / RTX / status | Pending. | Acceptance session to follow |
| 45 startup hint, real live settings | Pending; observe only. | Acceptance session to follow |
| 49 sky time / retained day length | Pending; observe migration and player choices. | Acceptance session to follow |
| 48 unique panels, citizen/ragdoll impacts, stains and live screen | Pending, with both standalone copies present. | Acceptance session to follow |
| 44 Physics Blood coexistence | Pending. | Acceptance session to follow |
| 51 stock two-prop dupe / icon | Pending; record and remove only this task's generated files. | Acceptance session to follow |
| 3840x2160 frame time / device loss | Pending, using the field's saved video settings. | Acceptance session to follow |
| Restoration and depot verification | Pending. | Final audit to follow |
| Release repository gate | Running. | `release-initial.log` |

## Open

Live checks and final Release gate are in progress. Any confirmed failure ends live testing and is
reported for the owning task; this task does not fix it.
