# Claude Code GitHub Actions Integration

Using Claude Code in CI/CD pipelines via the first-party `anthropics/claude-code-action` GitHub Action. This enables automated code review, issue triage, PR labeling, and more — directly in your GitHub workflows.

## Overview

`anthropics/claude-code-action` runs Claude Code as a GitHub Action with access to your repository context. It can read files, analyze diffs, post comments, and apply labels — all within the security boundary of GitHub Actions.

## Setup

### Prerequisites

- Anthropic API key stored as a GitHub Actions secret (`ANTHROPIC_API_KEY`)
- Repository with GitHub Actions enabled

### Basic Configuration

```yaml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

## Use Cases

### 1. Automated PR Code Review

Post review comments on pull requests with findings, suggestions, and potential issues:

```yaml
name: PR Review

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  contents: read
  pull-requests: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Review this PR. Focus on:
            - Security issues (injection, auth bypass, secrets exposure)
            - Logic errors and edge cases
            - Missing error handling
            - Breaking API changes without migration path

            Be specific. Reference file paths and line numbers.
            Only flag real issues — false positives waste reviewer time.
```

### 2. Issue Triage and Labeling

Automatically categorize and label new issues:

```yaml
name: Issue Triage

on:
  issues:
    types: [opened]

permissions:
  issues: write

jobs:
  triage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Analyze this issue and suggest:
            1. Labels (bug, feature, docs, infra, security)
            2. Priority (P0-critical, P1-high, P2-medium, P3-low)
            3. Which team/area of the codebase is affected

            Base your analysis on the issue title, body, and the
            repository structure.
```

### 3. PR Description Generation

Auto-generate PR descriptions from the diff:

```yaml
name: PR Description

on:
  pull_request:
    types: [opened]

permissions:
  pull-requests: write

jobs:
  describe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Generate a PR description based on the diff. Include:
            - Summary of changes (2-3 bullets)
            - Files changed and why
            - Testing considerations
            - Breaking changes (if any)

            Keep it concise. Developers will read this in a review queue.
```

### 4. Commit Message Validation

Check commit messages against conventions:

```yaml
name: Commit Lint

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  pull-requests: write

jobs:
  lint-commits:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Check all commits in this PR against conventional commit format:
            type(scope): description

            Valid types: feat, fix, docs, style, refactor, test, chore, ci
            Flag any commits that don't match. Suggest corrections.
```

### 5. Documentation Freshness Check

Verify docs match code changes:

```yaml
name: Docs Check

on:
  pull_request:
    paths:
      - "src/**"
      - "docs/**"
      - "README.md"

permissions:
  pull-requests: write

jobs:
  docs-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            This PR changes source code. Check if any documentation
            needs updating:
            - README.md
            - API docs
            - Configuration examples
            - Architecture diagrams referenced in docs

            Only flag documentation that is now factually wrong due
            to the code changes. Don't flag style or wording preferences.
```

## Configuration Options

| Input | Description | Required |
|-------|-------------|----------|
| `anthropic_api_key` | Anthropic API key | Yes |
| `prompt` | Instructions for Claude | Yes |
| `model` | Model to use (default: `claude-sonnet-4-6`) | No |
| `max_tokens` | Maximum response tokens | No |
| `allowed_tools` | Tools Claude can use | No |

## Best Practices

### Prompt Design for CI/CD

- Be specific about what to check — vague prompts produce vague results
- Include the failure mode: "Flag X because Y can happen" is better than "Check for X"
- Tell Claude what NOT to flag — reduces noise from false positives
- Reference your project's conventions: "We use conventional commits" or "We follow the error handling pattern in `src/utils/errors.ts`"

### Cost Management

- Use `claude-sonnet-4-6` for routine tasks (review, triage) — it's cheaper and fast
- Reserve `claude-opus-4-6` for complex analysis (architecture review, security audit)
- Use path filters in workflow triggers to avoid running on irrelevant changes
- Set `max_tokens` to limit response size

### Security

- Store the API key as a GitHub Actions secret, never in workflow files
- Use minimal `permissions` — only grant what the workflow needs
- Review Claude's suggestions before merging — automated review augments human review, it doesn't replace it

## Combining with Existing Workflows

Claude Code Action works alongside your existing CI/CD. A common pattern:

```yaml
jobs:
  test:
    # Your existing test job
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test

  review:
    # Claude reviews in parallel with tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: "Review this PR for security and correctness issues."
```

## Related Resources

- [GitHub Actions Patterns](../workflows/github-actions.md) — General GHA development protocol
- [CI/CD Patterns](../workflows/ci-cd-patterns.md) — Deployment strategies and pipeline design
- [PR Review Protocol](pr-review-protocol.md) — Structured review methodology
- [Best Practices](claude-best-practices.md) — Headless mode and automation patterns
