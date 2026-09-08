#!/usr/bin/env python3
"""Read the session logs written by session-log.sh.

The index is derived here rather than stored anywhere: one file per session is the
only shape that survives many parallel sessions without write contention, and a
directory scan is fast enough that a second source of truth would only add drift.

See README.md in this directory for the log format and the entry kinds.
"""
import argparse
import os
import re
from datetime import datetime, timedelta

SESSIONS_DIR = os.environ.get("SESSION_LOG_DIR", os.path.expanduser("~/.claude/session-logs"))
ENTRY_RE = re.compile(r"^- (\d\d:\d\d) (\w+) · (.*)$")
KINDS = ("ask", "edit", "run", "pr", "agent", "state", "dropped", "note")


def load(days=None):
    out = []
    if not os.path.isdir(SESSIONS_DIR):
        return out
    cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d") if days else None
    for day in sorted(os.listdir(SESSIONS_DIR), reverse=True):
        if not re.match(r"^\d{4}-\d\d-\d\d$", day) or (cutoff and day < cutoff):
            continue
        ddir = os.path.join(SESSIONS_DIR, day)
        for name in sorted(os.listdir(ddir)):
            if not name.endswith(".md"):
                continue
            path = os.path.join(ddir, name)
            head, entries = {}, []
            try:
                with open(path, errors="replace") as fh:
                    for i, line in enumerate(fh):
                        line = line.rstrip("\n")
                        if i == 0 and line.startswith("# "):
                            head["title"] = line[2:]
                        elif ":" in line and i < 5 and not line.startswith("- "):
                            k, _, v = line.partition(":")
                            head[k.strip()] = v.strip()
                        m = ENTRY_RE.match(line)
                        if m:
                            entries.append((m.group(1), m.group(2), m.group(3)))
            except OSError:
                continue
            # The hook's derived batch and hand-written state lines append independently.
            entries.sort(key=lambda e: e[0])
            head.update(day=day, path=path, entries=entries,
                        session=name[:-3], project=head.get("project", "?"),
                        ticket=head.get("ticket", "-"), branch=head.get("branch", "-"))
            out.append(head)
    return out


def group_key(s):
    """A forked resume (new session id, same work) must read as one row, not two."""
    return (s["day"], s["project"], s["branch"], s["ticket"])


def last_state(s):
    """(HH:MM, text) of the newest state entry in one session, or None."""
    for stamp, kind, text in reversed(s["entries"]):
        if kind == "state":
            return (stamp, text)
    return None


def newest_state(members):
    """Newest state line across a group. Members are UUID-named, so file order is not time order."""
    found = [st for st in (last_state(m) for m in members) if st]
    return max(found)[1] if found else ""


def counts(entries):
    c = {}
    for _, kind, _ in entries:
        c[kind] = c.get(kind, 0) + 1
    return " ".join("%s:%d" % (k, c[k]) for k in KINDS if k in c)


def cmd_list(args):
    sessions = load(args.days)
    groups = {}
    for s in sessions:
        groups.setdefault(group_key(s), []).append(s)
    rows = 0
    for key in sorted(groups, reverse=True):
        members = groups[key]
        if args.project and args.project.lower() not in key[1].lower():
            continue
        if args.ticket and args.ticket.upper() != key[3].upper():
            continue
        entries = [e for m in members for e in m["entries"]]
        title = members[0].get("title", "(untitled)")
        state = newest_state(members)
        span = "%s-%s" % (entries[0][0], entries[-1][0]) if entries else "--:--"
        print("%s  %s  %-11s %s" % (key[0], span, key[3], title))
        print("        %s%s" % (key[1], "" if key[2] in ("-", "") else "  (%s)" % key[2]))
        print("        %s%s" % (counts(entries),
                                "" if len(members) == 1 else "  [%d sessions]" % len(members)))
        if state:
            print("        state: %s" % state[:150])
        print()
        rows += 1
    if not rows:
        print("no sessions%s" % (" in the last %d days" % args.days if args.days else ""))


def cmd_show(args):
    sessions = load(None)
    target = args.target
    hits = [s for s in sessions
            if target.lower() in (s["ticket"] or "").lower()
            or s["session"].startswith(target)
            or s["day"] == target
            or target.lower() in (s.get("title") or "").lower()]
    if not hits:
        print("no session matching %r" % target)
        return
    for s in hits:
        print("=" * 78)
        print("%s   %s" % (s["day"], s.get("title", "")))
        print("%s  %s  %s" % (s["project"], s["branch"], s["ticket"]))
        print("=" * 78)
        for t, kind, text in s["entries"]:
            print("  %s  %-8s %s" % (t, kind, text))
        print()


def cmd_grep(args):
    pat = re.compile(args.pattern, re.I)
    for s in load(args.days):
        matched = [(t, k, x) for t, k, x in s["entries"] if pat.search(x)]
        if not matched:
            continue
        print("%s  %s  %s" % (s["day"], s["ticket"], s.get("title", "")))
        for t, k, x in matched:
            print("    %s %-8s %s" % (t, k, x[:160]))
        print("    -> %s" % s["path"])
        print()


def main():
    ap = argparse.ArgumentParser(description="read Claude Code session logs")
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("list")
    p.add_argument("--days", type=int, default=14)
    p.add_argument("--project")
    p.add_argument("--ticket")
    p.set_defaults(fn=cmd_list)
    p = sub.add_parser("show")
    p.add_argument("target")
    p.set_defaults(fn=cmd_show)
    p = sub.add_parser("grep")
    p.add_argument("pattern")
    p.add_argument("--days", type=int, default=30)
    p.set_defaults(fn=cmd_grep)
    args = ap.parse_args()
    if not args.cmd:
        ap.print_help()
        return
    args.fn(args)


if __name__ == "__main__":
    main()
