# kubectl Context Inject — retired

This executable example was withdrawn; this page is a migration stub.

It injected kubectl’s `--context` into Helm, which requires `--kube-context`, and whole-command matching mishandled compound commands.

## Migration

Remove the `hooks.PreToolUse` settings registration that invokes `kubectl-context-inject.sh` **before** deleting your local script. Review your copied settings manually; this repository does not migrate adopter configurations.

Select and verify the target explicitly, then use `kubectl --context <context> …` or `helm --kube-context <context> …`. Do not automatically rewrite commands. See [post-apply verification](../post-apply-state-check/).

Retirement does not make the remaining guards comprehensive. See the [retirement map](../../RETIRED.md).
