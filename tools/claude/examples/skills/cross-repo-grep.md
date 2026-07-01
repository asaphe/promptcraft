---
name: cross-repo-grep
description: Fetch and quote lines from another repo in your org at main without cloning or checking out. Use to verify cross-repo claims (e.g., "PR #N in repo X says file F says Z"). Usage - /cross-repo-grep <repo> <path> [pattern]
user-invocable: true
allowed-tools: Bash(gh api repos/<org>/* *), Bash(jq *), Bash(grep *), Bash(base64 *)
argument-hint: "<repo> <path> [pattern]"
---

# cross-repo-grep

Fetch a file from another repo in your org at `main` and (optionally) grep it. Authoritative source is `gh api repos/<org>/<repo>/contents/<path>?ref=main` — never local clone state, which can be stale or wrong-branch.

## Why this exists

PR descriptions are claims, not evidence. Local clones can be on feature branches, dirty, or stale. When a finding depends on the current `main` of *another* repo, fetch the actual file before asserting.

## Steps

### 1. Parse arguments

Expected: `<repo> <path> [pattern]` where:

- `<repo>` is the name of one of your org's repos.
- `<path>` is the in-repo path (no leading slash).
- `[pattern]` is optional — if absent, quote the first ~40 lines; if present, grep for it and quote ±3 lines.

If `<repo>` or `<path>` is missing, ask the user.

### 2. Fetch the file

```bash
REPO="<org>/<repo>"
PATH_IN_REPO="<path>"
gh api "repos/${REPO}/contents/${PATH_IN_REPO}?ref=main" \
  --jq '.content' \
  | base64 -d \
  > /tmp/cross-repo-grep-fetch.txt
```

Failure modes:

- `404` — path doesn't exist on `main` of that repo. Report verbatim; offer to try a different branch via `--ref <branch>`.
- `403` — gh auth scope missing repo:read. Surface to user.

### 3. Quote what matters

Without a pattern:

```bash
head -40 /tmp/cross-repo-grep-fetch.txt
```

With a pattern:

```bash
grep -n -C 3 -E '<pattern>' /tmp/cross-repo-grep-fetch.txt || echo "no match for <pattern> in <repo>/<path>@main"
```

### 4. Report

Include in the response:

1. Full GitHub URL: `https://github.com/<org>/<repo>/blob/main/<path>`
2. Verbatim quoted lines (with line numbers from grep -n) — never paraphrased.
3. One-line conclusion about the claim being verified.

## Counter-indications

- Do not use to fetch large generated files (lockfiles, dist/, .terraform/) — gh api returns base64 with a size cap, and the noise drowns the signal.
- Do not use when local clone is on `main` AND known-clean for the target file — `Read` is cheaper. The discriminator: are you about to make a claim about *another* clone's main, or your own? If "another", use this.
- Do not use to fetch entire directories — gh api contents returns a JSON listing, not concatenated content.
