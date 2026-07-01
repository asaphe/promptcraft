# PR Review Output Gate

A PreToolUse hook + validator that gates PR-review submission on a **structured dismissal log** — every review finding you drop must record evidence, reasoning, and confidence before you're allowed to post the review.

> **When this fits:** you run a `/pr-review` flow (specialist reviewer agents, optionally a bot reviewer) and want a mechanical guard that stops findings from being silently dropped. If your reviews are lightweight, this is more machinery than you need.

## Why

Reviewer agents and bots catch real bugs that local heuristics miss. *Silent dismissal* — dropping a finding without recording why — has a documented track record of letting bugs through, especially on security-sensitive PRs where an ad-hoc "looks fine" reads as thorough when it wasn't. The dismissal log forces every drop to cite the command it ran, what that returned, the reasoning, and a confidence level; the validator fails if any of those are missing.

## Components

| File | Role |
|------|------|
| `pr-review-output-gate.sh` | PreToolUse hook; runs the validator before review-submission commands |
| `validate-pr-review.sh` | reads the dismissal log, exits 1 with errors if non-compliant |
| your `/pr-review` skill | writes `/tmp/pr-review-${PR}-dismissals.json` before presenting findings |

## Modes

- **WARN (default).** Hook exits 0. A missing/invalid log emits `additionalContext` that surfaces as a warning in the next prompt. Nothing is blocked.
- **BLOCK.** The hook exits 2 when the PR diff touches security-sensitive paths (IAM, OIDC, secrets, SSM, KMS, RBAC) **and** there is no valid dismissal log. On those PRs the specialist reviewers must run via `/pr-review` for the review to be defensible.

The included hook already implements both: WARN for ordinary PRs, BLOCK scoped to security-sensitive file patterns (see `SECURITY_REGEX`). To make BLOCK unconditional, change the WARN branch's `exit 0` accordingly; to make it fully advisory, drop the `exit 2` branch.

## Dismissal log schema

The skill writes this to `/tmp/pr-review-${PR}-dismissals.json`:

```json
{
  "schema_version": 1,
  "pr_number": 1234,
  "started_at": "2025-01-01T17:30:00Z",
  "completed_at": "2025-01-01T17:42:00Z",
  "agents_run": ["security-reviewer", "devops-reviewer"],
  "bot_run": true,
  "bot_findings_seen": 3,
  "verified_findings": [
    {
      "source": "devops-reviewer",
      "severity": "ISSUE",
      "file": "config/foo.tf",
      "line": 42,
      "text": "Image tag mismatch",
      "evidence": "kubectl get deploy ... -> abc123. PR sets main."
    }
  ],
  "dropped_findings": [
    {
      "source": "codex",
      "severity": "P1",
      "text": "Cron-only triggers may drop base queue triggers",
      "verification": {
        "command": "gh api repos/<org>/<repo>/contents/path/to/scaling.tf?ref=main",
        "result": "triggers_source uses concat(a, b) — concatenated, not replaced"
      },
      "reasoning": "Concat is on main; merge produces both. Verified by reading merged code.",
      "confidence": "high"
    }
  ],
  "cross_repo_refs": [
    {
      "ref": "other-repo #390",
      "claim": "concat triggers from both sources",
      "verified": true,
      "evidence": "gh api repos/<org>/<other-repo>/contents/scaling.tf?ref=main — OR replaced with concat"
    }
  ]
}
```

### Field requirements

**Top-level:** `schema_version` (1), `pr_number`, `started_at`/`completed_at` (ISO 8601, for the freshness check), `agents_run` (≥1 reviewer), `bot_run` (bool), `bot_findings_seen` (int), `verified_findings[]`, `dropped_findings[]`, `cross_repo_refs[]`.

**Every `dropped_findings` entry:** `source`, `severity`, `text`, `verification.command` (the actual command run to check the claim), `verification.result`, `reasoning`, and `confidence` (`low` | `medium` | `high`). A `high`-confidence drop should show the finding contradicted by code read end-to-end; `medium`/`low` drops should surface to the user so they can override.

**Every `cross_repo_refs` entry:** `ref`, `claim`, `verified` (must be `true` — a `false` fails validation), and `evidence` (the command that fetched the cross-repo file plus a relevant excerpt).

**Bot accountability:** if `bot_run: true`, every bot finding counted in `bot_findings_seen` must appear in `verified_findings` or `dropped_findings` with `source: "codex"`. The validator counts independently and fails if `verified + dropped < bot_findings_seen`. Adapt the `"codex"` source name in `validate-pr-review.sh` to whatever bot(s) run on your PRs.

## Wiring

Register the hook on `PreToolUse` for the commands that post reviews, e.g.:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/pr-review-output-gate.sh" }
        ]
      }
    ]
  }
}
```

The hook self-detects the target PR from `gh api .../pulls/{n}/comments` and `gh pr review {n} --request-changes|--comment`; `gh pr review --approve` is allowed freely (no findings, no log needed). If you add a new posting path (e.g. a GraphQL mutation), extend the detection regex in the hook.

## Testing

```bash
# Build a minimal valid log and validate it (expect exit 0):
PR=12345
cat > /tmp/pr-review-${PR}-dismissals.json <<EOF
{
  "schema_version": 1, "pr_number": ${PR},
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "agents_run": ["security-reviewer"], "bot_run": false, "bot_findings_seen": 0,
  "verified_findings": [], "dropped_findings": [], "cross_repo_refs": []
}
EOF
bash validate-pr-review.sh ${PR}          # expect exit 0
rm /tmp/pr-review-${PR}-dismissals.json

# Negative test — an unverified cross-repo ref should fail:
#   jq '.cross_repo_refs += [{"ref":"x","claim":"y","verified":false}]' ...  → expect exit 1

# Hook behavior:
echo '{"tool_input":{"command":"gh pr review 99999 --approve --body ok"}}' \
  | bash pr-review-output-gate.sh; echo "exit: $?"   # expect 0 (approve is allowed)
echo '{"tool_input":{"command":"git status"}}' \
  | bash pr-review-output-gate.sh; echo "exit: $?"   # expect 0 (irrelevant command)
```

## What it does NOT catch

- **The absence-of-findings case** ("what did the review miss entirely") — that's the job of an adversarial pass in the review skill, not this accounting gate.
- **Hallucinated evidence strings** — the validator checks the field exists, not that the quoted excerpt actually appears in the referenced file. Add a string-match check if you need that.
