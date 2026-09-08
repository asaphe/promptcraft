---
name: sessions
description: Query the session-log corpus for what OTHER or PAST Claude sessions did and where they stopped. Use for "what did we do last week", "which session touched PROJ-412", "what was left unanswered days ago". Distinct from /history-search, which greps prompt TEXT — this reads session STATE; and from /recap, which renders the state of the CURRENT thread rather than querying the corpus. Usage - /sessions [list|show|grep] [args]
user-invocable: true
allowed-tools: Bash(python3 *), Bash(ls *), Bash(cat *), Bash(grep *), Read
argument-hint: "[list|show <ticket|id|date>|grep <regex>]"
---

# sessions

Reads `$SESSION_LOG_DIR/<date>/<session-id>.md` (default `~/.claude/session-logs/`), written continuously by the [`session-log`](../hooks/session-log/) Stop hook for the derived facts, and by Claude at boundaries for the `state` entries.

**This skill requires that hook.** Without it there is no corpus, and the commands below print nothing. Say so rather than falling back to reconstructing from transcripts — that is `/history-search`'s job, and it answers a different question.

## When to use this instead of /history-search or /recap

| Ask | Skill |
|---|---|
| "what did we *do* about X", "where did *that* session stop" | **this** |
| "what did I *say* about X", find the wording of a past prompt | `/history-search` |
| "recap", "recap session", "read \<handoff\> and recap" — the work in front of you | `/recap` |

`/recap` renders the current thread's state; this queries the log for other sessions. When `/recap` has no thread state to render (post-compact, cold start) it calls `show` here for the source and says so. They read different corpora and neither subsumes the other. If the log has no entry for the period asked about, say so and offer `/history-search` — never silently substitute one corpus for the other.

## Commands

```bash
python3 <path-to>/sessions.py list  --days 14 [--project example] [--ticket PROJ-412]
python3 <path-to>/sessions.py show  <ticket | session-id-prefix | YYYY-MM-DD | title fragment>
python3 <path-to>/sessions.py grep  <regex> [--days 30]
```

Run the command verbatim rather than reconstructing the path from memory. A remembered path drifts from the documented one even when it was read correctly the first time.

## Entry types

`ask` typed prompt · `edit` files written · `run` meaningful command (joined from the optional action ledger) · `pr` PR opened · `agent` subagent dispatched · `state` Claude's objective / decided / open / next · `dropped` a prompt submitted but never answered · `note` other.

## Reading a log

- **"Where is it at?"** — the last `state` entry. If there is none, say so plainly rather than inferring state from the mechanical entries. A derived log records what happened, never what was decided.
- **`dropped` entries are the highest-signal lines in the file** — each is something the user typed and never got an answer to. Surface them whenever recapping, not only when asked.
- **The log is evidence of what happened, not authority on what is true now.** Verify live state (`gh pr view`, `git status`) before acting on anything it says. A PR the log records as open may have merged three days ago.

## Writing a state entry

Append one line — never rewrite the file. It is append-only and has a second writer (the hook), so a rewrite races it.

```text
- HH:MM state · objective: … | decided: … | open: … | next: …
```

Write one at a pause, before a compact, and when the hook's Stop nudge asks for it.
