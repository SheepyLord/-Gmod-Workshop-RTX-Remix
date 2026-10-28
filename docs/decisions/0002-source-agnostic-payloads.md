# 0002: Payloads are source-agnostic; the Workshop route is decided after a private upload test

- Status: Accepted 2026-10-27
- Decided by: the user (SheepyLord)

## Context

The intended distribution is a Workshop item carrying the Remix runtime (about 930 MB of DLLs plus
an `.exe`). Stock `gmad.exe` refuses `.dll`/`.exe`, and the GMod wiki lists them as restricted for
Workshop items ([RESEARCH.md §5](../RESEARCH.md)). Whether `gmpublish` or the Workshop accepts an
archive built with another packer, and whether such an item stays up, is unknown. Size is not a
problem: installed items reach 3.2 GB.

## Decision

- The loader treats every source the same: a package is a `.gma` with `native/manifest.json`,
  wherever it comes from (Workshop folder, local file, unpacked development folder).
- The manifest format leaves room for a declared download URL with a pinned SHA-256, to be added
  only if the Workshop route fails.
- The PoC uses local packages. M6 runs a private-visibility upload test, then this record is updated
  (or superseded) with the chosen route.
- Payloads are never disguised as whitelisted file types to slip past the Workshop's checks.

## Consequences

- Development does not depend on the Workshop at all.
- Two possible download paths must stay in mind when designing discovery and integrity checks.
- The GMA reader must handle LZMA-wrapped archives (what `gmpublish` uploads produce).

## Alternatives considered

- **Binaries inside the Workshop `.gma`, committed to now**: the user's original design; kept as the
  first option for M6 but not assumed before the upload test.
- **Workshop manifest + GitHub Releases binaries, committed to now**: complies with the whitelist but
  needs network code in the bootstrap before we know it is necessary.
