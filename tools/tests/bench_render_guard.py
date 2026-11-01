"""Measure added guard lookups/time with a 1,200-path, 761-mount slow-file.Read double."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import sys

import test_render_guard as guard_tests


def benchmark(guard, repeats, lookup_ms):
    runs = []
    for _ in range(repeats):
        done = subprocess.run(
            [guard_tests.LUAJIT, str(Path(__file__).with_name("render_guard_harness.lua")),
             str(guard), "r8_material_bench", str(lookup_ms)], cwd=guard_tests.REPO,
            capture_output=True, encoding="utf-8", errors="replace", timeout=120)
        if done.returncode:
            raise RuntimeError(done.stdout + done.stderr)
        runs.append([json.loads(line[6:]) for line in done.stdout.splitlines() if line.startswith("BENCH ")])
    cases = []
    for position, first in enumerate(runs[0]):
        rows = [run[position] for run in runs]
        for row in rows:
            if {key: value for key, value in row.items() if key != "elapsed_ms"} != {
                    key: value for key, value in first.items() if key != "elapsed_ms"}:
                raise RuntimeError("nondeterministic counters: " + first["case"])
        cases.append({**first, "elapsed_ms": round(statistics.median(row["elapsed_ms"] for row in rows), 6),
                      "modeled_lookup_ms": first["file_reads"] * lookup_ms})
    return {"guard": str(guard), "cases": cases, "runs": runs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guard", type=Path, default=guard_tests.GUARD)
    parser.add_argument("--baseline-guard", type=Path)
    parser.add_argument("--lookup-ms", type=float, default=1.0)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--out", type=Path, default=guard_tests.REPO / "out/r8-compat/material-cost.json")
    args = parser.parse_args()
    if not guard_tests.LUAJIT:
        parser.error("LuaJIT is required")
    if args.repeats < 1 or not 0 <= args.lookup_ms <= 10:
        parser.error("repeats must be positive; lookup-ms must be in [0, 10]")
    result = {"schema": 1, "paths_per_case": 1200, "modeled_mounts": 761,
              "failed_lookup_ms": args.lookup_ms, "repeats": args.repeats,
              "scope": "Added guard I/O and harness elapsed time only; no engine/VFS/GPU or game measurement"}
    if args.baseline_guard:
        result["baseline"] = benchmark(args.baseline_guard.resolve(), args.repeats, args.lookup_ms)
    result["current"] = benchmark(args.guard.resolve(), args.repeats, args.lookup_ms)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for variant in ("baseline", "current"):
        for case in result.get(variant, {}).get("cases", []):
            print(f"{variant:8s} {case['case']:16s} {case['elapsed_ms']:9.3f} ms "
                  f"{case['file_reads']:4d} reads {case['archive_probes']:7d} modeled mount probes")
    print("Receipt:", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
