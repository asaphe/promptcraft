# PII & Public Repo Discipline

- **Zero PII tolerance** — Never include personal names, email addresses, company names, internal service names, workspace/account IDs, or token prefixes in any file.

- **Scan before commit** — Before every commit, grep the diff for: company names, personal identifiers, internal URLs, API keys, account IDs.

- **Scan every name variant** — Old and new names, snake_case, camelCase, kebab-case, and abbreviations. One spelling misses the rest.

- **Report findings before fixing** — Show each match and where it is before removing anything. Never auto-fix what hasn't been shown.

- **A leak in history needs a rewrite** — A fix commit on top leaves the data in history. Rewrite it (`git filter-repo`) and force-push, with approval (see `git-discipline.md`). PR bodies and comments are outside any history rewrite — edit them separately.

- **Go file by file** — Verify each file right after editing it. Don't batch large changes without per-file review.

- **Generalize, don't just delete** — Replace specifics with realistic placeholders (`your-org`, `service-name`) so the example keeps its substance.

- **PR descriptions describe the change** — Titles, bodies, and commit messages say what the content adds and why. They don't narrate the hygiene steps behind it.

- **No internal references** — Never reference internal repos, services, infrastructure, or tooling. This is a standalone public project.

- **PR-only workflow** — All changes go through PRs. Never push directly to main.
