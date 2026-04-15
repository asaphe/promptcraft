# Operational Discipline

## Implementation Discipline

- **Verify cross-platform behavior for committed artifacts** — If a script generates files committed to the repo and CI runs a different bash/OS version than local (macOS bash 3.2 vs Linux bash 5.x), confirm output is byte-identical on both. `${var:0:N}` is the most common trap — byte-based on bash 3.2, char-based on 5.x.

## PR Lifecycle Hygiene

- **After every push, run post-push checklist** — (1) Resolve all addressed review threads, (2) Update PR body to reflect final state. This is not optional.

- **Fix all issues encountered, not just what the PR introduced** — When reviewing or working on a PR, address all issues found regardless of origin.

- **Never defer work to follow-up PRs** — If a fix is under ~50 lines and related to the current work, do it now.