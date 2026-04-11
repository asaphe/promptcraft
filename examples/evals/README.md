# Skill Evaluation Framework

Validation suite for Claude Code skills — catches trigger routing errors and functional regressions when skills, agents, or `CLAUDE.md` are modified.

## The Problem

Claude Code routes user queries to skills based on description fields in `SKILL.md` files. When skills have overlapping domains (e.g., a PR review skill vs. a PR status-check skill vs. a PR resolver skill), routing errors are common and hard to catch manually. A change to one skill's description can redirect queries that used to hit a different skill.

## Structure

```
evals/
  runner.py                 # Orchestrator (manual checklist mode)
  {skill-name}/
    trigger_eval.json       # Does the right skill activate for a given query?
    evals.json              # Does the skill produce correct output? (optional)
```

## Two Types of Evals

### 1. Trigger Evals — "Does the right skill fire?"

Each skill has positive cases (should activate) and negative cases (should NOT activate, with which other skill should win instead):

```json
[
  {"query": "review PR #456", "should_trigger": true},
  {"query": "check CI on PR 456", "should_trigger": false, "expected_skill": "pr-check"},
  {"query": "ambiguous edge case", "should_trigger": false, "expected_skill": "other-skill", "note": "why this is tricky"}
]
```

Negative cases always specify `expected_skill` — making routing errors diagnosable rather than just "wrong."

### 2. Functional Evals — "Does the skill behave correctly?"

For your most critical skills, add observable behavioral expectations:

```json
{
  "skill_name": "deploy",
  "evals": [
    {
      "id": 1,
      "prompt": "deploy the app to staging",
      "expectations": [
        "Reads deployment config before executing",
        "Asks for environment confirmation before proceeding",
        "Does NOT deploy to production without explicit instruction"
      ],
      "setup": "Optional: describe required preconditions",
      "teardown": "Optional: cleanup instructions"
    }
  ]
}
```

Expectations are plain-language descriptions of observable behavior (file reads, tool calls, agent spawns, prohibitions). Verified manually against the Claude Code session trace.

## Running Evals

```bash
# Full manual checklist (all skills)
python evals/runner.py

# One skill only
python evals/runner.py --skill deploy

# Trigger evals only (faster)
python evals/runner.py --type trigger

# Functional evals only
python evals/runner.py --type functional
```

The runner prints a checklist. Test each query interactively in a Claude Code session and verify the expected behavior.

## When to Run

Run trigger evals when you change:
- A `SKILL.md` description field (this is what Claude uses for routing)
- `CLAUDE.md` agent routing tables or skill references
- Any skill that belongs to a family with overlapping triggers

## CI Integration

Add a GitHub Actions workflow that posts a reminder comment when a PR modifies skill files:

```yaml
name: Skill eval reminder
on:
  pull_request:
    types: [opened, reopened]  # Not on every push — avoid comment spam
    paths:
      - '.claude/skills/**/SKILL.md'
      - '.claude/CLAUDE.md'

jobs:
  remind:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea # v7
        with:
          script: |
            const { data: files } = await github.rest.pulls.listFiles({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.issue.number,
            });
            const skillFiles = files
              .filter(f => f.filename.match(/\.claude\/skills\/.*SKILL\.md/) || f.filename === '.claude/CLAUDE.md')
              .map(f => `- \`${f.filename}\``);

            if (skillFiles.length === 0) return;

            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: [
                '## Skill files changed — run trigger evals',
                '',
                'The following skill/routing files were modified:',
                ...skillFiles,
                '',
                '```bash',
                'python examples/evals/runner.py --type trigger',
                '```',
                '',
                'Check that trigger routing is still correct, and update `trigger_eval.json` if skill descriptions changed.',
              ].join('\n'),
            });
```

Fires once on PR open — not on every push — to avoid comment spam.

## Adding Evals for a New Skill

1. Create `evals/{skill-name}/trigger_eval.json`
2. Write ~5 positive cases (queries that should trigger this skill) and ~5 negative cases (queries that should trigger a *different* skill instead)
3. Optionally add `evals.json` for functional expectations (recommended for your top 3-5 most-used skills)
4. Run `python evals/runner.py --skill {skill-name}` to verify the checklist renders

## Roadmap

**Phase 1 (current):** Manual checklist mode — `runner.py` prints queries to test interactively.

**Phase 2:** CI reminder — GHA workflow warns when skill files change without eval updates.

**Phase 3:** Automated runner via Claude Code SDK — send each trigger query to Claude Code, observe which skill activates, pattern-match expectations against tool call traces, output timestamped JSON + markdown report.

## See Also

For **automated hook testing** (pipe JSON through PreToolUse hooks, check exit codes), see `.claude/evals/`.
