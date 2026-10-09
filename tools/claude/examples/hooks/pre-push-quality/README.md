# Pre-Push Quality Gate — retired

This executable example was withdrawn; this page is a migration stub.

Its generic linter, directory and working-directory assumptions did not reliably validate the repository being pushed. It also emitted unsupported nested `permissionDecision: block`.

## Migration

Remove the `hooks.PreToolUse` settings registration that invokes `pre-push-lint-guard.sh` **before** deleting your local script. Review your copied settings manually; this repository does not migrate adopter configurations.

Run the repository’s own lint/test commands and CI. See [testing and validation](../../docs/testing-validation.md).

Retirement does not make the remaining guards comprehensive. See the [retirement map](../../RETIRED.md).
