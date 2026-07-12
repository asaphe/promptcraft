# Self-Paced Loops (dynamic wakeup scheduling)

How to pick the next check-in delay for an open-ended recurring task when nobody gave you a fixed interval.

Fixed-interval scheduling (cron-style) fits known cadences. This doc covers the other case: a loop where the agent decides, on every wake, when to wake next — babysitting a deploy, watching a review queue, an autonomous improvement loop. The primitive is a scheduled-wakeup call carrying the delay, the prompt to re-fire, and a one-line reason. The judgment is entirely in the delay.

The token economics are covered in [`claude-best-practices.md`](../../guides/claude-best-practices.md) (waiting hierarchy, prompt-cache TTL, never poll via shell loops); this doc is the delay-selection layer on top.

## Pick the delay from what you're actually waiting for

| Situation | Delay | Why |
|---|---|---|
| Polling external state the harness can't notify you about (CI run, deploy, remote queue) | Match the state's real rate of change | A job that takes ~8 min deserves one ~8-min check, not eight 1-min checks — same information, 1/8th the context re-reads |
| Something else is the primary wake signal (background-task notification, event monitor) | Long fallback heartbeat, 20–30 min | The heartbeat is a safety net for a hung or lost notification, not the detection mechanism |
| Idle tick — loop alive, nothing specific to watch | 20–30 min default | The user can always interrupt sooner; quiet wakes should be rare and cheap |

Two corollaries:

- **Never schedule a wake just to keep the prompt cache warm.** If there is nothing to check, the wake is pure spend. Cache-expiry math never justifies a wakeup on its own.
- **Never poll for work the harness already tracks.** Background tasks and dispatched agents re-invoke you on completion — a wakeup that asks "is it done yet?" duplicates a notification you were going to get for free. Schedule only the long fallback.

## Every wake states its reason

The scheduling call carries a one-line reason shown to the user. Make it specific — "watching CI run on PR" beats "waiting". The user reads this line to understand the loop's cadence without having to reverse-engineer it, and you re-read it on wake to remember why you're here.

## End the loop deliberately

A self-paced loop has no natural terminator — it ends when you stop scheduling. On every wake, first ask whether the loop's objective is met or moot (deploy landed, queue empty, user said stop). If so, end it explicitly and say so; a loop that quietly keeps ticking after its purpose expired is the recurring-task version of a leaked resource.
