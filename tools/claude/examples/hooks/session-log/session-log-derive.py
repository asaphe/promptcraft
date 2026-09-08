#!/usr/bin/env python3
"""Derive session-log entries from a Claude Code transcript and append them.

Called by session-log.sh on the Stop event. Also runnable by hand against any
transcript, which is how you backfill: the resume mark makes a re-run idempotent.

See README.md in this directory for the log format, the entry kinds, and the
environment variables read below.
"""
import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone

# Unset means the machine's local zone. see: README.md § Environment
LOCAL_TZ = None
if os.environ.get("SESSION_LOG_TZ"):
    try:
        from zoneinfo import ZoneInfo
        LOCAL_TZ = ZoneInfo(os.environ["SESSION_LOG_TZ"])
    except Exception:
        LOCAL_TZ = None

SESSIONS_DIR = os.environ.get(
    "SESSION_LOG_DIR", os.path.expanduser("~/.claude/session-logs"))
# Optional, absent is fine. see: README.md § Optional — the action ledger
LEDGER_DIR = os.environ.get(
    "SESSION_LOG_LEDGER_DIR", os.path.expanduser("~/.claude/local/action-ledger"))

# Opt-in: a generic default fabricates keys from version suffixes. see: README.md § Environment
_TICKET_PAT = os.environ.get("SESSION_LOG_TICKET_RE", "")
TICKET_RE = re.compile(_TICKET_PAT) if _TICKET_PAT else None

# `type == "user"` alone is ~80% machine-authored; promptSource is what separates them.
HUMAN_SOURCES = ("typed", "queued")
EDIT_TOOLS = ("Edit", "MultiEdit", "Write", "NotebookEdit")


def parse_ts(raw):
    """Transcript stamps are ISO-8601 UTC with a trailing Z, which Python 3.9 rejects."""
    if not raw:
        return None
    try:
        if isinstance(raw, (int, float)):
            return datetime.fromtimestamp(raw / 1000, timezone.utc)
        dt = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except Exception:
        return None
    # A ledger stamp with no offset would otherwise crash every aware/naive comparison below.
    return dt if dt.tzinfo else dt.astimezone()


def local_hhmm(dt):
    if dt is None:
        return "--:--"
    return (dt.astimezone(LOCAL_TZ) if LOCAL_TZ else dt.astimezone()).strftime("%H:%M")


def local_date(dt):
    if dt is None:
        return datetime.now().strftime("%Y-%m-%d")
    return (dt.astimezone(LOCAL_TZ) if LOCAL_TZ else dt.astimezone()).strftime("%Y-%m-%d")


def squash(text, limit=120):
    text = " ".join(str(text or "").split())
    return text[: limit - 1] + "…" if len(text) > limit else text


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") == "text")
    return ""


def rel(path, cwd):
    if not path:
        return None
    home = os.path.expanduser("~")
    if cwd and path.startswith(cwd.rstrip("/") + "/"):
        return path[len(cwd.rstrip("/")) + 1:]
    return path.replace(home, "~", 1) if path.startswith(home) else path


def read_records(path, skip):
    """Returns (records, total_lines). Malformed lines are counted, never fatal."""
    records, total = [], 0
    with open(path, errors="replace") as fh:
        for i, line in enumerate(fh):
            total = i + 1
            if i < skip:
                continue
            try:
                records.append(json.loads(line))
            except Exception:
                continue
    return records, total


MACHINE_PREFIXES = ("<task-notification", "<local-command", "<command-name", "<system-reminder")
QUEUED_GRACE_SEC = 300


def is_machine(text):
    """Task notifications ride the same queue as typed prompts; only the latter are asks."""
    return not text or text.lstrip().startswith(MACHINE_PREFIXES)


def derive_entries(records, meta, pending=None, seen_prs=None, last_edit=None):
    """Transcript records -> [(datetime, kind, text)]. Mutates meta, `pending` and `meta["last_edit"]`."""
    out = []
    pending = pending if pending is not None else []
    seen_prs = seen_prs if seen_prs is not None else set()
    for rec in records:
        kind = rec.get("type")
        ts = parse_ts(rec.get("timestamp"))

        if kind == "custom-title" and rec.get("customTitle"):
            meta["title"] = rec["customTitle"]
        elif kind == "user":
            # First cwd wins: a session that hops into a worktree still indexes under the repo it started in.
            if rec.get("cwd"):
                meta.setdefault("cwd", None)
                meta["cwd"] = meta["cwd"] or rec["cwd"]
                meta["seen"].add(rec["cwd"])
            if rec.get("gitBranch"):
                meta["seen"].add(rec["gitBranch"])
                if not meta.get("branch") or meta["branch"] in ("main", "master", "HEAD"):
                    meta["branch"] = rec["gitBranch"]
            if rec.get("isMeta") or rec.get("isSidechain"):
                continue
            if rec.get("promptSource") not in HUMAN_SOURCES:
                continue
            body = squash(text_of((rec.get("message") or {}).get("content")))
            if body:
                out.append((ts, "ask", body))
                meta["asks"] += 1
        elif kind == "assistant":
            files, agents, notes = [], [], []
            for block in (rec.get("message") or {}).get("content") or []:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name, inp = block.get("name"), block.get("input") or {}
                if name in EDIT_TOOLS:
                    f = rel(inp.get("file_path") or inp.get("notebook_path"), meta.get("cwd"))
                    if f and f not in files:
                        files.append(f)
                elif name == "Agent":
                    agents.append("%s — %s" % (inp.get("subagent_type") or "agent",
                                               squash(inp.get("description"), 60)))
                elif name == "Artifact":
                    notes.append("artifact %s" % squash(inp.get("action") or "publish", 40))
            fresh = [f for f in files if f not in (last_edit or [])]
            if fresh:
                out.append((ts, "edit", ", ".join(fresh)))
                last_edit = files
            for a in agents:
                out.append((ts, "agent", a))
            for n in notes:
                out.append((ts, "note", n))
            meta["last_edit"] = last_edit
        elif kind == "queue-operation":
            op, body = rec.get("operation"), rec.get("content") or ""
            if op == "enqueue" and not is_machine(body):
                pending.append([rec.get("timestamp"), squash(body)])
            elif op == "dequeue" and pending:
                pending.pop(0)
            elif op == "remove":
                trimmed = squash(body)
                pending[:] = [q for q in pending if q[1] != trimmed]
                # A removed human prompt was usually submitted and never became a turn.
                if not is_machine(body):
                    out.append((ts, "dropped", "never answered: %s" % trimmed))
        elif kind == "pr-link" and rec.get("prNumber"):
            pr_key = "%s#%s" % (rec.get("prRepository") or "", rec["prNumber"])
            if pr_key in seen_prs:
                continue
            seen_prs.add(pr_key)
            out.append((ts, "pr", "#%s %s — %s" % (rec["prNumber"],
                                                   rec.get("prRepository") or "",
                                                   rec.get("prUrl") or "")))
    # Emitted once, then dropped from `pending` so the next run cannot repeat it.
    now = datetime.now(timezone.utc)
    for entry in list(pending):
        qts = parse_ts(entry[0])
        if qts and (now - qts).total_seconds() > QUEUED_GRACE_SEC:
            out.append((qts, "dropped", "never answered: %s" % entry[1]))
            pending.remove(entry)
    return out


def derive_ledger(session, skip):
    """`run` entries join an already-classified ledger; this is never a second classifier."""
    path = os.path.join(LEDGER_DIR, "%s.tsv" % session)
    if not os.path.exists(path):
        return [], skip
    out, total = [], 0
    with open(path, errors="replace") as fh:
        for i, line in enumerate(fh):
            total = i + 1
            if i < skip or not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 4:
                continue
            ts, cls, code, cmd = parse_ts(parts[0]), parts[1], parts[2], parts[3]
            out.append((ts, "run", "%s %s (exit %s)" % (cls, squash(cmd, 100), code)))
    return out, total


def header_lines(meta, session):
    # The ticket hides in whichever of branch / title / worktree path the session used.
    ticket = ""
    for hay in [meta.get("branch"), meta.get("title")] + sorted(meta.get("seen") or []):
        m = TICKET_RE.search(hay or "") if TICKET_RE else None
        if m:
            ticket = m.group(0).upper()
            break
    cwd = meta.get("cwd") or ""
    return [
        "# %s" % (squash(meta.get("title"), 200) or "(untitled session)"),
        "session: %s" % session,
        "project: %s" % (cwd.replace(os.path.expanduser("~"), "~", 1) if cwd else "?"),
        "branch:  %s" % (meta.get("branch") or "-"),
        "ticket:  %s" % (ticket or "-"),
        "",
    ]


def write_log(path, meta, session, entries):
    head = header_lines(meta, session)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write("\n".join(head) + "\n")
    else:
        with open(path) as fh:
            existing = fh.read().split("\n")
        # Rewritten only when the title or branch moved; the body is never touched.
        if existing[:5] != head[:5] and len(existing) >= 5:
            with open(path, "w") as fh:
                fh.write("\n".join(head[:5] + existing[5:]))
    if not entries:
        return
    # A lost or reset .mark re-derives the session, which without this dedup doubles every entry.
    try:
        with open(path, errors="replace") as fh:
            already = Counter(ln.rstrip("\n") for ln in fh if ln.startswith("- "))
    except OSError:
        already = Counter()
    with open(path, "a") as fh:
        for ts, kind, text in entries:
            line = "- %s %s · %s" % (local_hhmm(ts), kind, text)
            # Counted, not a set: two real events can render identically inside one minute.
            if already[line]:
                already[line] -= 1
                continue
            fh.write(line + "\n")


def last_state(path):
    """(turns_since, minutes_since) for the newest `state` entry; (None, None) if never."""
    if not os.path.exists(path):
        return None, None
    turns, stamp = 0, None
    with open(path, errors="replace") as fh:
        lines = [ln for ln in fh if ln.startswith("- ")]
    for line in reversed(lines):
        parts = line[2:].split(" ", 2)
        if len(parts) >= 2 and parts[1] == "state":
            stamp = parts[0]
            break
        turns += 1
    if stamp is None:
        return None, None
    now = datetime.now(LOCAL_TZ) if LOCAL_TZ else datetime.now()
    try:
        hh, mm = (int(x) for x in stamp.split(":"))
    except ValueError:
        return turns, None
    # A state line carries HH:MM and no date, so its age is only derivable inside the log's
    # own day. A session resumed across days keeps writing into day one's file, where the
    # same stamp could be minutes or days old — report unknown and let `turns` decide.
    if os.path.basename(os.path.dirname(path)) != now.strftime("%Y-%m-%d"):
        return turns, None
    mins = (now.hour * 60 + now.minute) - (hh * 60 + mm)
    return turns, mins if mins >= 0 else mins + 1440


def run(transcript, session, sessions_dir=SESSIONS_DIR, force_offsets=None):
    mark_meta = {"records": 0, "ledger": 0, "pending": [], "header": {}, "path": None}
    mark_path = None
    if force_offsets is None:
        for day in sorted(os.listdir(sessions_dir)) if os.path.isdir(sessions_dir) else []:
            cand = os.path.join(sessions_dir, day, "%s.mark" % session)
            if os.path.exists(cand):
                mark_path = cand
                try:
                    with open(cand) as fh:
                        mark_meta.update(json.load(fh))
                except Exception:
                    pass
                break
    else:
        mark_meta.update(force_offsets)

    records, total = read_records(transcript, mark_meta["records"])
    cached = mark_meta.get("header") or {}
    meta = {"asks": 0, "title": cached.get("title"), "branch": cached.get("branch"),
            "cwd": cached.get("cwd"), "seen": set(cached.get("seen") or []),
            "last_edit": cached.get("last_edit")}

    pending = list(mark_meta.get("pending") or [])
    seen_prs = set(mark_meta.get("prs") or [])
    entries = derive_entries(records, meta, pending, seen_prs, cached.get("last_edit"))
    led, led_total = derive_ledger(session, mark_meta["ledger"])
    entries.extend(led)
    entries.sort(key=lambda e: e[0] or datetime.min.replace(tzinfo=timezone.utc))

    first_ts = None
    for rec in records:
        first_ts = parse_ts(rec.get("timestamp"))
        if first_ts:
            break
    day = local_date(first_ts) if mark_path is None else os.path.basename(os.path.dirname(mark_path))
    log_path = mark_path[:-5] + ".md" if mark_path else os.path.join(sessions_dir, day, "%s.md" % session)

    write_log(log_path, meta, session, entries)
    # Written on every path: force_offsets chooses where a pass STARTS, never whether the next one can resume.
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path[:-3] + ".mark", "w") as fh:
        json.dump({"records": total, "ledger": led_total, "pending": pending,
                   "prs": sorted(seen_prs),
                   "header": {"title": meta["title"], "branch": meta["branch"],
                              "cwd": meta["cwd"], "seen": sorted(meta["seen"]),
                              "last_edit": meta.get("last_edit")}}, fh)

    turns, mins = last_state(log_path)
    with open(log_path, errors="replace") as fh:
        asks_total = sum(1 for ln in fh if ln.startswith("- ") and " ask " in ln[:16])
    return {"path": log_path, "appended": len(entries), "records": total,
            "asks_total": asks_total, "state_turns": turns, "state_mins": mins}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--transcript", required=True)
    ap.add_argument("--session", required=True)
    ap.add_argument("--sessions-dir", default=SESSIONS_DIR)
    ap.add_argument("--from-scratch", action="store_true",
                    help="ignore any resume mark and re-read the transcript from line 0")
    args = ap.parse_args()
    offsets = {"records": 0, "ledger": 0} if args.from_scratch else None
    print(json.dumps(run(args.transcript, args.session, args.sessions_dir, offsets)))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # a logger must never be able to wedge a yield
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        sys.exit(0)
