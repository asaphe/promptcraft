# CI Polling Guard — retired

This executable example was withdrawn; this page is a migration stub.

It treated arbitrary long sleeps as CI polling and emitted unsupported nested `permissionDecision: block`.

## Migration

Remove the `hooks.PreToolUse` settings registration that invokes `ci-polling-guard.sh` **before** deleting your local script. Review your copied settings manually; this repository does not migrate adopter configurations.

Use `gh run watch <run-id> --exit-status` where supported; run it in the background when your assistant supports that. A deliberate wait is not inherently a defect. See the [session analytics guide](../../../guides/session-analytics-guide.md).

Retirement does not make the remaining guards comprehensive. See the [retirement map](../../RETIRED.md).
