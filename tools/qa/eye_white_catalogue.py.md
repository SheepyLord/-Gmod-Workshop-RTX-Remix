# eye_white_catalogue.py

Runs the shipped Lua eye-white name matcher against a PMX JSONL corpus and installed Hotloader
manifests without modifying their contents. No independent Python approximation of the rules.

```powershell
python tools/qa/eye_white_catalogue.py --corpus <main>/out/r10/corpus.jsonl --library poc=H:/SteamLibrary/steamapps/common/GarrysMod_PoC/garrysmod/data/mmd_hotloader/assets --out out/r10/catalogue.json
```

`--library LABEL=ASSETS_DIRECTORY` is repeatable, including a read-only field catalogue. Optional
`--luajit EXE` overrides normal PATH/user-install discovery. Outputs JSON with model/material counts,
matched surfaces/names, shared-texture counts, and near misses for manual review. It cannot label
unnamed/combined surfaces from names alone; reported near misses are candidates, not ground truth.
With `--out` writes only that report; otherwise stdout. Temporary Lua inputs/runners stay in the
repository's `out/tmp` and are removed afterwards. Reads source catalogue/manifests and matcher only.
Exit 0 on success; argparse 2 for missing/bad arguments; nonzero on Lua, decoding or I/O failure.
