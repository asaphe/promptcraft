# PII Prevention Guide

How to prevent sensitive data leakage when working on public or shared repositories.

## What Leaks

Data that identifies your infrastructure, organization, or individuals:

| Category | Examples | Risk |
|----------|----------|------|
| **Cloud resource IDs** | `vpc-0abc123...`, `sg-038bad...`, `i-0abc...` | Reveals infrastructure topology |
| **Account IDs** | AWS 12-digit accounts, Azure subscription GUIDs | Enables targeted attacks |
| **Zone/Hosted IDs** | Route53 `Z0247406X...`, CloudFlare zone IDs | DNS enumeration |
| **UUIDs** | Databricks account, API keys, correlation IDs | Service identification |
| **Org/repo names** | `my-company/internal-service` | Reveals private repos |
| **Domain names** | `internal.example.co`, `admin.company.com` | Internal service discovery |
| **User paths** | `/Users/johndoe/...`, `/home/deploy/...` | Username enumeration |
| **Credential references** | `op://Vault/Item`, `1password.com` account URLs | Credential vault targeting |
| **Internal ticket IDs** | `DEV-1234`, workspace IDs, user IDs | Internal tracking exposure |
| **IP ranges / CIDRs** | `10.60.0.0/16`, private subnets | Network topology |

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

```bash
git diff | grep -iE '(company-name|internal-domain|username|account-id-pattern)' || echo "clean"
```

Build a project-specific pattern covering your sensitive identifiers:

```bash
git diff | grep -iE '(mycompany|mycompany\.com|johndoe|123456789012|vpc-0|sg-0|internal\.example)' || echo "clean"
```

### Staged files scan

```bash
git diff --staged | grep -iE '<pattern>' || echo "clean"
```

### PR body / issue text

Before posting, search your draft text for the same patterns. Pay special attention to:

- Example commands you copied from real sessions
- Error messages that contain paths or IDs
- Reproduction steps with real resource names

### Test fixtures

```bash
grep -rE '<pattern>' tests/fixtures/ || echo "clean"
```

## Sanitization Patterns

When you need to include examples that originally contained sensitive data, replace with generic placeholders:

| Original | Replacement |
|----------|------------|
| `vpc-0abc123def456789a` | `vpc-<ID>` |
| `123456789012` (account) | `<ACCOUNT_ID>` |
| `Z0247406X6CI60Z1JQ2` | `Z<ZONE_ID>` |
| `292bf5a3-e432-483f-b14d-949b412ea11a` | `<UUID>` |
| `/Users/johndoe/projects/...` | `~/projects/...` |
| `my-company/internal-service` | `<org>/<repo>` |
| `company.1password.com` | `<vault-host>` |
| `DEV-1234` | `TICKET-1234` |
| `10.60.0.0/16` | `10.x.x.x/16` |

## Automated Protection

### Git hooks

Add a pre-commit hook that scans for your known patterns:

```bash
#!/bin/bash
if git diff --staged | grep -qiE '(mycompany|johndoe|123456789012)'; then
  echo "ERROR: Staged changes contain sensitive data"
  git diff --staged | grep -niE '(mycompany|johndoe|123456789012)'
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

When building tools that generate output files (like CLI correction rules), sanitize by default and provide a `--no-sanitize` flag for debugging. Users should never need to remember to sanitize — the safe default protects them.

## Recovery

If sensitive data is pushed to a public repo:

1. **Don't just add a cleanup commit** — The data is in git history forever
2. **Rewrite history immediately:**

   ```bash
   git filter-repo --replace-text <(echo 'sensitive-string==>REDACTED')
   git push --force-with-lease
   ```

3. **Rotate any exposed credentials** — Assume they're compromised
4. **Check CI artifacts** — Build logs, test outputs may also contain the data

## PR Description Hygiene

Things that should NEVER appear in a PR body on a public repo:

- "No PII or company-specific data in any new/changed content" — This checkbox reveals you're sanitizing from a private source
- Real infrastructure IDs, even in "before" examples
- Internal repo paths or URLs
- References to specific company accounts or vaults
- Employee names or usernames

Instead, use generic examples and let the code speak for itself.

## Related Resources

- [Public Contribution Guide](public-contribution-guide.md) — Full contribution workflow
- [Issue Writing Guide](issue-writing-guide.md) — Structuring issues without leaking data
