#!/usr/bin/env bash
# PreToolUse hook — nudges (does not block) before `gh pr review`/`gh pr comment` posts whose body asserts AWS resource state (role, policy, secret, SSM param, KMS key) when the claim may be derived from local IaC grep instead of live AWS. Exit 0 always. Rationale + registration JSON: README.md.

INPUT=$(cat)
CMD=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$CMD" ]; then
  exit 0
fi

# Only fire on outbound claim surfaces — PR review/comment posts.
if ! printf '%s\n' "$CMD" | grep -qE '(gh pr (review|comment)|gh api [^|;&]*/(comments|reviews))'; then
  exit 0
fi

# Require state-assertion vocabulary near an AWS resource identifier; either alone is too noisy.
if ! printf '%s\n' "$CMD" | grep -qiE '(verified|confirmed|does( not)? exist|is (not )?(attached|present|configured|allowed|denied)|trust policy|the role|the policy|the secret|assumes? role|getsecretvalue|principal)'; then
  exit 0
fi

if ! printf '%s\n' "$CMD" | grep -qiE '(arn:aws:|role/|policy/|secret:|parameter /|key/|(^|[^a-z])(iam|ssm|kms)([^a-z]|$)|secrets manager)'; then
  exit 0
fi

cat >&2 <<'EOF'
PRE-CLAIM GUARD: This `gh pr review`/`gh pr comment` body looks like it asserts AWS resource state (role, policy, secret, SSM param, KMS key). Before posting:
  (1) Did you verify the claim against LIVE AWS state — not a grep of local IaC code?
  (2) If not, run the live describe/get first: aws iam get-role / get-policy, aws secretsmanager describe-secret, aws ssm get-parameter, aws kms describe-key.
  (3) The local repo and Terraform state can both be stale; only `aws describe/get` against the live account is authoritative.
Posting unverified live-state claims as PR review evidence is the failure mode "verify, don't assume" exists to prevent.
EOF

exit 0
