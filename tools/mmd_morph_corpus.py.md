# mmd_morph_corpus.py

Audits the R10 PMX corpus summaries, measures standard morph sides, mines exact
group recipes and near-identical vertex-offset synonyms, and emits the Character
Motion Importer's reviewed semantic table and CP932 decoder data (ADR 0089).

```powershell
python tools/mmd_morph_corpus.py --corpus <corpus.jsonl> --out out/r10/corpus-analysis.json --sample-offsets 48 --data out/r10/stage/character-motion-importer/mmd_vmd_npc/data_static/mmd_vmd_npc
python tools/mmd_morph_corpus.py --corpus <corpus.jsonl> --out out/r10/motion-coverage.json --motion <imported-motion-or-built-header.json> --sample-offsets 0
```

Inputs: the corpus scanner's JSONL (morph names, panels, types, measured `left`
weight share, group children, and source PMX paths); optional motion JSON's
`flexes[].m`/`mmd` identities. The deterministic offset sample reads those PMX
files. It accepts a cosine >=0.995 and a displacement-norm ratio 0.95–1.05,
on the same panel and measured side. Only a unit-weight single child, or a
complete opposite-sided pair, becomes group synonym evidence. An alias needs
three corroborating observations and no conflicting meaning. Corpus entries
can be variants/copies; observations do not claim independent authors.

Outputs: JSON report (counts, coverage, evidence, rejected aliases, offset sample
paths/errors) under `--out`; with `--data`, `morph_semantics.json` and `cp932.json`
in that staged folder. Never pass `packages/`; import the reviewed staged data
using `inputs.py import`. No model bytes, translations of model code, or paths
are shipped in either table. Counts/relations, not models, are test fixtures.
CP932 data is generated from Python's codec; exact names are never NFKC folded.
NFKC is used only to audit semantic variants.

Side effects: creates/writes the requested outputs; reads models only when
sampling offsets. Exit 0 on success; argument/input errors are nonzero. No
network, game changes, publishing or native build. Source models remain on the
existing Source-flex path. See [the tests](tests/test_mmd_morphs.py.md).
