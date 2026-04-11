# CLAUDE.md

Promptcraft — open-source prompt engineering knowledge base and toolkit for Claude Code, ChatGPT, and Cursor.

## Public Repo — Zero Tolerance

- All commits are permanent, visible, and indexed. No PII, company names, internal service names, workspace/account IDs, or token prefixes in any content.
- Scan every diff for PII before committing. `git diff --staged | grep -iE '(company|internal|username|account-id)'`
- No internal references — this is a standalone public project. Content should read as if written by an independent contributor.

## Code Standards

- Conventional commits: `type(scope): description` — `feat:`, `fix:`, `docs:`, etc.
- Always work via PRs — never push directly to main.
- Shell scripts must use POSIX ERE only (no `\s`, `\d`, `\b`). macOS `grep -E` doesn't support PCRE.

## Content Accuracy

This repo is a knowledge base — getting a pattern wrong teaches it wrong to every reader who copies it.

- Verify every code example works if copied verbatim. Hook exit codes must match Claude Code's actual behavior. Settings JSON must use valid configuration fields.
- Cross-reference before adding. Check if content exists elsewhere before duplicating. Verify file paths in cross-references actually exist.
- Keep `examples/` and `claude/scaffolding/` in sync — when updating a pattern in one, check the other.

## Review Posture

- Multiple self-review passes before presenting changes.
- Adversarial pass: challenge every example against a real shell, real Claude Code, real edge case.
- When adding hooks: test with `echo '{"tool_input":{"command":"..."}}' | ./hook.sh` for every documented case.

## Hooks (dogfooding)

This repo uses its own example hooks in `.claude/hooks/`:

- `destructive-guard.sh` — Two-tier blocking (hard: push to main, AWS deletions; soft: PR ops, force-push). Copied from `examples/hooks/destructive-guard/`.
- `pr-create-guard.sh` — Blocks PR creation on missing prerequisites. Copied from `examples/hooks/pr-create-guard/`.
- Learning-capture hooks — Session start/end/precompact learnings.

When updating a hook in `examples/`, sync the `.claude/hooks/` copy too.
