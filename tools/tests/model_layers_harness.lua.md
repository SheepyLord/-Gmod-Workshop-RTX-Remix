# model_layers_harness.lua

GPU-free client fixture for the shipped outline module. Called by
[test_model_layers.py](test_model_layers.py.md) with the production Lua path and a scenario. Mocks
only engine and native boundaries (entities, `ents.GetAll`, `RemixMaterial`, `RemixConfig`, a clock)
and counts the engine and native calls.

- Both settings: `nativeloader_ignore_outlines` archived with default 1, and
  `nativeloader_ignore_outline_shells` archived with default 0; `rtx.gmod.ignoreOutlineMeshes` is
  sent `False` unless the shell setting is on, and the two rules toggle independently (`shells`).
- Names: the MMD family's hei/touming, ordinary-image protection (`collision`, `ordinary_hei`),
  sub-materials added and removed (`submaterial`), private proxies and slots without a material
  (`proxy`), clientside entities (`client_entity`), skin changes (`skin_change`).
- Only model entities: map textures named `*_outline` in Remix's cached-material registry, on a brush
  entity or on the world are never hidden or tracked, and the registry is not scanned (`world`, and
  every scenario).
- Bounded work: settled frames look up and write nothing; an unresolved hash is retried with a
  growing delay (`late_hash`); 2001 entities are looked at a bounded share per frame, with at most a
  few dozen hash lookups and no `ents.GetAll` outside the sweep (`bounded`); without a revision names
  are re-read rarely and a changed binding is still seen (`nil_revision`); a revision change
  re-reads them (`revision`); a removed entity's names are dropped and no longer looked up, also
  while suppression is off (`prune`).
- A refused write waits 1 s, then 2 s, then 4 s before the next attempt (`retry`); missing APIs
  write nothing (`no_api`).

No files, network or user settings are changed. Exit zero on success; assertion failures are nonzero.
