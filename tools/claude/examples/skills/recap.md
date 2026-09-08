---
name: recap
description: Render the state of the work in front of you — this thread, or a handoff file you were just pointed at — as a short goal/state/done/open/next brief that ends the turn. Use for "recap", "recap session", "recap and status", "recap, goal vs current state", and for "read <handoff-file> and recap + what's next". Distinct from /sessions, which queries the session-log corpus for what OTHER or PAST sessions did; this one renders the state of the current work and stops. Usage - /recap [path to a handoff file]
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(python3 *), Bash(ls *), Bash(cat *), Bash(grep *), Bash(gh pr view *), Bash(gh pr list *), Bash(gh run list *), Bash(gh run view *), Bash(git status*), Bash(git log *), Bash(git branch *), Bash(jq *)
argument-hint: "[path-to-handoff-file]"
---

# recap

A recap is a **rendering**, not an investigation. It reports state the reader can act on in one screen, then ends the turn.

## Pick the source

| The ask | Source |
|---|---|
| `read <path> and recap` / `…and what's next` | that file — Read it first, in full |
| `recap` / `recap session` / `recap and status` | this conversation |
| the thread has no state (post-compact, cold start) | `/sessions show <id>`, and say the log is the source |
| "what did *another* session do" | not this skill — `/sessions` |

If a handoff path is named, the file is authoritative for *intent* and stale for *state*.

## The shape

Five sections, in this order, nothing else:

```text
**Goal** — one line: what this work set out to do.
**Where we are** — current state against that goal. One or two lines.
**Done** — bullets. What landed.
**Open** — decisions you owe me, blockers, unanswered questions.
**Next** — the one concrete next action.
```

Drop a section only when it is genuinely empty, and say so in a word (`Open — none`) rather than deleting the heading. Never invent a sixth section.

## The contract

- **Short.** A recap is read to re-orient, not to re-live. If it does not fit one screen it has failed — cut prose, not sections.
- **Done means done.** Summarize what landed; do not re-argue it, re-justify it, or narrate how it was reached.
- **Ticket numbers, PR numbers and file paths only when load-bearing.** An identifier the reader would act on stays; an identifier that is provenance is noise.
- **Fix stale facts, do not report them.** Finding that the handoff file or an earlier claim is wrong is not a recap item — correct it, then recap the corrected state, and say in one line that you corrected it.
- **Open items are the highest-signal part.** Set them apart visually. Each one names the specific decision owed — never "blocked on you" with nothing to decide. An item resolved earlier in the session is not open; re-read before listing it.
- **No advice about how to read the recap.** No "see section C", no "you may want to".

## Verify before asserting

A recap states facts about the world, so it carries the same evidence bar as anything else. Fetch, do not recall:

- **PR / CI / ticket state** — `gh pr view`, `gh run list` at recap time. A status remembered from earlier in the session is stale by default, and a large share of these asks is explicitly about PR status or mergeability.
- **Branch and worktree** — `git status`, `git branch --show-current`.
- **`dropped` entries** when the session log is the source — each is something the user typed and never got an answer to. They belong under **Open**.

## End the turn

A recap is terminal. Stop after **Next** — do not start it, do not ask a follow-up question underneath it, and do not treat the recap as an implicit go-ahead. Many of these asks say so outright ("wait for approval", "don't auto-resume", "pause"); the rest mean it.

If the same turn also carries an explicit pause, emit your full handoff packet instead — this shape is the summary, not the handoff.
