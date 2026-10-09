# Contributing to Promptcraft

Thank you for considering a contribution. This repository is a living collection of AI assistant rules, standards, and prompts — battle-tested patterns from real-world development and DevOps work.

## How to Contribute

### Reporting Issues

- Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) for broken links, incorrect information, or formatting issues
- Use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md) for new patterns, guides, or improvements

### Submitting Changes

1. Fork the repository
2. Create a branch: `feat/short-description`, `fix/short-description`, or `docs/short-description`
3. Make your changes
4. Run `markdownlint .` to check formatting (see `.markdownlint.yaml` for config)
5. Submit a pull request using the [PR template](.github/PULL_REQUEST_TEMPLATE.md)

### What Makes a Good Contribution

- **Battle-tested patterns** — Rules and patterns that come from real production experience, not theoretical best practices
- **Concrete examples** — Show input/output pairs, before/after comparisons, or working configurations
- **Tool-agnostic core, tool-specific extensions** — Universal principles, language standards, and infrastructure patterns go under `shared/` (e.g., `shared/principles/`, `shared/languages/`, `shared/infrastructure/`); tool-specific adaptations go under `tools/<tool>/` (`tools/claude/`, `tools/cursor/`, `tools/chatgpt/`).
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

## Adoption and Markdown coverage checks

Run these from the repository root after changing copy routes, dependencies, or lint inputs:

```bash
python3 .claude/scripts/check-adoption.py
python3 .claude/scripts/test-check-adoption.py
python3 .claude/scripts/test-markdownlint-inputs.py
python3 .claude/scripts/markdownlint-inputs.py
markdownlint -c .markdownlint.yaml '**/*.md'
```

The local markdownlint command remains available. CI instead uses `git ls-files -z` to select tracked `.md` and `.markdown` files, including hidden directories, minus the nine exact paths in `.markdownlintignore`. The generator emits `:path` literal inputs directly to the pinned CLI2 action; it does not use shell-expanded globs. Newly created files enter this corpus when tracked. Keep the exclusions unchanged unless a separate decision approves a format or scope change.

The adoption checker executes only the four delimited copy/setup snippets from ADOPTION in temporary homes/projects, without settings registration, model invocation, network calls, or cloud tools. Temporary HOME provides test isolation, not a security sandbox; snippets are reviewed repository code. Local Markdown links in copied artifacts and the manifest's optional public source links are checked locally against repository targets. Optional companions remain public browsing references, not additional installed dependencies.

## Code of Conduct

Be respectful, constructive, and focused on making the repository better. Disagreements about patterns are welcome — frame them as trade-offs, not absolutes.

## License

By contributing, you agree that your contributions will be licensed under [CC BY 4.0](LICENSE).
