# PR Review Verification Checklist

Mandatory verification steps by finding type. Every finding must include an **Evidence** block showing what was checked and what was found. Findings without evidence are dropped before presentation.

This file is a kernel: the verification rules here apply to every reviewer agent. Per-repo overlays may add domain-specific verification rows that extend it (e.g. a `pr-review-verification.md` next to this file in a downstream repo). Keep the kernel and its overlays in sync; byte-equality is a convention until a CI drift check lands.

## Evidence Block Format

```markdown
**Evidence:**
- Checked: {what was queried/read/grepped}
- System has: {actual result from the real system}
- PR claims: {what the PR has or claims}
- Conclusion: {why this is a finding}
```

## Verification by Finding Type

**Tool scope:** Not all reviewer agents have the same tools. Infrastructure verifications (e.g. `kubectl`, `terraform`, `aws`, `helm`) are only available to agents explicitly scoped to them. If a verification requires tools you don't have, use code-level alternatives (read tfvars, grep config files, check sibling patterns) rather than skipping verification entirely.

### "Wrong value" (version, name, path, ID)

Query the real system for the actual value. Never flag a value as wrong based on memory alone.

| Domain | How to verify | Available to |
|--------|---------------|--------------|
| Branch name | `git branch -a` or `gh pr view --json headRefName` | all agents |
| Config value | Read the tfvars/values file AND the consumer code | all agents |

**Code-level alternatives** when you lack infrastructure tool access: read the tfvars/values files directly, check sibling config files for the expected pattern, or grep deployment manifests for the value in question.

### "Missing X" (file, field, config, import, test)

Grep the codebase AND check 3+ sibling files for the pattern before claiming something is missing.

- Search for the thing claimed missing (use the Grep tool, not bash grep)
- Check sibling files: if 3+ similar files also lack it, it's the norm — downgrade to SUGGESTION
- For missing tests: check `**/test*` directories for coverage of the changed function
- For missing config: check if a default exists upstream (provider default, helm chart default, env fallback)

### "Security issue" (injection, auth bypass, privilege escalation)

Must show a concrete attack vector or reference a specific CVE/OWASP category.

- Trace the data flow: where does user input enter? Does it reach the dangerous sink unsanitized?
- For dependency vulnerabilities: verify the version is actually affected (check advisory, not just "old version")

### "Doesn't match config/spec" (mismatch between code and config)

Read BOTH sides and show the comparison.

- Read the config/spec file cited
- Read the code being flagged
- Show the specific values from each
- If referencing the project spec: quote the exact rule

### "Pre-existing issue" (bug in changed file, not introduced by PR)

Still report — downgrade severity but never drop.

- Verify it's genuinely pre-existing: `git log --oneline -1 -- <file>` or `git blame <file> -L <line>`
- Classify as ISSUE (not BLOCKING) with note: "Pre-existing — not introduced by this PR"
- If the pre-existing issue blocks the PR from merging (e.g., CI failure), escalate to BLOCKING

### "Dead code" (unused function, unreachable branch, stale config)

Grep ALL consumers before claiming code is dead.

- Search for the name across all consumers (use the Grep tool with appropriate type filters)
- Check for dynamic references: string-based lookups, reflection, config-driven dispatch, variable interpolation
- Check for external consumers: other repos, CI workflows, scripts
- If zero hits: evidence is the grep command and "0 results"

### "Pattern violation" (naming, style, convention)

Check established convention before flagging.

- Search for the pattern across 3+ sibling files in the same directory/module
- If the "violation" IS the convention (majority of files do it this way): drop finding or downgrade to SUGGESTION with migration note
- If the project spec mandates the pattern: cite the spec rule, classify per spec authority

### "CI step will fail at runtime" (import error, missing tool, wrong venv)

Trace the full runtime chain — file existence is not enough.

**`set -euo pipefail` silent exit:** When reviewing shell scripts or GHA `run:` blocks, check whether `set -e` is active (explicit or via GHA default `bash -e {0}`). If a command that can fail (e.g. `make`, `npm`, `poetry run`) runs *before* the error-handling code in the same block, `set -e` kills the script immediately and the error message never prints. Verify that every error-handling or annotation line is actually reachable when the preceding command fails. Fix: capture the exit code explicitly with `if ! cmd; then echo "::error::..."; exit 1; fi` — `cmd || true` makes the combined expression exit 0 and CI stays green, swallowing the failure.

**GHA `::error::` annotation reachability:** A `::error::` annotation on the line after a failing command is silently lost — `bash -eo pipefail` exits before it executes. Check that `::error::` lines are inside an error-handling branch (e.g. `if ! cmd; then echo "::error::..."; fi`) rather than sequentially after the command they annotate.

- For language imports: file on disk → declared in the package manifest (`pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, etc.) → installed in the step's environment → on the module search path → importable. Check which `working-directory` and setup step the command inherits — a package installed in a subdirectory is not importable from a parent directory
- For shell commands: binary exists → on `PATH` in the runner → correct version → correct flags
- For `working-directory` overrides: verify the environment/toolchain in that directory has what the step needs. A prior step that generates files does not make them importable — generation ≠ installation
- Read the package manifest that the setup step actually installs — a prior step's success does not guarantee the tool/package is available in the current step's environment

| Check | How to verify | Available to |
|-------|---------------|--------------|
| Language import resolves | Read the package manifest the setup step installs; check if target is a declared dependency or workspace member | all agents |
| Shell tool available | Check runner image or setup step for the tool | all agents |
| Env var set | Trace `env:` blocks at job and step level — step-level overrides job-level | all agents |
| Working directory correct | Check `defaults.run.working-directory` AND step-level `working-directory` | all agents |

### "Trigger condition doesn't match real dependency" (workflow `if` gates on wrong filter)

When a job gates on a path filter, trace the full dependency chain.

- Read the job's steps to identify what it actually validates (which specs, which scripts, which output files)
- For each path filter in the `if` condition: trace whether changes to those paths actually affect the validated artifacts
- Follow imports in the code the job runs — don't infer from package names or directory proximity
- If a path filter is missing (changes to X affect the job's output but X isn't in the trigger): flag as a gap
- If a path filter is present but has no dependency path to the job's output: flag as misplaced
- **Path filter specificity:** When a `paths:` trigger or pre-commit grep covers a broad directory (e.g. `src/**`), check whether it fires on non-source files (README, manifest files, config). A glob that triggers expensive operations (dependency resolution, code generation, full rebuilds) on non-functional file changes should be tightened to the relevant source extension (`**/*.py`, `**/*.ts`, `**/*.tf`, etc.).

### "New enforcement workflow not wired as required status check"

When a PR adds a new CI enforcement workflow (schema validation, drift detection, coverage gate), verify it's wired as a required status check in branch protection. A workflow that isn't required can be ignored on merge — it's informational, not enforcement. Flag if missing.

Check both classic branch protection and rulesets:

```bash
# Classic format (contexts and newer checks entries)
gh api repos/{org}/{repo}/branches/main/protection \
  --jq '(.required_status_checks.contexts[]?), (.required_status_checks.checks[].context?)' 2>/dev/null

# Ruleset-based enforcement (newer GitHub feature)
gh api repos/{org}/{repo}/rulesets \
  --jq '.[] | select(.enforcement == "active") | .name' 2>/dev/null
```

If both return empty for the new workflow's job name, it is advisory-only.

### "Content dropped or missing from a modified file" (stale-branch false positive)

Before claiming that content was removed from a file — a field dropped from config, a rule deleted, an entry missing — verify whether that content existed at the **merge base** of this branch and `main`.

**Why**: When a branch is stale (created before recent main changes), files at branch HEAD may be missing content that was added to main *after* the branch was created. A merge automatically preserves that content. However, if the content existed at the merge base (when the branch was created) and is now absent from branch HEAD, the branch deliberately deleted it — and the merge will propagate that deletion. A check against `origin/main` alone cannot distinguish these two cases; you must check the merge base.

```bash
# Fetch main so origin/main is current
git fetch origin main --quiet

# Find the common ancestor. Use HEAD — works from a worktree (where HEAD == pr-$PR_NUMBER),
# the repo root on the PR branch, and the CI reviewer checkout (which uses the PR head ref).
MERGE_BASE=$(git merge-base HEAD origin/main)

# Was the supposedly-dropped content in the file at branch creation time?
git show "$MERGE_BASE:<file>" | grep -F "<the thing you think was dropped>"
```

| Merge-base result | `origin/main` result | Conclusion |
|-------------------|---------------------|-----------|
| **Not found** at merge-base | Found on `origin/main` | Added to main *after* branch was created — stale-branch artifact. **Drop the finding.** Merge will preserve it. |
| **Not found** at merge-base | Also absent from `origin/main` | Content never existed on either side. Not a regression. |
| **Found** at merge-base | Present or absent | Branch started with the content and **removed it**. This is a real deletion — keep the finding. |

Evidence format:

```text
Checked: MERGE_BASE=$(git merge-base HEAD origin/main)
         git show "$MERGE_BASE:<file>" | grep '<missing thing>'
Merge-base: not found
origin/main: found
Conclusion: Stale-branch artifact. Merge will preserve it. Drop the finding.
```

### "Wildcard removed, explicit list added" (coverage completeness)

When a PR replaces a glob/wildcard with an explicit list of entries, enumerate ALL items currently covered by the old pattern and diff against the new explicit list before reporting or confirming coverage.

**Why**: The explicit list is written by a human who knows the current file set. New top-level directories or files may have been added since the list was written, and the author simply didn't know they existed. The diff only shows the new explicit entries — it never shows what the wildcard was covering that was silently dropped.

```bash
# Enumerate everything currently on disk that the old pattern would have matched
ls <directory>/          # for a top-level dir glob
find <path> -maxdepth 1  # for deeper coverage

# Then verify each item has an entry in the new explicit list
grep -F "<item>" <CODEOWNERS or config file>
```

| Result | Action |
|--------|--------|
| Item on disk, entry in new list | Covered |
| Item on disk, no entry in new list | **Gap — flag as finding** |
| Entry in new list, item not on disk | Dead entry — flag as suggestion |

**Common pattern**: CODEOWNERS migrations from `.path/**` to per-file entries. The top-level `ls` reveals directories (hooks/, scripts/, evals/, settings.json) that the author only listed known subdirectories for. Always run `ls .claude/` (or the equivalent top-level dir), not just `ls .claude/agents/`, `ls .claude/rules/`, etc.

Evidence format:

```text
Checked: ls .claude/ → agents/ docs/ evals/ hooks/ rules/ scripts/ skills/ specs/ .gitignore CLAUDE.md README.md settings.json
CODEOWNERS has entries for: agents/ docs/ rules/ skills/ specs/ (via file-level)
Missing: evals/ hooks/ scripts/ settings.json README.md .gitignore
Conclusion: 6 paths had coverage under .claude/** and now have zero explicit CODEOWNERS entries.
```

### "Reachability-based claim" (fingerprint removal, backport safety, unreachable code)

When a finding depends on whether a commit/file is reachable from `main`, verify reachability — don't infer from the diff.

- Claim: "Removing this `.gitleaksignore` fingerprint will break scheduled scans of `main`"
- Verification: `gh api repos/{owner}/{repo}/compare/main...{sha} --jq '{status, ahead_by, behind_by}'`
  - `status: identical` or `behind` → commit IS on main; fingerprint must stay if the secret still exists there
  - `status: ahead` or `status: diverged` → commit is NOT reachable from `main`; a `fetch-depth: 0` clone of `main` won't contain it, so the fingerprint is safe to remove (`ahead` = purely ahead of main, no divergence; `diverged` = branch split from main)
- Same pattern for backport claims: "This fix was backported to `release/v2`" → same compare endpoint with `release/v2` as base; `status: behind` confirms reachability from the release branch.
- Same pattern for "is this commit in production" and "is this dead code on an unmerged branch" — the compare endpoint's `status` field is the ground truth, not the diff or the local working tree.

### "Generated output correctness" (script produces markdown, JSON, YAML, config)

When a script generates an artifact, verify the output renders/parses correctly — not just that the script exits 0.

- Identify the output format (markdown table, JSON, YAML, etc.)
- Identify which input values flow into the output — trace the full data path from source file through extraction/processing to final format
- Test with adversarial inputs: characters that are special in the output format (`|` in markdown tables, `"` in JSON, `:` in YAML, `\` in any format)
- Render/parse the output and verify: does a markdown table have the right number of columns? Does JSON parse without error? Does YAML load the expected structure?
- Check truncation boundaries: if output is truncated, does truncation land mid-character (UTF-8 multi-byte) or mid-escape-sequence?

### "Cross-platform behavior" (bash, awk, sed, cut across macOS/Linux)

When shell scripts use string operations, check whether behavior differs across platforms.

- `${var:offset:length}` — bash 3.2 (macOS `/bin/bash`) slices bytes; bash 5.x (Linux, CI runners) slices characters. Multi-byte chars (em-dash = 3 bytes) produce different output.
- `awk substr()` — BSD awk (macOS) is byte-based even with `LC_ALL=en_US.UTF-8`; gawk (Linux) is character-based.
- `cut -c` — **NOT portable** despite POSIX spec. GNU `cut` with `C.UTF-8` on Linux still counts bytes; macOS `cut` counts characters. Use `perl -CSD -ne 'print substr($_, 0, N)'` for portable character-based truncation.
- `sed` — BSD sed (macOS) requires `sed -i ''`; GNU sed uses `sed -i`. `-E` vs `-r` for extended regex.
- `grep` — macOS `grep -E` is POSIX ERE only (no `\s`, `\d`, `\b`); GNU grep supports PCRE shortcuts.
- `sort`, `date`, `stat` — all have BSD/GNU differences.
- Verification: check the shebang (`#!/usr/bin/env bash` vs `#!/bin/bash`), check what bash version CI runners use (`ubuntu-latest` = bash 5.2), check if Homebrew bash is assumed.

### "Validator completeness" (test, checker, CI gate)

When the PR includes or modifies a validator, ask what could pass the check but still be wrong.

- Read what the validator checks: presence? format? content equality? behavioral correctness?
- Identify the gap: "checks that skill names appear in inventory" ≠ "checks that inventory content matches regenerated output"
- Deliberately construct a false-negative scenario: introduce a drift/error that should be caught and verify the validator flags it
- Check whether the validator runs in the same environment as the artifact it validates (same bash version, same locale, same tool versions)

### "Consistency across parallel code paths" (sibling functions, similar helpers)

When modifying a function, check whether sibling functions that handle the same data apply the same sanitization, escaping, or error handling.

- Identify sibling code: other functions in the same file that process similar data, other call sites that extract similar fields
- For each edge case the modified function handles (quote stripping, escaping, truncation, null checks), verify the sibling handles it too
- If one path strips YAML quotes and another doesn't, that's a finding — regardless of whether any current input triggers the bug
- Quick check: search the file for the same field name or processing pattern

## Verification Shortcuts

Not every finding needs a 5-minute investigation. Quick verifications:

| Check | Time |
|-------|------|
| Search for pattern in sibling files (Grep tool) | 5 seconds |
| Read the full file for context | 10 seconds |
| `git blame` a specific line | 5 seconds |

The evidence block can be one line for simple checks:

```markdown
**Evidence:** Searched for `<pattern>` in `<path>` — N callers found. Pattern is established.
```
