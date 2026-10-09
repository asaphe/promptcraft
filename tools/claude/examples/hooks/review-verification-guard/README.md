# Review Verification Guard — retired

This executable example was withdrawn; this page is a migration stub.

A command regex cannot certify that a review checklist was performed. The script also emitted unsupported nested `permissionDecision: block`.

## Migration

Remove the `hooks.PreToolUse` settings registration that invokes `review-verification-guard.sh` **before** deleting your local script. Review your copied settings manually; this repository does not migrate adopter configurations.

Use the [review protocol](../../../guides/pr-review-protocol.md), the preserved [review kernel](../../docs/pr-review-rules.md), or the maintained [claude-reviewkit](https://github.com/asaphe/claude-reviewkit) plugin.

Retirement does not make the remaining guards comprehensive. See the [retirement map](../../RETIRED.md).
