"""Validate and summarize R12 Source/Remix memory snapshots; see vram_census.py.md."""
from __future__ import annotations

import argparse
from collections import defaultdict
import csv
import datetime
import io
import json
from pathlib import Path
import re

ALLOCATION = re.compile(r"\[RTX Allocation\] (\{.*\})")
SOURCE = re.compile(r"^R12_(TEXTURE|VRAM|CONTEXT|PROBE) ([\w.-]+) (\{.*\})\s*$", re.M)
CATEGORIES = {1: "app_buffers", 2: "app_textures", 3: "replacement_geometry", 4: "buffers",
              5: "acceleration_structures", 6: "opacity_micromaps", 7: "replacement_textures", 8: "render_targets"}


def utc_time(value):
    stamp = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if stamp.tzinfo is None:
        raise ValueError("telemetry timestamps must include a time zone")
    return stamp.astimezone(datetime.timezone.utc)


def telemetry(body, since=None):
    truncated = bool(body and not body.endswith("\n"))
    if truncated:
        body = body[:body.rfind("\n") + 1]
    reader = csv.DictReader(io.StringIO(body))
    if not reader.fieldnames or reader.fieldnames[0] != "time_utc" or len(set(reader.fieldnames)) != len(reader.fieldnames):
        raise ValueError("invalid telemetry header")
    samples = []
    for row in reader:
        if None in row or any(value is None for value in row.values()):
            raise ValueError("invalid telemetry column count")
        stamp = utc_time(row["time_utc"])
        sample = {"time_utc": row["time_utc"]}
        for key, value in row.items():
            if key == "time_utc":
                continue
            if value and (not value.isascii() or not value.isdigit()):
                raise ValueError("invalid telemetry counter")
            sample[key] = int(value) if value else None
        if since is None or stamp >= since:
            samples.append(sample)
    return dict(samples=samples, truncated_tail_omitted=truncated)


def allocations(body):
    complete, current = [], None
    for match in ALLOCATION.finditer(body):
        row = json.loads(match[1])
        if row["event"] == "begin":
            if current is not None:
                raise ValueError("allocation snapshot interrupted before end")
            if row.get("whole_frame"):
                raise ValueError("whole-frame profiler includes already released resources")
            current = dict(frame=row["frame"], expected=row["groups"], rows=[])
        else:
            if current is None or row["frame"] != current["frame"]:
                raise ValueError("allocation row outside its snapshot")
            if row["event"] == "group":
                if not isinstance(row.get("bytes"), int) or row["bytes"] < 0 or row.get("count", 0) < 1:
                    raise ValueError("invalid allocation count/bytes")
                current["rows"].append(row)
            elif row["event"] == "end":
                if len(current["rows"]) != current["expected"]:
                    raise ValueError("allocation snapshot missing groups")
                complete.append(current)
                current = None
            else:
                raise ValueError("unknown allocation event")
    if current is not None:
        raise ValueError("truncated allocation snapshot")
    return complete


def summarize_allocations(snapshot):
    categories = defaultdict(int)
    for row in snapshot["rows"]:
        if row["device_local"]:
            categories[CATEGORIES.get(row["category"], "unknown")] += row["bytes"]
    app = [row for row in snapshot["rows"] if row["category"] == 2 and row["device_local"]]
    return dict(frame=snapshot["frame"], device_local_categories=dict(categories),
                app_texture_groups=sorted(app, key=lambda row: row["bytes"], reverse=True),
                all_groups=snapshot["rows"])


def source_snapshots(body):
    stages = {}
    for match in SOURCE.finditer(body):
        kind, label, content = match.groups()
        stage = stages.setdefault(label, dict(textures=[], vram=[]))
        value = json.loads(content)
        if kind == "TEXTURE":
            stage["textures"].append(value)
        elif kind == "VRAM":
            stage["vram"].append(value)
        else:
            stage[kind.lower()] = value
    for label, stage in stages.items():
        if stage.get("probe", {}).get("truncated"):
            raise ValueError(f"{label}: native probe traversal was truncated")
        count = stage.get("probe", {}).get("textures")
        if count is not None and count != len(stage["textures"]):
            raise ValueError(f"{label}: texture rows lost/truncated ({len(stage['textures'])}/{count})")
        groups, formats, families = defaultdict(int), defaultdict(int), defaultdict(int)
        for texture in stage["textures"]:
            size = texture.get("Size")
            if not isinstance(size, int) or size < 0:
                raise ValueError(f"{label}: missing/invalid Source byte estimate")
            groups[texture.get("TexGroup", "unavailable")] += size
            formats[texture.get("Format", "unavailable")] += size
            name = str(texture.get("Name", "")).lower().replace("\\", "/")
            family = ("eye_white_proxies" if "nativeloader/eye_whites/" in name else
                      "mmd_base_textures" if name.startswith("mmd/t/") else
                      "spawn_icons" if name.startswith("spawnicons/") else "other")
            families[family] += size
        stage["source_estimates"] = dict(bytes=sum(groups.values()), by_group=dict(groups),
            by_format=dict(formats), by_family=dict(families),
            largest=sorted(stage["textures"], key=lambda row: row["Size"], reverse=True)[:30])
    return stages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--console", type=Path)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--telemetry", type=Path, help="the companion's existing local vram.csv; no game input")
    parser.add_argument("--since", type=utc_time, help="include telemetry at or after this ISO time with time zone")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    if not any((args.console, args.runtime, args.telemetry)):
        parser.error("give at least one console, runtime or telemetry input")
    if args.since is not None and not args.telemetry:
        parser.error("--since requires --telemetry")
    result = {}
    if args.console:
        result["source"] = source_snapshots(args.console.read_text(encoding="utf-8", errors="replace"))
    if args.runtime:
        result["allocations"] = [summarize_allocations(value) for value in
            allocations(args.runtime.read_text(encoding="utf-8", errors="replace"))]
    if args.telemetry:
        result["telemetry"] = telemetry(args.telemetry.read_text(encoding="utf-8"), args.since)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
