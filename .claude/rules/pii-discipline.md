# PII & Public Repo Discipline

- **Zero PII tolerance** — Never include personal names, email addresses, company names, internal service names, workspace/account IDs, or token prefixes in any file.

- **Scan before commit** — Before every commit, grep the diff for: company names, personal identifiers, internal URLs, API keys, account IDs.

- **No internal references** — Never reference internal repos, services, infrastructure, or tooling. This is a standalone public project.

- **PR-only workflow** — All changes go through PRs. Never push directly to main.
