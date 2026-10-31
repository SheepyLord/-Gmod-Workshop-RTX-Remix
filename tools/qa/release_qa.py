"""Release QA on one install: runs the scripted sessions of docs/TESTING.md's release protocol one after
another through tools/poc_session.py and checks each against the pass rules, so a single command says
whether a release is good on the user's own install (--field) or on the PoC (the package before its
publish). Changes nothing itself: the sessions only launch, probe and quit the game."""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
POC_SESSION = REPO / "tools" / "poc_session.py"
PROBES = Path(__file__).resolve().parent
MODERN_HOUSE_MAP_ITEM = "3495468649"  # the user's subscription that holds modern_house (RESEARCH.md)
REGISTRY_KEY = r"HKCU\Software\Valve\Source\garrysmod"
# Files a QA run must leave as they were.
WATCHED = ("user.conf", "rtx.conf", "bin/win64/winmm.dll", "bin/win64/winmm.pdb",
           "native-loader/config.json", "native-loader/bootstrap-install.json")
# Settings the game itself writes at a normal quit: compared value by value. A new key (an add-on's
# new convar) is reported; a changed value fails in client.vdf (the player's add-on settings) and, in
# config.cfg, for the keys a session switches for a moment (R4-28: mat_queue_mode).
SETTINGS = {"config.cfg": "garrysmod/cfg/config.cfg", "client.vdf": "garrysmod/cfg/client.vdf"}
GUARDED_CONFIG_KEYS = ("mat_queue_mode",)
SETTING_LINE = re.compile(r'^\s*(.*?)\s*"([^"]*)"\s*$')
SESSIONS = {
    "session": {"probe": "rtx_session_probe.lua", "shots": 90, "map": "gm_construct"},
    "spawnmenu": {"probe": "spawnmenu_probe.lua", "shots": 60, "map": "gm_construct"},
    "map-glass": {"probe": "map_glass_probe.lua", "shots": 180, "map": "modern_house", "cheats": True},
    "spawned-glass": {"probe": "spawned_glass_probe.lua", "shots": 120, "map": "gm_construct", "cheats": True},
}
QA_LINE = re.compile(r"(?m)^NL_QA_([A-Z_]+) (.*?)\s*$")
GLASS_LINE = re.compile(r"(?m)^NL_GLASS (.*?)\s*$")
TOOLGUN_LINE = re.compile(r"(?m)^\[nativeloader\] Toolgun screen (\{.*\})\s*$")
STEP_FOLDER = re.compile(r"^(\d+)-")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def session_command(name: str, *, root: Path, evidence: Path, step: str, field: bool, extra: list[str]) -> list[str]:
    """The poc_session.py command line of one session. --field: the user's own install with its
    Workshop add-ons and its own window settings; otherwise the PoC, where the map is mounted from the
    user's subscription alone and queued rendering is switched on as the field has it."""
    spec = SESSIONS[name]
    command = [sys.executable, str(POC_SESSION), "--root", str(root), "--evidence", str(evidence)]
    if field:
        command.append("--allow-steam-managed")
    command += ["run", "--name", step, "--addons"]
    if field:
        command += ["--workshop", "--no-window", "--map", spec["map"]]
        if name == "session":
            command.append("--menu-shot")
    else:
        if spec["map"] == "modern_house":
            command += ["--map", "gm_construct", "--mount-workshop", MODERN_HOUSE_MAP_ITEM, "--change-map", "modern_house"]
        else:
            command += ["--map", spec["map"]]
        command += ["--console", "mat_queue_mode 2"]
    if spec.get("cheats"):
        command += ["--console", "sv_cheats 1"]
    command += ["--lua", str(PROBES / spec["probe"]), "--lua-shots", str(spec["shots"])]
    command += [f"--extra={value}" for value in extra]
    return command


def probe_lines(console: str) -> dict[str, list]:
    """NL_QA_<PART> lines by part, each value parsed as JSON when it is JSON."""
    lines: dict[str, list] = {}
    for part, payload in QA_LINE.findall(console):
        try:
            value = json.loads(payload)
        except ValueError:
            value = payload
        lines.setdefault(part, []).append(value)
    return lines


def check_record(record: dict) -> list[str]:
    """What the session record itself shows wrong (empty: nothing)."""
    if record.get("failed"):
        return [f"the session step failed: {record['failed']}"]
    problems = []
    if not record.get("map_loaded"):
        problems.append("the map did not load")
    if not record.get("normal_quit"):
        problems.append(f"no normal quit (exit {record.get('exit')})")
    if record.get("lua_errors"):
        problems.append(f"{record['lua_errors']} Lua errors in console.log")
    activation = record.get("activation") or {}
    if activation.get("outcome") != "active":
        problems.append(f"RTX is not active: {activation.get('outcome')} ({activation.get('reason')})")
    if record.get("status_errors"):
        problems.append(f"status errors: {record['status_errors']}")
    if not record.get("lua_shots_done"):
        problems.append("the probe did not finish (no NL_SHOT_DONE)")
    return problems


def glass_counts(console: str) -> dict[str, list[str]]:
    """NL_GLASS <event> <words...> lines by event, the last of each."""
    events: dict[str, list[str]] = {}
    for line in GLASS_LINE.findall(console):
        words = line.split()
        if words:
            events[words[0] if words[0] != "no" else line] = words[1:]
    return events


def word_after(words: list[str], key: str) -> int | None:
    try:
        return int(words[words.index(key) + 1])
    except (ValueError, IndexError):
        return None


def check_probe(name: str, console: str) -> list[str]:
    """What the probe's own lines show wrong for that session (empty: nothing)."""
    problems = []
    lines = probe_lines(console)
    if name == "session":
        guard = (lines.get("GUARD") or [None])[0]
        if not isinstance(guard, dict) or guard.get("missing"):
            problems.append("no render guard (NL_QA_GUARD)")
        elif guard.get("errors") or guard.get("cleanup_errors") or not guard.get("installation"):
            problems.append(f"render guard at start: {guard}")
        after = (lines.get("GUARD_AFTER_TOOLGUN") or [None])[0]
        if not isinstance(after, dict) or after.get("errors") or after.get("cleanup"):
            problems.append(f"render guard after the toolgun: {after}")
        if (lines.get("WEAPON") or [None])[0] != "gmod_tool":
            problems.append(f"the toolgun was not selected: {(lines.get('WEAPON') or [None])[0]}")
        toolgun = TOOLGUN_LINE.findall(console)
        state = json.loads(toolgun[-1]) if toolgun else {}
        if not state.get("draws") or state.get("error"):
            problems.append(f"toolgun screen redraw: {state or 'no status line'}")
    elif name == "spawnmenu":
        if not lines.get("TABS"):
            problems.append("no creation tabs listed (NL_QA_TABS)")
        for tab in lines.get("TAB_MISSING", []):
            problems.append(f"spawn menu tab not found: {tab}")
    elif name in ("map-glass", "spawned-glass"):
        events = glass_counts(console)
        if "done" not in events:
            problems.append("the glass probe did not reach its end")
        if name == "map-glass":
            if any(event.startswith("no glass") for event in events):
                problems.append("no glass pane found on the map")
            shards = word_after(events.get("after_first", []), "shards")
            if not shards:
                problems.append(f"the window did not break into shards: {events.get('after_first')}")
        else:
            spawned = word_after(["n", *events.get("spawned", [])], "n")
            after = word_after(events.get("after_shot", []), "shards")
            if not spawned:
                problems.append("the glass pane was not spawned")
            elif not after or after <= spawned:
                problems.append(f"the spawned pane did not break: {spawned} shard(s) before, {after} after")
    return problems


def snapshot(root: Path, evidence: Path, label: str) -> dict[str, str]:
    """SHA-256 of the watched files and of the game's registry key; keeps the export and copies of
    the settings files as <label>-<name>."""
    state = {relative: sha256(root / relative) if (root / relative).exists() else "absent" for relative in WATCHED}
    export = evidence / f"{label}-registry.reg"
    subprocess.run(["reg", "export", REGISTRY_KEY, str(export), "/y"], capture_output=True, check=False)
    state["registry"] = sha256(export) if export.exists() else "absent"
    for name, relative in SETTINGS.items():
        if (root / relative).exists():
            (evidence / f"{label}-{name}").write_bytes((root / relative).read_bytes())
    return state


def settings(path: Path) -> dict[str, str]:
    """A config.cfg or client.vdf as {key: value}: each line's last quoted string is its value and
    what comes before it its key (`bind "F1" "x"` is the key `bind "F1"`)."""
    values = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = SETTING_LINE.match(line)
            if match and match.group(1) and not match.group(1).startswith("//"):
                values[match.group(1)] = match.group(2)
    return values


def settings_changes(before: Path, after: Path, guarded=()) -> dict:
    """What a run changed in one settings file: `changed` values, `added` and `removed` keys, and
    `problems` (a changed or removed value, or only the guarded keys when `guarded` is given)."""
    old, new = settings(before), settings(after)
    changed = {key: [old[key], new[key]] for key in old if key in new and old[key] != new[key]}
    removed = sorted(key for key in old if key not in new)
    judged = [key for key in [*changed, *removed] if not guarded or key in guarded]
    return {"changed": changed, "added": {key: new[key] for key in new if key not in old}, "removed": removed,
            "problems": [f"{key}: {old.get(key)!r} -> {new.get(key)!r}" for key in judged]}


def crash_reports(root: Path) -> int:
    folder = root / "rtx-remix" / "logs" / ".sentry-native"
    return sum(1 for _ in folder.rglob("*.dmp")) if folder.is_dir() else 0


def next_number(evidence: Path) -> int:
    numbers = [int(match.group(1)) for child in evidence.iterdir() if child.is_dir()
               for match in [STEP_FOLDER.match(child.name)] if match] if evidence.is_dir() else []
    return max(numbers, default=0) + 1


def last_record(evidence: Path, step: str) -> dict | None:
    log = evidence / "session.json"
    history = json.loads(log.read_text(encoding="utf-8")) if log.exists() else []
    runs = [record for record in history if record.get("name") == step]
    return runs[-1] if runs else None


def evaluate(name: str, step: str, evidence: Path, output: str = "") -> dict:
    """Checks the recorded run `step` of session `name`. `output`: what poc_session.py printed, for
    the reason when it recorded no run (it refused before the launch)."""
    record = last_record(evidence, step) or {"failed": "no record of the run " + output.strip()[-400:]}
    console_path = evidence / step / "console.log"
    console = console_path.read_text(encoding="utf-8", errors="replace") if console_path.exists() else ""
    problems = check_record(record)
    if not record.get("failed"):
        problems += check_probe(name, console)
    if record.get("crash_reports"):
        problems.append(f"crash minidumps kept in {step}\\crash-reports: {record['crash_reports']}")
    return {"name": name, "step": step, "passed": not problems, "problems": problems,
            "seconds_to_map": record.get("seconds_to_map"), "exit": record.get("exit"),
            "shots": [shot.get("label") for shot in record.get("lua_shots") or []],
            "menu_screenshot": record.get("menu_screenshot")}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", required=True, help="game install (the field install needs --field)")
    parser.add_argument("--evidence", required=True, help="evidence folder (poc_session.py's, created if missing)")
    parser.add_argument("--field", action="store_true",
                        help="the user's Steam-managed install: Workshop add-ons mounted, the game's own window settings")
    parser.add_argument("--only", default=",".join(SESSIONS),
                        help=f"sessions to run, in this order (default: {','.join(SESSIONS)})")
    parser.add_argument("--extra", action="append", default=[],
                        help="launch option passed to every session, e.g. --extra=-insecure (repeatable)")
    parser.add_argument("--timeout", type=int, default=1200, help="seconds one session may take")
    parser.add_argument("--evaluate-only", action="store_true",
                        help="launch nothing: check the latest recorded run of each session in the evidence folder")
    args = parser.parse_args(argv)
    names = [name.strip() for name in args.only.split(",") if name.strip()]
    unknown = [name for name in names if name not in SESSIONS]
    if unknown:
        parser.error(f"unknown session(s) {unknown}; known: {list(SESSIONS)}")
    root, evidence = Path(args.root), Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    started = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    results = []
    if args.evaluate_only:
        history = json.loads((evidence / "session.json").read_text(encoding="utf-8")) if (evidence / "session.json").exists() else []
        for name in names:
            steps = [record.get("name") for record in history if str(record.get("name", "")).endswith(f"-{name}")]
            results.append(evaluate(name, steps[-1], evidence) if steps else
                           {"name": name, "step": None, "passed": False, "problems": ["no recorded run"]})
        before = after = None
    else:
        before, dumps = snapshot(root, evidence, "before"), crash_reports(root)
        number = next_number(evidence)
        for offset, name in enumerate(names):
            step = f"{number + offset:02d}-{name}"
            command = session_command(name, root=root, evidence=evidence, step=step, field=args.field, extra=args.extra)
            print(f"release_qa: {step}: {' '.join(command[1:])}", file=sys.stderr, flush=True)
            clock = time.monotonic()
            try:
                completed = subprocess.run(command, cwd=REPO, capture_output=True, text=True, encoding="utf-8",
                                           errors="replace", timeout=args.timeout, check=False)
            except subprocess.TimeoutExpired:
                results.append({"name": name, "step": step, "passed": False, "problems": [f"timed out after {args.timeout} s"]})
                continue
            result = evaluate(name, step, evidence, completed.stdout + completed.stderr)
            result["seconds"] = round(time.monotonic() - clock)
            results.append(result)
            print(f"release_qa: {step}: {'PASS' if result['passed'] else 'FAIL ' + '; '.join(result['problems'])}",
                  file=sys.stderr, flush=True)
        after = snapshot(root, evidence, "after")
        new_dumps = crash_reports(root) - dumps
        if new_dumps > 0:
            results.append({"name": "crash-reports", "step": None, "passed": False,
                            "problems": [f"{new_dumps} new Remix crash report(s) under rtx-remix\\logs\\.sentry-native"]})
    changed = sorted(key for key in (before or {}) if before[key] != after[key])
    game_settings = {name: settings_changes(evidence / f"before-{name}", evidence / f"after-{name}",
                                            GUARDED_CONFIG_KEYS if name == "config.cfg" else ())
                     for name in SETTINGS} if before else {}
    setting_problems = [f"{name} {problem}" for name, change in game_settings.items() for problem in change["problems"]]
    summary = {
        "root": str(root), "field": args.field, "started": started, "sessions": results,
        "unchanged": sorted(set(before or {}) - set(changed)), "changed": changed, "settings": game_settings,
        "passed": all(result["passed"] for result in results) and not changed and not setting_problems,
    }
    (evidence / "qa-summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    for result in results:
        print(f"{'PASS' if result['passed'] else 'FAIL'}  {result['name']:<14} {result.get('step') or ''}"
              + ("" if result["passed"] else "  " + "; ".join(result["problems"])))
    if changed:
        print(f"FAIL  changed by the run: {', '.join(changed)}")
    for problem in setting_problems:
        print(f"FAIL  setting changed by the run: {problem}")
    for name, change in game_settings.items():
        if change["added"]:
            print(f"note  {name}: {len(change['added'])} new key(s) ({', '.join(list(change['added'])[:6])})")
    print(f"{'PASSED' if summary['passed'] else 'FAILED'}: {evidence / 'qa-summary.json'}")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
