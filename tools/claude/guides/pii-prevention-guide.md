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

### Prefer a scanner over hand-built greps

Hand-rolled patterns are fine for names and internal strings you invented, which no general tool can know about. They are a poor primary defense for credentials, which have known shapes. Use a dedicated scanner for those and keep your grep for the rest — [redacto](https://github.com/asaphe/redacto) is one such tool:

```bash
redacto --patterns all --live-window-secs 0 <paths…>
```

Two behaviors will silently defeat you if you don't know them, and they generalize to most scanners of this kind:

- **It exits 0 even when it finds matches.** Never chain on its exit code — `redacto … && git commit` commits the secret. Read the report, or grep the report for a match count. Verified: a file containing a known-matching identifier returns exit `0`.
- **A freshness window can skip just-modified files.** That default exists to avoid rescanning a whole tree, and it excludes exactly the files a commit flow cares about. `--live-window-secs 0` disables it. Re-scanning a file you did *not* just modify needs a fresh `--state-dir` too, or a stored watermark answers instead of the file.

**Append a known-positive control to the same invocation.** A clean report and a scan that never ran look identical. Put a throwaway file containing a string the scanner must match at the end of the file list; if the control does not appear in the output, the run proved nothing about your real files:

```bash
printf 'vpc-0a1b2c3d4e5f67890\n' > /tmp/control.md
redacto --patterns all --live-window-secs 0 <your paths…> /tmp/control.md
# The control MUST appear in the output. If it doesn't, the scan didn't run as written.
```

Match the control to the pattern class you are testing — a credential-shaped probe proves nothing about a scan restricted to infrastructure identifiers, and vice versa.

### Git diff scan

Use the pattern you built in step 1:

```bash
git diff | grep -iE '<your-pattern>' || echo "clean"
```

**That `|| echo "clean"` is lying to you if the diff was empty.** `grep` exits non-zero both when the input contained no match and when there was no input at all — wrong directory, everything already committed, or a wrapper that filtered the diff before `grep` saw it. All three print `clean`. Check that the input is non-empty before believing the result:

```bash
git diff > /tmp/scan.txt
[ -s /tmp/scan.txt ] || echo "WARNING: empty diff — this scan proves nothing"
grep -icE '<your-pattern>' /tmp/scan.txt
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

**Rotate first, and treat the credential as compromised from the moment it was pushed.** Everything below is damage limitation; only rotation actually ends the exposure. Do not let a history rewrite delay it, and do not let a successful rewrite convince you rotation is now optional.

1. **Rotate every exposed credential.** Assume it was scraped. Public-repo secret scanners are fast, and the window between push and rotation is the whole risk.
2. **Don't just add a cleanup commit** — the data remains in git history.
3. **Rewrite history**, understanding that this is incomplete:

   ```bash
   git filter-repo --replace-text <(echo 'sensitive-string==>REDACTED')
   git push --force-with-lease
   ```

4. **Know what the rewrite does not reach.** A force-push rewrites the branch. It does not purge the forge's hidden pull-request refs (`refs/pull/N/head`), and it does not remove orphaned commits that remain fetchable by SHA. Anyone who knows or guesses the SHA — and anyone who forked, or whose CI cached the object — can still retrieve the content. A green `filter-repo` run and a clean `git log` are not evidence the data is gone.
5. **Pick the remedy that matches the repo's age.** For a young repo with no forks and no external contributors, delete-and-recreate is the only certain remedy and is usually cheaper than it sounds. For anything with history worth keeping, you need the forge provider's support team to garbage-collect the unreachable objects — open that request rather than assuming the push settled it.
6. **Check CI artifacts** — build logs, test outputs, and cached workspaces may hold the value independently of git history, and they have their own retention.

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
