# Bundled interface translations

These catalog data files include translated text from the GPL RTX fixes and are distributed under
GNU GPL version 2; see [COPYING](COPYING). The package includes these editable source catalogs
and their license under `nativeloader/resource/bundled-translations/`.

These six gettext catalogs translate the bundled RTX add-ons' interfaces and the Destruction
debug HUD. Edit `msgstr`; keep printf conversions in order. Product names, identifiers, file paths
and diagnostic codes stay literal. `unchanged.json` lists the reviewed words that are intentionally
identical to English, including French cognates.

`NL("text")` translates a displayed phrase. `NN("text")` marks a phrase kept as data until display;
it leaves the value unchanged. `NP("text")` registers a stable engine phrase for entity/property
metadata. Tool and undo phrase keys remain stable. Server glass notices send a format and arguments
to the receiving client, which chooses its own language.

The sources are in `packages/`, retaining each part's license. Existing keyed catalogs stay in their
own add-ons; these files cover newly localized interfaces. The companion catalog is separate because
the same English word can have different meanings in different contexts.

```powershell
python tools\companion_i18n.py update
python tools\companion_i18n.py check
python tools\check_addon_i18n.py
```

The package build embeds these catalogs in `nativeloader/i18n_data.lua`. Missing, blank, fuzzy,
duplicate or unreviewed English entries fail the build. `--allow-incomplete` is available for local
drafts, and is never used by the packager. Commands and console diagnostics remain English for
support. User-provided model names, paths, bone names and runtime diagnostic identifiers are data,
not text to translate.

Installed catalogs are source copies for review. Make lasting edits in the repository and rebuild;
the loader restores installed package files at the next start.
