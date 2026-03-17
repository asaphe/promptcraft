# Issue Writing Guide

How to write effective issues on open-source projects — feature proposals, bug reports, and design discussions.

## Before Opening

1. **Search all issues and PRs** (open AND closed) for your topic. Use multiple keyword variations.
2. **Read CONTRIBUTING.md** — Some projects have issue templates or specific instructions.
3. **Decide the issue type** — A concrete proposal, a bug report, or a design discussion each have different structures.

## Issue Types

### Feature Proposal (concrete)

For changes you plan to implement. Structure:

```markdown
## Problem

What's wrong today. Include reproduction steps if applicable.
Show the actual output and explain why it's a problem.

## Proposed Solution

Specific technical approach. Include:
- What changes, where
- A table of patterns/behaviors if applicable
- Flag names and default values

## Additional Improvements (same scope)

If you have related small improvements, list them separately.
This lets the maintainer approve the core and defer extras.
```

**Key principles:**

- Lead with the problem, not the solution. The maintainer may have a better approach.
- Be specific — "add sanitization" is vague; a table of patterns with replacements is actionable.
- Include reproduction steps. `rtk learn --write-rules && cat .claude/rules/cli-corrections.md` is better than "the output contains sensitive data."
- Offer to submit a PR: "Happy to submit a PR for this. Would target `develop`."

### Bug Report

```markdown
## Bug

One-line description of unexpected behavior.

## Steps to Reproduce

1. Exact command
2. Exact input
3. Expected vs actual output

## Environment

- OS, version
- Tool version
- Relevant configuration

## Possible Cause (optional)

If you've investigated, share what you found. But clearly separate
"I believe" from "I verified."
```

### Design Discussion

For changes too large or uncertain for a direct proposal. Structure:

```markdown
## Problem

What's not working well and why. Include data — session counts,
match rates, real examples.

## Proposed Improvement

High-level approach, not implementation details.

### Concrete examples

Show before/after with real (sanitized) data:

| Current output | Proposed output |
|---------------|----------------|
| Raw 200-char command pair | Generalized principle with one example |

### How it could work

Sketch the approach without prescribing the implementation.
Ask the question you want the maintainer to answer:
"Should generalization happen in the detector or the reporter?"

## Scope

Which files/modules would be affected.
Note if it's a significant redesign vs a small extension.
```

**Key principle:** A design discussion respects that the maintainer owns the architecture. You bring the problem and data; they (may) bring the design. Offer ideas, don't prescribe.

## Writing Quality

### Title

- Prefix with type: `feat(scope):`, `fix(scope):`, `bug:`, `discussion:`
- Be specific: "sanitize sensitive data in learn output" not "improve learn"
- Under 70 characters

### Body

- **No filler.** Every sentence should add information.
- **Data over opinions.** "44 rules from 60 sessions, 1 recurs" is stronger than "the output is noisy."
- **Tables for structured information.** Pattern/replacement pairs, before/after comparisons, affected commands.
- **Reproduction commands should be copy-pasteable.** Use code blocks.
- **Sanitize examples.** Never include real infrastructure IDs, account numbers, or org names in issues on public repos. See [PII Prevention Guide](pii-prevention-guide.md).

### Follow-up

After submitting a PR for the issue:

- Comment on the issue linking the PR and noting any deviations from the proposal
- If you delivered more than proposed, explain what was added and why
- If you deferred items from the proposal, list them explicitly so the issue can be updated or kept open

## Anti-patterns

| Don't | Do Instead |
|-------|-----------|
| "This doesn't work" with no reproduction | Exact steps, expected vs actual |
| Proposing implementation before describing the problem | Problem first, solution second |
| Prescribing architecture in a design discussion | Ask questions, offer ideas |
| Leaving the issue stale after your PR ships | Comment with the outcome |
| Including real account IDs or org names in examples | Sanitize all examples |
| Opening an issue for something that already exists | Search first, thoroughly |

## Related Resources

- [Public Contribution Guide](public-contribution-guide.md) — Full contribution workflow
- [PII Prevention Guide](pii-prevention-guide.md) — Sanitizing examples for public repos
