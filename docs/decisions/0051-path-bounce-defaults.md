# 0051: Default path bounces to 1–12

- Status: Accepted 2026-10-30
- Decided by: the user's latest correction, "please set rtx.pathMaxBounces default to 12 instead"

## Decision

Keep the minimum default at 1 and use 12 as the maximum default in the runtime option metadata,
every graphics quality preset, the package's classic defaults layer and the companion numeric
override's draft. The companion accepts at most 15, matching the runtime's existing bound.

These are defaults. Explicit user/environment overrides remain higher priority. The screenshot's
User Settings value 16 is an existing override, so changing the default does not silently erase it.
Reset that native option to use the new default. No user.conf is edited or migrated by this change.

## Validation

The companion lifecycle harness checks twelve on explicit activation, rejection of sixteen, and preservation of
an intentional eight-bounce override. Preset assignments and the packaged layer are reviewed with
the source build and package comparison. No shader ABI or ray-interaction budgets change.
