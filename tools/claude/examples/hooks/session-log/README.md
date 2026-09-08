# Session Log

A **Stop** hook that appends what each turn did to a per-session markdown file, plus a reader for querying those files later. It answers *"what did that session actually do, and where did it stop?"* without reconstructing anything from transcripts.

Three files, and they are separable:

| File | Role |
|---|---|
| `session-log.sh` | The Stop hook. Derives the turn's entries, prunes old logs, nudges when the log has no recent `state` line. |
| `session-log-derive.py` | Transcript → log entries. Also runnable by hand, which is how you backfill. |
| `sessions.py` | The reader: `list`, `show`, `grep` over the logs. Install this alone if you only want to read logs someone else's tooling writes. |

## Why a log and not the transcript

The transcript is a complete record and an unusable one — it is enormous, it is per-session, and finding "where did we stop on X" in it means reading it. The log is the derived subset that answers that question: one line per meaningful event, one file per session, grep-able.

Two properties do most of the work:

- **The index is derived, never stored.** One file per session is the only shape that survives many parallel Claude Code sessions without write contention. `sessions.py list` scans the directory at read time; a stored index would only add a second source of truth to drift.
- **Half the content is written by the model, not the hook.** The hook records what mechanically *happened* (files edited, agents dispatched, PRs opened). What was *decided* is not derivable from a transcript, so Claude appends `state` lines itself. The hook's only role there is noticing when the newest `state` line has gone stale and saying so.

## Log format

`$SESSION_LOG_DIR/<date>/<session-id>.md`:

```text
# Refactor the ingest pipeline
session: 0f9c1a2b-...
project: ~/code/example
branch:  feat/ingest-retry
ticket:  PROJ-412

- 09:14 ask · refactor the retry path so a 429 backs off instead of failing the batch
- 09:16 edit · src/ingest/retry.py, src/ingest/__init__.py
- 09:22 run · test pytest tests/ingest -q (exit 0)
- 09:31 agent · planner — sequence the retry rollout
- 09:40 state · objective: 429 backoff | decided: token bucket, not sleep | open: none | next: PR
- 09:44 pr · #218 example/repo — https://github.com/example/repo/pull/218
- 10:02 dropped · never answered: also check whether the DLQ replays these
```

Alongside each `.md` sits a `.mark` file holding the resume offsets, so the next run reads only the new transcript lines.

### Entry kinds

| Kind | Written by | Meaning |
|---|---|---|
| `ask` | hook | A prompt the human actually typed |
| `edit` | hook | Files written this turn, deduped against the previous turn |
| `run` | hook | A meaningful command, joined from the optional action ledger |
| `pr` | hook | A PR opened from this session |
| `agent` | hook | A subagent dispatched |
| `note` | hook | Other tool activity worth a line |
| `dropped` | hook | A prompt submitted and never answered |
| `state` | Claude | objective / decided / open / next |

**`dropped` is the highest-signal kind in the file.** Each one is something the human typed that never became a turn — a prompt removed from the queue, or one still queued long after it was submitted. Nothing else in Claude Code surfaces these, and they are exactly what "where did we stop" is asking about.

**`state` is the only kind that records a decision.** A derived log records what happened, never what was concluded. If a session has no `state` line, say so when reading it rather than inferring intent from the mechanical entries.

## Install

Register the Stop hook in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/session-log.sh"
          }
        ]
      }
    ]
  }
}
```

`session-log.sh` finds `session-log-derive.py` beside itself and `_lib/hook-diag.sh` one directory up, so keep the layout of this repo when copying — or edit the two paths at the top of the script.

The hook never blocks and never writes to stderr on a non-zero exit. Both are deliberate: a Stop hook that forces narration pushes the session's real answer above the fold, and a logger that can wedge a yield is worse than no logger.

## Reading the logs

```bash
python3 sessions.py list  --days 14 [--project example] [--ticket PROJ-412]
python3 sessions.py show  <ticket | session-id-prefix | YYYY-MM-DD | title fragment>
python3 sessions.py grep  <regex> [--days 30]
```

`list` groups by `(day, project, branch, ticket)`, so a session resumed under a new id reads as one row rather than two, and prints the newest `state` line per group.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `SESSION_LOG_DIR` | `~/.claude/session-logs` | Where logs are written and read. Read by all three files. |
| `SESSION_LOG_TZ` | machine local zone | Rendering timezone for entry times, e.g. `UTC`. Set it when logs are read somewhere other than where they were written. |
| `SESSION_LOG_TICKET_RE` | `[A-Za-z]{2,10}-\d{1,6}` | Your tracker's key format. Matched against branch, title, and every cwd the session saw — the ticket hides in whichever of those the session used. |
| `SESSION_LOG_RETENTION_DAYS` | `90` | Age at which a date directory is pruned. |
| `SESSION_LOG_LEDGER_DIR` | `~/.claude/local/action-ledger` | Optional; see below. |

## Optional — the action ledger

`run` entries are a **join**, not a second classifier. If `$SESSION_LOG_LEDGER_DIR/<session-id>.tsv` exists, each line is read as four tab-separated fields and rendered as a `run` entry:

```text
<ISO-8601 timestamp>\t<class>\t<exit code>\t<command>
```

Nothing in this repo writes that file — supply it from whatever already classifies your commands (a `PostToolUse` hook, a shell wrapper), or leave it absent. When the file is missing, `derive_ledger` returns nothing and the rest of the log is unaffected: there are simply no `run` lines.

Classifying commands here instead would mean a second, divergent classifier, which is the thing to avoid — two classifiers disagreeing about whether a command mattered is worse than one classifier and a missing column.

## Retention

The hook prunes date directories older than `SESSION_LOG_RETENTION_DAYS` once per session, keyed on a `.pruned` marker beside the log rather than on a date check — a date check silently never fires on a machine that is not awake at the right moment.

The `rm` runs unattended, so it is fenced twice: `$SESSION_LOG_DIR` must end in `session-logs`, and only directories matching `20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]` are removed. Claude Code's own `~/.claude/sessions` registry sits one directory over, and an unfenced sweep would be pointed straight at it.

## Backfill

The derive script runs standalone against any transcript:

```bash
python3 session-log-derive.py \
  --transcript ~/.claude/projects/<project>/<session-id>.jsonl \
  --session <session-id> --from-scratch
```

`--from-scratch` ignores any resume mark and re-reads from line 0. That is safe to repeat: `write_log` dedups against the lines already in the file, so a re-derive of a session that already has a log adds nothing. The mark is rewritten on every path, backfill included — a backfilled log with no mark makes the next live Stop re-derive the whole transcript.

## Companion skills

- [`skills/sessions.md`](../../skills/sessions.md) — query the corpus for what past or other sessions did.
- [`skills/recap.md`](../../skills/recap.md) — render the current thread's state; falls back to `sessions show` when the thread has no state to render.
