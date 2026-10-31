# nativeloader_model_layers.lua

RTX-only client outline suppression ([ADR 0047](../../../../../docs/decisions/0047-ignore-incompatible-model-outlines.md),
[ADR 0059](../../../../../docs/decisions/0059-outline-shell-rule-opt-in.md)). Layered facial cutouts are
corrected in the runtime; this file only decides which outline geometry Remix hides. Two archived
client settings drive two owned, NoSave runtime options:

| Setting | Default | Drives | What it hides |
|---|---|---|---|
| `nativeloader_ignore_outlines` | 1 | `rtx.gmod.ignoredOutlineTextures` | the textures of outline materials of loaded models, by name (below); the Model outlines checkbox |
| `nativeloader_ignore_outline_shells` | 0 | `rtx.gmod.ignoreOutlineMeshes` (`True`/`False`, sent either way) | the runtime's rule: every opaque model draw that culls its front faces (D3D `CULL_CW`). GMod culls that way for real mirrored geometry too, so it is opt-in and console only |

**Which materials.** Only materials bound to model entities (a `.mdl` model; the world, brush
entities and sprites never count, so map textures such as `white_outline` stay visible): the model's
materials, its sub-materials, and the private proxy materials of the local body
(`rtx_pseudoplayer`'s `RTXMaterials`; an entry without a material, a slot it could not copy, is
skipped). An outline is a name starting `outline` or ending `_outline(s)`, `-outline`, ` outline`, or
with `outline` between separators; in the MMD template family (two or more `template ...`
materials, parenthesized source suffixes ignored) also the dedicated `hei` and `touming` slots.
Outline names are given to `RemixMaterial.TrackMaterial` once; procedural ones (`!` sub-materials,
proxies) are not, they get hashes when drawn. A texture shared with an ordinary material of any
loaded model is never hidden.

**Bounded work per frame.** Entities are found by `OnEntityCreated` and a sweep of `ents.GetAll()`
when suppression starts and every 10 s, then looked at in turn, new ones first, at most 256 material
slots per frame: model and skin (a model's material list is read once per model, skin and skin
count), sub-materials and proxy entries. An entity's set of names is rebuilt only when one of those
changed. Names are reference-counted by the entities that use them: a removed entity's names are
dropped and no longer looked up. `RemixMaterial.GetAllTextureHashes` runs for at most 16 names per
frame, and only for a new name, a name whose texture has no hash yet (retried after 0.25 s, doubling
to 4 s) or every name after `RemixMaterial.GetMaterialHashRevision()` changed (polled every 0.1 s).
Without a revision (nil: the native lookup is busy or unavailable) every name is read again after
0.5 s, doubling to 8 s. The hidden list and its protection are rebuilt only when a name's hashes or
uses changed. The global cached-material registry is not scanned.

**Writes.** Think publishes the two options when their value changes. A write Remix refuses (it
prints a warning) is tried again after 1 s, doubling to 60 s, not every frame. Turning
`nativeloader_ignore_outlines` off clears the owned list and stops all lookups; removed entities are
still dropped every 10 s. Original materials, other categories, entity overrides, Steam files and
user.conf are not modified. The native runtime hides matching geometry from primary, shadow and
reflection rays.

Resources are client-local tables and native lookups; no server or network messages. The command
`nativeloader_model_layers_status` prints both switches, the counts of entities and materials
followed, and the texture list sent. No process exit code. Tests:
[`tools/tests/test_model_layers.py`](../../../../../tools/tests/test_model_layers.py.md).
