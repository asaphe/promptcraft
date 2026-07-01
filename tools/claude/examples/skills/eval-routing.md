---
name: eval-routing
description: Measure whether the current skill catalog's descriptions let a fresh, context-free router pick the right skill for a prompt. Code-graded by exact/set match; routing decisions made by cheap Haiku subagents. Use to catch ambiguous or overlapping skill descriptions. Usage - /eval-routing [cases-file] [--only skill]
user-invocable: true
allowed-tools: Bash(python3 *), Bash(mkdir -p /tmp/*), Bash(rtk proxy python3 *), Read, Write, Task
argument-hint: "[cases-file] [--only skill]"
---

# eval-routing

A self-contained routing eval for the skill catalog. Given `{prompt, expected}` cases,
it asks a **fresh Haiku subagent** (no session context → no contamination) which single
skill it would invoke for each prompt, then **code-grades** the answer by exact/set match.

> This skill ships with helper scripts (a catalog builder, a deterministic grader, a
> headless runner) and a cases file. They are described generically below — adapt the
> paths to wherever you keep them alongside your own copy of the skill.

## What this measures — and what it does NOT

- **Measures:** *routability from descriptions*. Can a model, seeing only the skill catalog
  (name + `description` frontmatter) and a user prompt, pick the intended skill? Misroutes
  point at **ambiguous or overlapping descriptions** — the one actionable lever you control.
- **Does NOT measure:** the exact production routing path. Real routing is also shaped by any
  intent-injection hook on `UserPromptSubmit` and full session context. This is a faithful
  proxy for description quality, not a replica of the live router. Don't over-read a passing
  score.

Grading is pure code — deterministic, free, reproducible across runs. Only the
routing *decision* uses a model, and it uses Haiku for cost.

## Steps

### 1. Parse arguments

- `[cases-file]` — path to a JSONL case file. Default: the bundled routing cases file.
- `[--only skill]` — optional: run only cases whose `expected` (or `acceptable`) is this skill.

Case schema (one JSON object per line):

```json
{"prompt": "...", "expected": "skill-name-or-none", "acceptable": ["alt-skill"]}
```

`acceptable` is optional — use it when more than one skill is a legitimate route.

### 2. Build the live catalog

Rebuild from installed `SKILL.md` frontmatter so it never drifts. Run the bundled
catalog-builder script, which emits the catalog as markdown:

```bash
RUN=/tmp/eval-routing-$$; mkdir -p "$RUN"
python3 "<skill-dir>/build_catalog.py" md | tee "$RUN/catalog.md"
```

The catalog is the exact context the router agents get. Read it — if a skill you're testing
isn't in it, the skill isn't installed and the case will (correctly) fail.

### 3. Dispatch one router subagent per case — IN PARALLEL

Send **all** `Task` calls in a **single message** so they run concurrently. Each router agent:

- `subagent_type: general-purpose`, `model: haiku` (cheap; the decision is pure reasoning)
- gets the catalog + one prompt, and this exact instruction:

> You are a skill router. Below is a catalog of available skills (name: description) and a
> user prompt. Decide which SINGLE skill should be invoked for this prompt, or `none` if no
> skill fits. Judge only from the catalog — do not invent skills. Output ONLY a JSON object
> on one line: `{"chosen": "<skill-name-or-none>"}`. No prose, no code fences.
>
> CATALOG:
> <paste catalog.md>
>
> PROMPT:
> <the case prompt>

Collect each agent's `{"chosen": ...}` and append `{"prompt": ..., "chosen": ...}` to
`$RUN/results.jsonl` (one line per case). Write it with the Write tool.

### 4. Grade (code, deterministic)

Run the bundled grading script against the cases file and the results:

```bash
python3 "<skill-dir>/grade.py" "<cases-file>" "$RUN/results.jsonl"
```

It prints a per-case PASS/MISS table, overall accuracy, and a misroute list. Exit code is
non-zero if any case missed (useful if this is ever wired into CI).

### 5. Report

Give the user: overall accuracy, the table, and for each **misroute** a one-line hypothesis —
almost always "description for X overlaps Y" or "description too vague to disambiguate from Z".
Misroutes are the deliverable: they name the exact skill descriptions worth rewriting. Do NOT
edit any skill descriptions automatically — surface them and let the user decide.

## Adding cases

Append lines to the cases file. Good cases to grow coverage:

- **Negatives** (`expected: none`) — prompts that should NOT trigger any skill (catches over-eager routing).
- **Near-collisions** — prompts that plausibly fit two skills; encode the fair set via `acceptable`.
- **Real misroutes** — when you notice the live router pick wrong, add that prompt here so a fix is measurable.

## Headless / CI

A bundled headless runner does the same routing measurement, but every decision is a
`claude -p` subprocess instead of an interactive `Task` — so the whole loop scripts and can
gate a PR on accuracy:

```bash
python3 "<skill-dir>/run_headless.py" [cases-file] [--only skill] \
  [--model haiku] [--concurrency 6] [--retries 4]
```

Exit code: `0` clean pass · `1` a real misroute (routing regression) · `2` a case
couldn't be evaluated (auth/timeout/unparseable) — an *infrastructure* error, never
conflated with a routing verdict, so a flake can't read as a regression.

**Auth caveat (load-bearing).** In CI set `ANTHROPIC_API_KEY` (or a `claude setup-token`
token). Run *inside* an interactive Claude Code session, the nested `claude -p` uses the
claude.ai OAuth credential, which **intermittently reports "Not logged in"** for
tens-of-seconds windows (the parent session's token refresh races the child's keychain
read — `claude auth status` still says logged-in throughout). `--retries` rides short
flaps; a plain terminal or an API key is the reliable path.

**Note on fidelity.** The headless router runs with an overridden `--system-prompt` and
`--tools ""` — a *cleaner* context-free router than the interactive `Task` path (which
inherits Claude Code's default system prompt). Expect occasional divergence: e.g. a
"remember that I prefer X" prompt might route to a learning skill interactively but `none`
headless, because that skill's description doesn't advertise "remember/prefer" phrasing.
Divergences are themselves description-quality signals.

Offline: set an environment variable pointing the runner at a stub command that emits the
`--output-format json` envelope, to exercise the orchestration/parse/grade path without
tokens or live auth.

## Behavior eval — v2

A companion runner grades an agent's *output*, not just its routing. Each case runs a
**target** (`claude -p` performs the task) then a **judge** (`claude -p` scores the output
against the rubric); the judge is model-graded, and a deterministic rubric-grader aggregates
its per-criterion verdicts.

```bash
python3 "<skill-dir>/run_behavior.py" [cases-file] \
  [--target-model haiku] [--judge-model sonnet]
```

Behavior case schema: `{"id","task","rubric":[{"criterion","required"}],"system"?}`.
A case passes iff every `required` criterion passes; optional criteria only move the score.
Same exit-code contract (`0`/`1`/`2`) and the same offline stub hook.
