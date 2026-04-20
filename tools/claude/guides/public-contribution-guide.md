# Open Source Contribution Guide for Claude Code

How to contribute to open-source projects effectively using Claude Code — from studying a repo to landing a merged PR.

## Before You Write Code

### 1. Study the repo

Read in this order:

1. **CONTRIBUTING.md** — Branch naming, PR process, testing requirements, sign-off policies. This overrides any default assumptions.
2. **CLAUDE.md** (if present) — Architecture, conventions, performance constraints, common pitfalls. This is the codebase's own Claude Code instructions.
3. **Open issues and PRs** — Search ALL states (open, closed, merged) for your topic. Use specific keywords and variations. A duplicate PR wastes everyone's time.
4. **The module you'll change** — Read the sibling files, not just the target. Understand the patterns before adding to them.
5. **Tests** — How do they test? Inline `#[cfg(test)]`? Separate `tests/` directory? Fixtures from real data or synthetic? Match the existing style.

### 2. Check for existing work

Before opening an issue or PR, search exhaustively:

```bash
gh issue list --repo org/repo --state all --limit 500 --json number,title,state \
  --jq '.[] | "\(.state)\t\(.number)\t\(.title)"' | grep -iE "keyword1|keyword2|keyword3"

gh pr list --repo org/repo --state all --limit 200 --json number,title,state \
  --jq '.[] | "\(.state)\t\(.number)\t\(.title)"' | grep -iE "keyword1|keyword2|keyword3"
```

Search with multiple keyword variations — the maintainer may have used different terminology.

### 3. Open an issue first

For non-trivial changes, signal intent before coding. An issue lets the maintainer weigh in on the approach before you invest time. See [Issue Writing Guide](issue-writing-guide.md) for structure.

Exception: typo fixes, doc corrections, and obvious one-line bug fixes can go straight to PR.

## Implementation

### 4. Fork and branch correctly

```bash
# Fork if you don't have push access
gh repo fork org/repo --clone=false

# Add fork as remote
git remote add fork https://github.com/your-username/repo.git

# Branch from the correct base (usually develop or main — check CONTRIBUTING.md)
git fetch origin
git checkout -b "feat/description" origin/<base-branch>
```

**Branch naming:** Follow the project's convention exactly. If they use `feat(scope): description` but git rejects colons, use `feat/scope-description`.

### 5. Match codebase conventions

The highest-quality contribution looks like the maintainer wrote it:

- **Same patterns** — If the codebase uses individual named regex variables, don't introduce a vector of structs. If they use `lazy_static!`, don't use `once_cell`.
- **Same test style** — If tests are inline `mod tests` with `assert_eq!`, don't introduce a test framework.
- **Same error handling** — If they use `anyhow`, don't use `thiserror`. If they `unwrap()` in `lazy_static!`, you can too.
- **Same naming** — If existing functions use `snake_case` with full words, don't abbreviate.

### 6. Test locally with their gate

Run whatever pre-commit or CI gate the project specifies — not your own version of it. If CONTRIBUTING.md says:

```bash
cargo fmt --all --check && cargo clippy --all-targets && cargo test
```

Run exactly that. If you don't have the toolchain, install it. "Happy to address CI failures" is a red flag that says you didn't test.

### 7. PII scan before every commit

Before staging files, scan the diff for sensitive data. See [PII Prevention Guide](pii-prevention-guide.md) for patterns.

This applies to:

- Code and test fixtures
- Commit messages
- PR body text
- Issue descriptions

### 8. Commit with sign-off if required

Many projects require DCO (Developer Certificate of Origin):

```bash
git commit -s -m "feat(scope): description"
```

Check CONTRIBUTING.md for sign-off requirements.

## PR Submission

### 9. PR body must be accurate

Every claim must match reality:

- **Test count** — Count `#[test]` annotations in your changed files. Don't estimate.
- **Verification results** — Show actual command output, not "tests pass."
- **Scope description** — If you delivered more or less than the linked issue proposed, say so explicitly.

### 10. Reference the issue

Use `Closes #NNN` to auto-link. If the PR only partially addresses the issue, use `Relates to #NNN` and comment on the issue explaining what's deferred.

### 11. Post-submission checklist

After creating the PR:

- [ ] PR body test count matches actual count
- [ ] All verification claims are true as of the last push
- [ ] No PII in diff, PR body, commit messages, or linked issues
- [ ] Issue references are correct
- [ ] If the issue proposed N things and you did M, the delta is documented

## Common Mistakes

| Mistake | Why it's bad |
|---------|-------------|
| Introducing new abstractions in a codebase that uses simple functions | Maintainer sees it as over-engineering |
| "Happy to address CI failures" | Signals you didn't test; maintainer has to run your tests for you |
| Claiming N tests when you have M | Credibility loss on first review |
| Drive-by formatting fixes in unrelated files | Violates scope rules, pollutes diff |
| Editing issue body after PR is submitted | Confuses the historical record |
| Not checking for existing issues/PRs | Wastes everyone's time on duplicates |

## Related Resources

- [Issue Writing Guide](issue-writing-guide.md) — How to structure effective issues
- [PII Prevention Guide](pii-prevention-guide.md) — Preventing sensitive data leakage in public repos
- [Best Practices](claude-best-practices.md) — General Claude Code workflow
