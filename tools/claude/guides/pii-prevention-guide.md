# PII Prevention Guide

How to prevent sensitive data leakage when working on public or shared repositories.

## Define Your Boundary First

Every team has different sensitive data. Before scanning, you need to know what YOUR sensitive patterns are. The process:

1. **List your identifiers** — What names, IDs, domains, and paths would reveal your organization or infrastructure if found in a public repo?
2. **Build a grep pattern** — Combine them into a single regex you can run against any diff.
3. **Store it somewhere durable** — Your global `~/.claude/CLAUDE.md`, a git hook, or a shell alias. If it's not automated, it won't happen consistently.

### How to discover your sensitive patterns

Run through this checklist for your environment:

| Question | What to add to your pattern |
|----------|---------------------------|
| What's your company/org name? | Company name, domain, GitHub org |
| What cloud provider(s)? | Resource ID prefixes (AWS: `vpc-`, `sg-`, `i-`; GCP: `projects/`; Azure: `/subscriptions/`) |
| What account/project IDs do you use? | AWS account numbers, GCP project IDs, Azure subscription GUIDs |
| What usernames appear in paths? | `/Users/<name>/`, `/home/<name>/` |
| What internal domains exist? | `internal.company.com`, `admin.company.com` |
| What credential managers? | 1Password vault URLs, Vault paths, AWS SSM prefixes |
| What project management tool? | Ticket prefixes (`JIRA-`, `LINEAR-`), workspace IDs |
| What internal service names? | Names that would reveal architecture if public |

The result is a project-specific pattern like:

```bash
grep -iE '(mycompany|mycompany\.com|johndoe|internal\.example)' || echo "clean"
```

## What Leaks

Common categories across most organizations:

| Category | Risk | Examples |
|----------|------|----------|
| **Organization names** | Reveals who you are | Company name in URLs, repos, domains |
| **Cloud resource IDs** | Infrastructure topology | AWS `vpc-*`/`sg-*`/`i-*`, GCP `projects/*`, Azure `subscriptions/*` |
| **Account identifiers** | Targeted attacks | AWS 12-digit accounts, GCP project IDs, Azure subscription GUIDs |
| **DNS identifiers** | DNS enumeration | Route53 zone IDs, CloudFlare zone IDs, custom domains |
| **UUIDs** | Service identification | API keys, account IDs, correlation IDs in any platform |
| **User paths** | Username enumeration | `/Users/name/`, `/home/name/`, `C:\Users\name\` |
| **Credential references** | Vault targeting | 1Password URIs, HashiCorp Vault paths, AWS SSM paths |
| **Internal ticket IDs** | Internal tracking exposure | `JIRA-1234`, `LINEAR-ABC`, workspace/user IDs |
| **IP ranges** | Network topology | Private CIDRs, VPN ranges, internal subnets |
| **Internal domains** | Service discovery | Internal APIs, admin panels, monitoring dashboards |

## When to Scan

Scan at every boundary where content crosses from private to public:

1. **Before every `git add`** — Scan the diff
2. **Before creating a PR** — Scan the PR body text
3. **Before opening an issue** — Scan example commands and reproduction steps
4. **Before posting comments** — Scan inline code and error outputs
5. **After writing test fixtures** — Scan fixture files for real data
6. **After context continuation** — Re-scan; stale context may contain sensitive data you've forgotten about

## How to Scan

### Git diff scan

Use the pattern you built in step 1:

```bash
git diff | grep -iE '<your-pattern>' || echo "clean"
```

### Staged files scan

```bash
git diff --staged | grep -iE '<your-pattern>' || echo "clean"
```

### PR body / issue text

Before posting, search your draft text for the same patterns. Pay special attention to:

- Example commands you copied from real sessions
- Error messages that contain paths or IDs
- Reproduction steps with real resource names

### Test fixtures

```bash
grep -rE '<your-pattern>' tests/fixtures/ || echo "clean"
```

## Sanitization Patterns

When including examples that originally contained sensitive data, replace with generic placeholders. Choose placeholders that are obviously not real:

| Type | Original | Replacement |
|------|----------|------------|
| Cloud resource | `vpc-0abc123def456789a` | `vpc-<ID>` |
| Account | `123456789012` | `<ACCOUNT_ID>` |
| UUID | `292bf5a3-e432-483f-...` | `<UUID>` |
| User path | `/Users/johndoe/...` | `~/...` |
| Org/repo | `my-company/my-service` | `<org>/<repo>` |
| Domain | `admin.company.com` | `internal.example.com` |
| Ticket | `JIRA-1234` | `TICKET-1234` |
| CIDR | `10.60.0.0/16` | `10.x.x.x/16` |

## Automated Protection

### Git hooks

Add a pre-commit hook that scans for your known patterns:

```bash
#!/bin/bash
PATTERN='(mycompany|johndoe|internal\.example)'  # <-- customize this
if git diff --staged | grep -qiE "$PATTERN"; then
  echo "ERROR: Staged changes may contain sensitive data"
  git diff --staged | grep -niE "$PATTERN"
  exit 1
fi
```

### Claude Code rules

Add to your global `~/.claude/CLAUDE.md`:

```markdown
## Privacy

Before committing to any public or shared repo, scan the staged diff for:
company names, personal names/usernames, internal service names,
workspace/account IDs, email addresses, and token prefixes.
```

### Build-time sanitization

When building tools that generate output files (reports, rules, logs), sanitize by default and provide a `--no-sanitize` flag for debugging. Users should never need to remember to sanitize — the safe default protects them.

## Recovery

If sensitive data is pushed to a public repo:

1. **Don't just add a cleanup commit** — The data remains in git history
2. **Rewrite history immediately:**

   ```bash
   git filter-repo --replace-text <(echo 'sensitive-string==>REDACTED')
   git push --force-with-lease
   ```

3. **Rotate any exposed credentials** — Assume they're compromised
4. **Check CI artifacts** — Build logs, test outputs may also contain the data

## PR Description Hygiene

Things that should NEVER appear in a PR body on a public repo:

- Checkboxes about PII scanning — this reveals you're sanitizing from a private source
- Real infrastructure IDs, even in "before" examples
- Internal repo paths or URLs
- References to specific company accounts or vaults
- Employee names or usernames

Instead, use generic examples and let the code speak for itself.

## Related Resources

- [Public Contribution Guide](public-contribution-guide.md) — Full contribution workflow
- [Issue Writing Guide](issue-writing-guide.md) — Structuring issues without leaking data
