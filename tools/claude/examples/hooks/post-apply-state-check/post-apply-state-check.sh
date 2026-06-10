#!/usr/bin/env bash
# PostToolUse hook — nudges after a successful terraform/kubectl apply: exit 0 proves syntax was accepted, not that the resource is live and correct. Verify the actual resource before declaring done. Registration JSON: README.md.

INPUT=$(cat)
CMD=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // empty')

# Claude Code's PostToolUse payload field is .tool_response.stdout in current releases; older versions used .tool_result.stdout. Try both for portability.
RESULT=$(printf '%s\n' "$INPUT" | jq -r '.tool_response.stdout // .tool_result.stdout // empty')

[ -z "$CMD" ] && exit 0

# Optional default kube context for the suggested verification commands. Set KUBE_DEFAULT_CONTEXT in your environment; falls back to a placeholder.
KUBE_CTX="${KUBE_DEFAULT_CONTEXT:-<cluster-context>}"

emit_ctx() {
  jq -n --arg ctx "$1" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $ctx
    }
  }'
}

if printf '%s\n' "$CMD" | grep -qE 'terraform[[:space:]]([^|;&]* )?apply([[:space:]]|$)'; then
  # Only fire when the apply actually succeeded — a nudge after a failed apply is noise.
  printf '%s\n' "$RESULT" | grep -qE 'Apply complete!' || exit 0
  emit_ctx "POST-APPLY CHECK: 'Apply complete' proves Terraform's view, not the consumer's. Before declaring done:
  1. Verify each new/changed resource exists live: aws iam get-role, aws ssm get-parameter, aws ecr describe-repositories (or your provider's describe/get equivalent)
  2. Verify consumers can actually reach the new resources (sts assume-role, ssm get-parameter from the consumer's role)
  3. Confirm state file coverage: terraform state list | grep <resource>
  4. Update the PR body + tracker ticket with the applied timestamp"
  exit 0
fi

if printf '%s\n' "$CMD" | grep -qE 'kubectl[[:space:]]([^|;&]* )?apply([[:space:]]|$)'; then
  printf '%s\n' "$RESULT" | grep -qE '(configured|created|unchanged)' || exit 0
  RESOURCE=$(printf '%s\n' "$RESULT" | grep -oE '[a-z0-9/.-]+ (configured|created)' | head -1 | awk '{print $1}')
  if [ -n "$RESOURCE" ]; then
    emit_ctx "POST-APPLY CHECK: 'configured/created' means the API server accepted the manifest, not that the workload is healthy. Verify ${RESOURCE}:
  kubectl get ${RESOURCE} --context ${KUBE_CTX} -o wide
  kubectl describe ${RESOURCE} --context ${KUBE_CTX}  # check Events: for scheduling/pull/probe failures"
  else
    emit_ctx "POST-APPLY CHECK: 'configured/created' means the API server accepted the manifest, not that the workload is healthy. Verify applied resources:
  kubectl get <resource> --context ${KUBE_CTX} -o wide
  kubectl describe <resource> --context ${KUBE_CTX}  # check Events: for scheduling/pull/probe failures"
  fi
  exit 0
fi

exit 0
