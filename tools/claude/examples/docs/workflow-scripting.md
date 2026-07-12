# Workflow Scripting (deterministic multi-agent orchestration)

When multi-agent control flow matters — loops, fan-out, staged verification — author it as a small script with explicit primitives, not as a prompt that hopes the model orchestrates correctly.

Prompt-driven orchestration ("spawn five reviewers, then verify each finding") leaves loop bounds, concurrency, and error handling to the model's judgment on every run. A workflow script makes them deterministic: the script decides what fans out, what verifies, and what synthesizes; the agents only do the work. Claude Code exposes this as a workflow tool; if your harness lacks one, the same structure can be approximated with a driver script dispatching CLI executors (see [`multi-model-orchestration.md`](multi-model-orchestration.md)).

**This capability is consent-gated.** A workflow can spawn dozens of agents; invoke it only on explicit user opt-in, never because the task "would benefit from parallelism". See [`consent-gated-capabilities.md`](../../../../shared/principles/consent-gated-capabilities.md).

## The primitive vocabulary

| Primitive | What it does | When to reach for it |
|---|---|---|
| `agent(prompt, opts)` | Spawns one subagent; returns its final text, or a schema-validated object when `opts.schema` is set | Every unit of delegated work |
| `pipeline(items, stage1, stage2, …)` | Runs each item through all stages independently — **no barrier** between stages | Default for all multi-stage work |
| `parallel(thunks)` | Runs tasks concurrently and **awaits all** before returning (hard barrier) | Only when a later stage genuinely needs every prior result together |
| `phase(title)` / `log(msg)` | Group progress and narrate for the human watching the run | Every workflow — silent runs erode trust |
| `budget` | Exposes the token-spend ceiling: total, spent, remaining | Scaling fleet size or loop count to a target |

Failed or user-skipped agents resolve to `null` rather than aborting the run — filter results with `.filter(Boolean)` before using them.

## pipeline vs parallel — the barrier smell test

`pipeline` bounds wall-clock by the slowest single-item *chain*; a barrier bounds it by the sum of the slowest item *per stage*. If five finders run and the slowest takes 3× the fastest, a barrier wastes two-thirds of the fast finders' time idle.

A barrier is correct **only** when stage N needs cross-item context from all of stage N−1:

- Dedup / merge across the full result set before expensive downstream work.
- Early-exit on the total count ("0 findings → skip verification entirely").
- A stage prompt that references "the other findings" for comparison.

A barrier is **not** justified by "I need to flatten/map/filter first" (do it inside a pipeline stage), "the stages are conceptually separate" (that's exactly what pipeline models), or "it's cleaner code" (barrier latency is real). Smell test: if the code between two barriers is a plain transform with no cross-item dependency, the barrier is wrong — rewrite as a pipeline. When in doubt: pipeline.

```javascript
// Canonical shape: findings verify as soon as their dimension's review completes.
const results = await pipeline(
  DIMENSIONS,
  d => agent(d.prompt, { phase: 'Review', schema: FINDINGS_SCHEMA }),
  review => parallel(review.findings.map(f => () =>
    agent(`Adversarially verify: ${f.title}`, { phase: 'Verify', schema: VERDICT_SCHEMA })
      .then(v => ({ ...f, verdict: v }))))
)
const confirmed = results.flat().filter(Boolean).filter(f => f.verdict?.isReal)
```

## Structured returns

Free-text subagent output forces the orchestrator to parse prose — the top source of silent data loss in fan-out work. Pass a JSON schema in `opts.schema` and the subagent is *forced* to return a validated object; validation happens at the tool layer, so a mismatch triggers a retry instead of corrupt data flowing downstream. Rule of thumb: any agent whose output feeds another stage gets a schema; only terminal "summarize for the human" agents return prose.

## Budget-scaled loops

When the user sets a spend target, scale depth to it instead of hardcoding fleet sizes:

```javascript
const bugs = []
while (budget.total && budget.remaining() > 50_000) {
  const r = await agent('Find bugs in this codebase.', { schema: BUGS_SCHEMA })
  bugs.push(...r.bugs)
  log(`${bugs.length} found, ${Math.round(budget.remaining() / 1000)}k tokens remaining`)
}
```

Guard on `budget.total` — with no target set, `remaining()` is unbounded. A workflow-scripting tool may cap total agents as a runaway-loop backstop, but don't rely on an implicit ceiling that may not exist in your harness — a hand-rolled driver script needs its own bound.

## Quality patterns

Compose these per task; they are the reason to script rather than prompt:

- **Adversarial verify** — N independent skeptics per finding, each prompted to *refute* it; kill on majority refutation. Prevents plausible-but-wrong findings surviving. For a single-context variant see [`council.md`](../skills/council.md).
- **Perspective-diverse verify** — when a finding can fail multiple ways, give each verifier a distinct lens (correctness, security, reproducibility) instead of N identical refuters.
- **Loop-until-dry** — for unknown-size discovery (bugs, edge cases), keep spawning finders until K consecutive rounds return nothing *new*. Fixed counts (`while count < N`) miss the tail. Dedup against everything *seen*, not everything *confirmed* — otherwise judge-rejected findings reappear every round and the loop never converges.
- **Completeness critic** — a final agent that asks "what's missing — a modality not run, a claim unverified, a source unread?" Its output becomes the next round of work.
- **No silent caps** — if the script bounds coverage (top-N, sampling, no-retry), `log()` what was dropped. Silent truncation reads as "covered everything" when it didn't.

## Resumability

Runs journal each `agent()` call's result. On resume after a pause, kill, or script edit, the longest unchanged prefix of calls replays from cache; only edited or new calls re-run. Two consequences:

- **No nondeterminism in the script body.** `Date.now()`, `Math.random()`, and argless `new Date()` would break replay — pass timestamps in as arguments and stamp results after the run returns.
- **Debug from the journal, not from assumptions.** Before diagnosing an empty or odd final result, read the run's journal — it records what each agent actually returned. Cached results are not guaranteed non-empty.

## Scale to the ask

"Find any bugs" → a few finders, single-vote verify. "Thoroughly audit this" → larger finder pool, 3–5-vote adversarial pass, synthesis stage. The script encodes the scale decision once, visibly, instead of the model re-deciding it mid-run.
