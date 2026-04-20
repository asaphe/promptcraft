# Doc Quality and Review Guide

Documentation in `.claude/` has a unique failure mode: it's auto-loaded into every session, so stale content actively misleads rather than passively gathering dust. This guide covers patterns for keeping docs accurate and detecting staleness before it causes incidents.

## The Staleness Problem

Docs go stale because they're written during implementation — when the author has full context — and rarely revisited after. The most common offenders:

- **Ticket IDs** (DEV-1234) — meaningless after the ticket is closed
- **Dates and temporal phrases** ("as of March 2025", "currently", "recently") — become wrong silently
- **Hardcoded entity lists** (tenant lists, app lists, module counts) — drift as the system evolves
- **Instance-specific identifiers** (ARNs, account IDs, resource names) — change on infrastructure updates
- **Copied tables** from code that duplicate a source of truth without linking to it

## Staleness Scan Protocol

Before committing or reviewing any `.claude/` doc change, run through this checklist:

| Check | What to look for | Fix |
|-------|-----------------|-----|
| Temporal references | Dates, "as of", "currently", "recently", ticket IDs | Remove — use `git log`/`git blame` for history |
| Entity lists | Hardcoded lists of apps, tenants, modules, rules | Reference the authoritative source by path |
| Instance identifiers | ARNs, account IDs, cluster names, resource names | Remove from shared docs or reference the config source |
| Hardcoded counts | "14 agents", "67 rules", "~40 modules" | Remove or say "see X for current list" |
| File path references | Paths to other docs, code, or config | Verify each path exists (`test -f <path>`) |
| Code references | Function names, class names, CLI flags | Grep the codebase to verify they still exist |
| Factual claims | "WAF blocks bodies > 8KB", "ESO syncs every 30m" | Re-verify against current code or infrastructure |
| Personal/sensitive paths | Home directories, Google Drive, 1Password URIs | Remove from shared docs |

### Automated reference validation

Check all backtick-quoted file paths in `.claude/` docs against the filesystem:

```bash
find .claude/ -name '*.md' -exec grep -oE '`[a-zA-Z0-9_./ -]+\.(md|sh|py|ts|json)`' {} + \
  | tr -d '`' | sort -u | while read -r ref; do
    echo "$ref" | grep -qF '/' || continue  # skip bare filenames
    [ ! -f "$ref" ] && echo "MISSING: $ref"
  done
```

## Poka-Yoke Checklists

Pre-commit checklists that make staleness structurally harder to introduce.

### For doc authors

Before committing a new or modified doc:

- [ ] No temporal references (dates, ticket IDs, "currently")
- [ ] All file paths verified with `test -f` or `ls`
- [ ] Entity lists derived from authoritative source (or marked as snapshot with source path)
- [ ] Descriptions reflect deployed state, not vendor default behavior
- [ ] No instance-specific identifiers in shared docs
- [ ] No personal paths (home directories, cloud storage)

### For doc reviewers

During PR review of `.claude/` doc changes:

- [ ] New docs have pointers in CLAUDE.md on-demand reference section
- [ ] Section titles describe content, not context ("Exempted paths" not "Exempted paths (DEV-1234)")
- [ ] Updated docs: diff covers all changed facts, not just the reported issue
- [ ] Removed features: docs referencing them are updated or removed
- [ ] Cross-references: if doc A links to doc B, verify B still says what A claims
- [ ] Duplicated content has "Authoritative source:" pointer

## Anti-Staleness Patterns

Structural approaches that resist decay over time:

1. **Prefer pointers over copies** — Reference authoritative sources by path rather than duplicating tables or lists that will drift. When duplication is unavoidable, mark the source explicitly.

2. **Use git for temporal context** — Instead of inline dates ("added March 2025"), use `git log`/`git blame` to trace when and why content was added. Commit messages carry the context; docs carry the content.

3. **Derive lists from authoritative sources** — Tenant lists, app lists, and module inventories should come from APIs, config files, or runtime queries — not hardcoded enumerations in docs.

4. **Mark snapshots explicitly** — When a doc must contain a point-in-time snapshot (e.g., a comparison table), include: "Authoritative source: `path/to/file`. Verify before relying on this table."

5. **Use conditional loading** — Docs in `.claude/docs/` load on demand and are less damaging when stale than always-loaded rules in `.claude/rules/`. If content doesn't need to be in every session, move it to an on-demand reference.

6. **Lead with positive guidance in persistent docs** — "Describe deployed state" is clearer than "Don't describe defaults." Positive framing survives context pressure better.

## Measuring Doc Health

Periodic indicators that your docs need attention:

- **Stale doc count**: Files in `.claude/docs/` not modified in 6+ months are candidates for audit. Check with `git log --format='%ai' -1 <file>`.
- **Broken references**: Run the automated validation script above before each release or quarterly.
- **Incident-driven staleness**: After each incident, check if any doc contributed to a wrong conclusion. Update immediately — don't defer.
- **Review finding rate**: If doc review findings are consistently about staleness (not accuracy), the authoring checklists aren't being followed.

## Related Resources

- [Operational Rules Guide](../templates/rules/operational-rules-guide.md) — Rule deprecation and auditing
- [Learning System Guide](learning-system-guide.md) — Session mining for doc gaps
- [PII Prevention Guide](pii-prevention-guide.md) — Preventing sensitive data in docs
- [Global CLAUDE.md Guide](global-claude-md-guide.md) — On-demand reference design
