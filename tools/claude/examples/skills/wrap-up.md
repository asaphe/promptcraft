---
name: wrap-up
topic: Meta / self-improvement
description: >-
  Capture phase of the learning loop. At session end, scan the conversation for
  friction and learnings the passive Stop-hook regex misses (silent wrong-guesses,
  re-prompt loops, tool/config mismatches, ad-hoc scripts worth promoting) and
  write model-curated candidates to /tmp/claude-wrapup-<id>.jsonl for /learn to
  codify later. Capture only — never codifies, never edits CLAUDE.md/skills/hooks.
  Context-aware: degrades to write-only when tokens are scarce. Usage -
  /wrap-up | /wrap-up --emergency | /wrap-up --quick
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(jq *), Bash(wc *), Bash(grep *), Bash(ls *), Bash(cat *), Bash(date *), Bash(git -C *), Bash(git log *), Bash(git rev-parse *), Bash(gh pr view *), Write, AskUserQuestion
argument-hint: "(no args = full) | --quick | --emergency"
---

# Wrap-up — capture the loop before the session dies

You are the **capture phase** of the learning loop. `/learn` is the apply phase. Your job is to scan *this* conversation for what should be codified and write it to a candidate file that survives `/clear`, `/compact`, and token exhaustion — so the learning isn't lost when the session ends. You do **not** codify. You do **not** edit CLAUDE.md, skills, hooks, or docs. You write candidates and stop.

## Why this exists (don't duplicate the hook)

The Stop hook `learn-suggest.sh` already writes `/tmp/claude-pending-learn-<id>.jsonl` passively — but it only greps the *user's* text for correction patterns and tool-failure rate. It is blind to friction that left no scolding quote: a wrong guess you self-corrected, a re-prompt loop, a tool chosen where another was right, an ad-hoc command debugged across three tries. **Your added value is judgment** — you read the actual exchange and name the friction the regex can't see, with a root-cause hypothesis and a proposed destination that pre-fill `/learn`'s steps 2 and 6.

## Mode resolution (do this first)

| Trigger | Mode | Behavior |
|---|---|---|
| `--emergency`, or context-pressure system-reminders indicate near-exhaustion | `emergency` | Write candidates only. No ranking, no summary, no offer. One jq pass, then stop. |
| `--quick`, or approaching `/compact` | `quick` | Write + a one-line summary of what was captured. No offer to chain. |
| no args, healthy budget | `proactive` | Write + present candidates ranked by severity + tell the user to run `/learn` (which auto-finds the file). |

You cannot read your own token budget directly. Self-assess from any context-window pressure reminders present; default to `proactive` when unsure, but if the conversation is clearly long and near a limit, prefer `quick` — a written candidate is the whole point; a pretty summary that never gets written is failure.

## Active work comes first

If meaningful in-progress work exists (uncommitted changes, open PR mid-review, a half-applied plan), surface it in one line — but **do not build the new-session handoff prompt here.** That is governed by your existing handoff protocol in CLAUDE.md (the self-contained prompt with ticket + live-state + next steps). Point to it; don't reproduce it. Wrap-up is about learnings, not project state.

## Scanning for learnings

Read this session's exchange and look for these signals. Each maps to a proposed `scope` tag that pre-fills `/learn`'s routing (step 6):

| Signal | Proposed scope |
|---|---|
| Re-prompt loop on a standing instruction (you had to be told twice) | `[CLAUDE.md]` — a behavioral rule didn't fire or doesn't exist |
| Repeated corrections on the same topic | `[SKILL:<name>]` or `[CLAUDE.md]` — principle/procedure gap |
| You guessed/assumed and were wrong (even if self-caught, no user scold) | `[CLAUDE.md]` or `[DOC]` — verify-don't-assume gap |
| Tool failure or unexpected output | `[HOOK]` or config mismatch |
| Ad-hoc command debugged in-session, re-invoked, or solving a recurring chore | `[SCRIPT]` — capture iteration history, failed versions, discovered edge cases (not just the final working line) |
| Wrong tool chosen (Bash where a skill/Edit existed, raw `gh api` where a skill fits) | `[SKILL:<name>]` or `[CLAUDE.md]` |
| Cross-session operational fact learned (a path, an API quirk, an account id) | `[DOC]` → `~/.claude/docs/<topic>.md` |

**Capture backlog only.** Resolved work is excluded unless the *outcome itself* is a reusable learning. One signal = one candidate. Do not pre-judge generalizability — `/learn` step 3 owns the one-off filter. Your bar is "is this friction real," not "is this rule-worthy."

**Scope tags are proposals, not decisions.** You never write to any of these destinations. `/learn` applies its own routing + refusal rules (org-vs-personal, memory-guard, anti-bloat). A `[SCRIPT]` tag in your file is a hint, not a commitment.

## Candidate file format

Write to `/tmp/claude-wrapup-<session_id>.jsonl` (distinct from the hook's `claude-pending-learn-<id>.jsonl` — the Stop hook truncates that path at session end and would clobber you). Get the session id from the current session's jsonl filename under `~/.claude/projects/*/`.

First line is a session-metadata header; each subsequent line is one candidate:

```jsonl
{"header": true, "session_id": "<id>", "timestamp": "<iso8601>", "repo": "<name|->", "branch": "<branch|->", "commit": "<sha|->", "ticket": "<TICKET-###|->", "pr": "<#|->"}
{"quote": "<verbatim user signal, OR your one-line description if model-observed>", "why": "<one-line root-cause hypothesis>", "scope": "[CLAUDE.md]|[SKILL:x]|[HOOK]|[SCRIPT]|[DOC]|[ADR]|[MEMORY]", "severity": "critical|high|medium|low", "source": "<session jsonl path:line | model-observed>", "session_id": "<id>", "timestamp": "<iso8601>"}
```

Field rules:

- `quote` — verbatim when user-originated (no paraphrase); for model-observed friction, a crisp one-line description.
- `why` — your root-cause hypothesis. This pre-fills `/learn` step 2; if you can't state one, the signal is probably noise — drop it.
- `severity` — drives `/learn`'s ranked presentation. A re-prompt on a safety/destructive rule is `critical`; a stylistic nit is `low`.
- The `quote`/`session_id`/`timestamp` keys are a **superset** of the hook's format, so `/learn` reads this file with no change to its existing reader; `why`/`scope`/`severity`/`source` are extra fields it can use when present.

For `[SCRIPT]` candidates, put the iteration history in `why` (or an extra `notes` field): what the first version got wrong, what edge case forced the fix, why the final form works. The debugging path is the learning — not just the command.

## Closing behavior by mode

- **emergency** — after writing, emit only: `wrapped: N candidate(s) → /tmp/claude-wrapup-<id>.jsonl`. Stop.
- **quick** — the above plus a one-line-per-candidate list (severity + quote). Stop.
- **proactive** — present candidates as a severity-ranked list, then:

  ```text
  N candidate(s) captured → /tmp/claude-wrapup-<id>.jsonl
  Run /learn to codify (it will pick up this file). One incident per /learn run.
  ```

  Do **not** auto-invoke `/learn` or codify anything yourself. The user paces codification; `/learn` enforces one-incident-per-run, principle-not-rule, and anti-bloat.

If zero real candidates: write nothing, emit `wrap-up: no learnings worth capturing this session.` Do not create an empty file.

## Hard boundaries

- Capture only. No edits to CLAUDE.md, skills, agents, hooks, docs, or repo files. No `git`/`gh` writes. No PR creation.
- Never write to `~/.claude/projects/*/memory/` (blocked by `memory-guard.sh`) — and you have no reason to; your output goes to `/tmp`.
- Never decide a destination — only propose a `scope` tag. Routing + refusal rules live in `/learn`.
- Do not reproduce the new-session handoff prompt; that's your separate protocol.
