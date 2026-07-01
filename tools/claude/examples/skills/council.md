---
name: council
topic: Planning
description: >-
  Multi-perspective parallel review by a council of expert subagents, each in
  its own context (no same-context persona correlation). Roster is inferred
  from the task or specified explicitly. Use for design docs, incident RCA,
  cross-cutting refactors, vendor selection, migrations, hard debugs, security
  reviews, ADRs — any load-bearing decision where orthogonal perspectives
  beat single-context reasoning. Distinct from /pr-review (post-code).
  Usage - /council [input] or /council with <roster> [input]
user-invocable: true
allowed-tools: Agent, Read, Glob, Grep, Bash(gh issue view*), Bash(gh api*), Bash(cat*), Bash(ls*), Bash(mkdir*), AskUserQuestion, Write
argument-hint: "[plan-path | <ticket> | 'current' | inline-text] [with <comma-separated-roster>] [--no-pm]"
---

# Council

A general-purpose review board. The output is a structured critique of an input artifact (plan, incident, refactor proposal, vendor matrix, debug state, etc.), **not** code changes.

## When to use

Council is gated on **load-bearing decisions where orthogonal perspectives beat single-context reasoning**. Specific triggers:

- Design doc / RFC / ADR ≥10KB or labeled load-bearing
- Cross-cutting refactor touching ≥3 packages or ≥2 repos
- Incident with unclear root cause **or** first 2 hypotheses already failed
- Vendor / tool / framework selection with material lock-in
- Migration plan (sequencing, rollback, dual-write)
- Production change with broad blast radius (multi-tenant, IAM/secrets, schema, prod data)
- Security review of new auth / permissions / external-input surface
- Architecture decision the user labels "important" / "production-critical" / "load-bearing"

**Do NOT use for:**

- Routine code edits, single-file refactors, doc tweaks
- Quick bug fixes with clear root cause
- PR reviews → use `/pr-review`
- Verifying a finished implementation → that's `verify` or `/code-review`
- Inputs <5KB with no explicit "council this" signal — too little material for orthogonal perspectives

## Mechanism — why parallel subagents, not one model wearing hats

A single context adopting six personas in sequence produces **correlated** output: the same weights predicting agreeable continuations. Independent subagents, each with their own context and a tight role brief, produce genuinely orthogonal findings. The synthesis layer (PM) then reconciles them — including surfacing where experts **disagree**, which is the whole point.

## Auto-suggest (when you propose `/council` unprompted)

Propose a council when the conversation hits a "When to use" trigger above. The proposal format:

```text
Council candidate: <one-line task summary>
Proposed roster (N experts):
  - <expert>: <one-line why>
  ...
Estimated cost: ~$<X> (N+1 subagents at your review-tier model)
Spawn / swap <X> for <Y> / different roster / skip?
```

Limits: **never auto-spawn**, always gate on explicit approval. **Max 1 auto-suggestion per conversation** unless the user invites more.

## Steps

### 1. Resolve the input artifact

From `$ARGUMENTS`:

- **File path** (absolute or under a working dir) → Read full file.
- **`<ticket>`** (an issue-tracker ID) → fetch the ticket from your issue tracker.
- **`current`** or no argument → use the artifact as it stands in the current conversation context. If unclear what "the artifact" refers to, ask via `AskUserQuestion` (single question, list the candidates).
- **Inline text** → use as-is.
- **Incident** → resolve to the observability/log-bundle artifact path the conversation has already gathered, or ask if unclear.

Write the resolved input to `/tmp/council-<short-id>/input.md` so every subagent reads the **same** artifact (no drift from interpreting "current context" differently across agents).

### 2. Pick roster

The council draws its panel from whatever expert agents/personas you have available — assemble
3-7 whose lanes match the input's surface area. Keep a catalog of your reviewer archetypes
(each with a one-line lane + an adversarial frame) and select from it; the archetypes below are
generic defaults you can adapt to your own roster.

**Parse explicit roster first.** If `$ARGUMENTS` contains `with <expert1>,<expert2>,...`, use that roster verbatim. Validate each name against your available agents; reject unknown names with the list of valid ones.

**Otherwise infer from the input.** Pick 3-7 experts whose lanes match the input's surface area. Rules of thumb:

| Input type | Default roster |
|---|---|
| Design doc / RFC / ADR | architect, security, sre, simplicity-skeptic, coder, qa, reverse-doc-auditor (if shipped code exists for cross-check) |
| Incident RCA | ic-commander, forensics, sre, security (if compromise suspected), postmortem-author |
| Cross-cutting refactor | architect, coder, simplicity-skeptic, sre, qa, migration-planner |
| Vendor / tool selection | vendor-evaluator, cost-analyst, dx-advocate, security, sre, architect |
| Migration plan | migration-planner, sre, coder, qa, security, cost-analyst |
| Hard debug (≥2 hypotheses failed) | 3-5 **hypothesis-investigator** instances, each with a distinct theory, + forensics |
| Security review | security, architect, sre, simplicity-skeptic, qa |
| Production change (broad blast) | sre, security, qa, architect, coder |

**Always surface the chosen roster to the user before dispatching** — one line per expert, the user can edit / approve / swap. Format:

```text
Roster for this council:
  1. architect — module boundaries, abstraction cost
  2. security — threat model, prompt injection, secrets
  3. ...
Approve, or edit (e.g. "drop coder, add cost-analyst")?
```

**`--no-pm`** skips the synthesis pass (raw expert findings only).

### 3. Dispatch in parallel — one Agent call per expert, all in the same response

Each Agent invocation gets:

- `subagent_type: general-purpose`
- Tight role brief inline (subagents don't inherit parent context — embed the lane + adversarial frame directly)
- The input path: `/tmp/council-<id>/input.md`
- Any side artifacts the expert needs (e.g., shipped-code path for a doc-vs-code auditor, repo paths for a coder, log bundles for forensics)
- Instruction to produce findings in the **required output schema** (below) — no preamble, no closing summary, no "looks good"

**Role-brief template:**

```text
You are the {ROLE} on a council reviewing {ARTIFACT_TYPE} at {PATH}.

Read the entire input before producing findings. Do not skim.

Your lane: {LANE_DESCRIPTION}
Your adversarial frame: {ADVERSARIAL_PROMPT}
{SIDE_ARTIFACTS_INSTRUCTION_IF_ANY}

Discipline (non-negotiable):
- Default-skeptical. "Looks fine" requires per-axis positive evidence, not absence-of-failure on one axis.
- Every claim cites the line/section/file it's about (quote 1-2 lines).
- If you don't see evidence in the input that addresses a concern, the concern stands — silence is not an answer.
- Produce at least one "Steelman against the input" finding. If you can't construct one, you didn't read adversarially enough.
- Do not editorialize on lanes that aren't yours. If you're Security, don't comment on test strategy — QA owns that.

Output schema (strict, no other text):

## Findings

### [BLOCKER|ISSUE|SUGGESTION] <one-line title>
**Where:** <input section or quoted line>
**Concern:** <2-4 lines, evidence-based>
**Mitigation:** <concrete change, not "consider X">
**Confidence:** low | medium | high

(repeat per finding)

## Steelman against the input
<at least one credible failure mode, 3-6 lines, even if you generally support the input>

## Open questions for the author
<bullet list, each one a question the input does not answer that your lane needs answered>
```

Write each expert's raw output to `/tmp/council-<id>/expert-NN-<role>.md`. All Agent calls go in **one response** so they run concurrently. Don't loop.

### 4. Synthesis pass (PM / orchestrator) — unless `--no-pm`

Once all experts return, dispatch a final Agent (general-purpose, on your strongest model) with:

- Each expert's raw output (full, not summarized)
- The input artifact
- Instructions to:
  1. **Deduplicate** findings (multiple experts often flag the same thing — collapse, attribute to all flaggers).
  2. **Surface tensions** — explicit "Expert A says X, Expert B says ¬X" section. **Do not paper over.** This is where the council's real value lives.
  3. **Priority-rank**: Blockers (must-resolve before action) → Issues (must-resolve before merge/close) → Suggestions (track and revisit).
  4. **Sequence** — what to decide first, what depends on what, what can be parallelized.
  5. **Open questions** — consolidated, deduplicated.
  6. **One-line executive verdict**: `proceed | proceed-with-changes | redesign | abandon` (for design); `root-cause-found | continue-investigation | escalate` (for incident); `pick-A | pick-B | gather-more-data` (for vendor); etc. — pick the verdict vocabulary that fits the input type.

PM output schema:

```text
## Verdict
<one line: verdict>
<one line: biggest reason>

## Blockers
- [{flagged-by: <experts>}] <title> — <one-line concern> → <fix>
...

## Issues
...

## Suggestions
...

## Cross-expert tensions
### <topic>
- <Expert A position> vs <Expert B position>
- Author must decide: <the actual decision>

## Open questions
- <question> [from: <expert>]
...

## Sequence
1. Decide <X>
2. If <X>=A, then <Y>; if <X>=B, then <Z>
...
```

### 5. Write the report

Write the full output (per-expert raw findings + PM synthesis) to your reports directory, e.g.:

```text
<reports-dir>/councils/<input-slug>-<YYYY-MM-DD>.md
```

Surface the PM synthesis in the conversation; link to the file for the per-expert raw findings at `/tmp/council-<id>/expert-*.md`.

## Output discipline

- **No "looks good overall" sentences anywhere.** First-pass verdict is skeptical.
- **No paper-over of disagreement.** Cross-expert tensions are the council's main product — if every expert agrees, either the input is unusually clean **or** the council collapsed into correlated output (re-run with sharper adversarial prompts).
- **No suggestions to "consider X"** — each finding's mitigation must be a concrete edit / action. "Consider rate-limiting" is rejected; "Add a 100-req/min token-bucket on the /webhook endpoint, scoped per-tenant" is accepted.

## Cost notes

Full roster + PM = ~7 Agent invocations at your review-tier model's pricing. That's why this skill is gated on "load-bearing surface" in *When to use*. For lighter checks use a single inline `Explore` or `Plan` agent. Surface the estimated cost in the auto-suggest proposal before spawning.

## Self-check before declaring done

1. Did every expert produce a Steelman section? (If any skipped, the council failed; re-dispatch that one with a sharper brief.)
2. Did the PM surface at least one cross-expert tension? (If zero, suspect correlated output.)
3. Does every Blocker have a concrete fix, not "consider"?
4. Is the verdict line present, unambiguous, and using a verdict vocabulary that fits the input type?
5. Is the report written to your reports directory **and** linked in the conversation?
