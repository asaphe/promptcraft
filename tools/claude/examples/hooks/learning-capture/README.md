# Learning Capture — retired from this repo

These three hooks are no longer maintained as examples here. The pattern ships as a Claude
Code plugin: **[claude-learning-loop](https://github.com/asaphe/claude-learning-loop)**.

```text
/plugin marketplace add asaphe/claude-learning-loop
/plugin install learning-loop@claude-learning-loop
```

## What replaced it

The example's architecture was three hooks doing all the work: `SessionStart` injected
pending candidates, `SessionEnd` and `PreCompact` regex-scanned the transcript for
correction phrases and appended to `pending-learnings.md`. Regex alone over-captured
(any message starting with "no") and under-captured (a silent wrong guess the user
worked around produces no correction phrase at all).

The plugin keeps a thin passive layer — a `Stop` hook that suggests capture and a
`PreCompact` reminder — and moves the judgment into three skills:

| Skill | Phase |
|---|---|
| `/learning-loop:wrap-up` | Capture — model-curated scan of the conversation for friction the regex misses |
| `/learning-loop:eval` | Quality gate — scores each candidate for destination fit, recurrence, coverage, severity |
| `/learning-loop:learn` | Codify — writes the surviving candidates as principles, per a destinations manifest |

The classification step this example described (team-wide / agent-specific / personal) is
`/learning-loop:eval`, and the target is configured per-user in
`examples/learn-destinations.example.md` rather than hardcoded in the hook.
