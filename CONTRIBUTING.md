# Contributing to Promptcraft

Thank you for considering a contribution. This repository is a living collection of AI assistant rules, standards, and prompts — battle-tested patterns from real-world development and DevOps work.

## How to Contribute

### Reporting Issues

- Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) for broken links, incorrect information, or formatting issues
- Use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md) for new patterns, guides, or improvements

### Submitting Changes

1. Fork the repository
2. Create a branch: `feature/short-description` or `fix/short-description`
3. Make your changes
4. Run `markdownlint .` to check formatting (see `.markdownlint.yaml` for config)
5. Submit a pull request using the [PR template](.github/PULL_REQUEST_TEMPLATE.md)

### What Makes a Good Contribution

- **Battle-tested patterns** — Rules and patterns that come from real production experience, not theoretical best practices
- **Concrete examples** — Show input/output pairs, before/after comparisons, or working configurations
- **Tool-agnostic core, tool-specific extensions** — Core principles go in `core/`, tool-specific guidance goes in `claude/`, `cursor/`, `chatgpt/`, etc.
- **Concise and actionable** — Every sentence should help the reader do something. Cut preamble and filler.

### What to Avoid

- Marketing language or hyperbole ("revolutionary", "game-changing")
- Patterns that only work in narrow contexts without stating the constraints
- Duplicating content that already exists — extend or link instead
- PII, company-specific details, or credentials in any form

## Style Guide

- Use GitHub-flavored markdown
- Use tables for structured comparisons (more scannable than prose)
- Use code blocks with language tags for all code examples
- Keep headings hierarchical (no skipping levels)
- Run `markdownlint .` before submitting — CI enforces it

## Code of Conduct

Be respectful, constructive, and focused on making the repository better. Disagreements about patterns are welcome — frame them as trade-offs, not absolutes.

## License

By contributing, you agree that your contributions will be licensed under [CC BY 4.0](LICENSE).
