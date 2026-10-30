# 0038: Complete translations cover the bundled add-on interfaces

- Status: Accepted 2026-10-30, implementing the user's translation audit request.
- Decided by: the user: "Also localize every bundled add-on interface, if not translated yet";
  Codex choosing the implementation.
- Extends [0029](0029-companion-translations.md) beyond the companion's own panels.

## Decision

- Keep the existing add-ons' keyed catalogs and language overrides. Add Korean to Destruction and
  separate Traditional Chinese catalogs to Bodygroup Tool, Material Editor (including parameter
  help), Destruction and Motion Importer. Traditional Chinese must not select Simplified Chinese.
- Put newly localized RTX interface text in [companion/i18n/addons](../../companion/i18n/addons/README.md).
  Use a separate lookup namespace from the companion's own text to avoid ambiguous English words.
  The package embeds both namespaces. Tool IDs, convars, preset keys and user data do not change.
- Register stable engine phrases for metadata and undo labels. Format server-generated glass notices
  on the receiving client. The network message contains text and arguments, never executable Lua.
- Require complete release catalogs in both the companion packager and the runtime embedder.
  Draft-only commands may opt into English fallback. Check placeholders, duplicates and known text;
  record intentional unchanged names explicitly. Native add-on catalogs and language selectors get
  a separate LuaJIT check.
- Local modifications to the GPL RTX fixes stay inside the GPL package part. The derived interface
  catalog data carries GPL-2.0 too, with its editable PO sources and `COPYING` included in the package.
  No GPL implementation code is copied into the loader. Imports and indexes record the shipped sources.
- Long control labels get a full-width line in the RTX panels. Translation should not require the
  player to infer a clipped label.

No trust, loader deployment, native allowlist or field-install policy changes.
