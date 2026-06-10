# Pre-Claim Guard

A **PreToolUse** hook that nudges (never blocks) before `gh pr review` / `gh pr comment` posts whose body asserts AWS resource state — reminding the model to verify the claim against **live AWS**, not a grep of local IaC code.

## Why This Exists

The failure mode this catches: a PR review comment states *"the role X allows Y"*, *"secret Z exists"*, *"the trust policy permits W"* — posted as review evidence, but derived from grepping local Terraform code instead of querying live AWS state.

Local repo and Terraform state can both be stale:

- The role may have been modified out-of-band (console, another pipeline, an incident fix)
- The Terraform change may not have been applied yet
- The state file may lag the actual account

Once posted, the claim becomes "evidence" other reviewers and the PR author rely on. A wrong live-state assertion in a review is worse than no assertion — it actively suppresses the verification someone else might have done. Only `aws describe/get` against the live account is authoritative.

## What It Detects

The hook fires only when **all three** conditions hold (any one alone is too noisy):

1. **Outbound claim surface** — the command is `gh pr review`, `gh pr comment`, or a `gh api .../comments|/reviews` post
2. **State-assertion vocabulary** — `verified`, `confirmed`, `does (not) exist`, `is (not) attached/present/configured/allowed/denied`, `trust policy`, `the role`, `the policy`, `the secret`, `assumes role`, `GetSecretValue`, `principal`
3. **AWS resource identifier** — `arn:aws:`, `role/`, `policy/`, `secret:`, SSM parameter paths, or the words IAM / SSM / KMS / Secrets Manager

## Behavior

- **Exit 0 always** — reminder only, never blocks. The model may legitimately have verified the claim already; the nudge just forces that question to be answered before the post lands.
- Reminder is emitted to stderr, which Claude Code injects into the conversation as model-facing context.

## Installation

Register as a PreToolUse hook on `Bash`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/pre-claim-guard.sh"
          }
        ]
      }
    ]
  }
}
```

Requires `jq` on PATH.

## Customization

The pattern set is AWS-flavored. The same structure ports to any external system where review claims get made from stale local sources:

```bash
# GCP flavor
grep -qiE '(projects/|serviceAccount:|roles/|gcloud|gcs://)'

# Kubernetes flavor — "the deployment has the new env var" claimed from manifest grep
grep -qiE '(deployment/|configmap|the (pod|deployment|service) (has|uses|mounts))'
```

Pair the vocabulary list with your team's actual review language — the goal is matching *assertions of live state*, not any mention of a resource.

## Relationship to Other Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| **pre-claim-guard** | PreToolUse | Before posting review claims: verify against live state |
| [**stateful-op-reminder**](../stateful-op-reminder/) | PreToolUse | Before mutating live state: capture baseline, verify after |
| [**review-verification-guard**](../review-verification-guard/) | PreToolUse | Blocks review posts with an operation-specific verification checklist |

stateful-op-reminder guards the *write* path to external systems; this hook guards the *claim* path about them. Both enforce the same principle from opposite directions: live state is the only authority.
