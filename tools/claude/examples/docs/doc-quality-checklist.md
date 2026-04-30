# Doc Quality Checklist

On-demand reference for review agents evaluating `.claude/docs/`, `.claude/rules/`, and `CLAUDE.md` changes. Read this file when the PR diff includes documentation files.

## Staleness Scan

Check every line for content that will go stale without active maintenance:

| Pattern | Example | Fix |
|---|---|---|
| Ticket references | `(TICKET-1234)`, `see TICKET-5678` | Remove — use `git blame` to trace |
| Dates and temporal phrases | `as of <date>`, `currently`, `recently` | Remove or generalize |
| Instance-specific identifiers | ARNs, resource IDs, account IDs, cluster names | Remove or reference the Terraform / config source |
| Hardcoded counts | `14 agents`, `9 rules`, `3 exempted paths` | Remove or say "see X for current list" |
| Enumerated directory contents in prose | "The `<dir>/` tree contains a, b, c, d, ..." | Describe purpose; link to authoritative source |
| Personal paths | Cloud-storage paths, home directories, local tool paths | Remove from shared docs |
| Duplicated lists / tables | Exempted-paths table that mirrors a Terraform source | Add "Authoritative source: path/to/file" |

## Content Accuracy

- **Describes deployed state, not defaults** — If a component has been customized (overridden rules, changed defaults), the doc must describe the actual behavior, not vendor documentation behavior.
- **Every factual claim is verifiable** — Can a reader confirm each claim by reading the referenced source? If not, add the reference or remove the claim.
- **Code references resolve** — File paths, function names, and config keys mentioned in the doc must exist in the current codebase.
- **No negative repo declarations** — "There is no X here" and "X does not live in this repo" go stale silently the moment anyone adds X. Flag and remove them. The repo structure section already tells readers what IS present; a list of absences is redundant noise that becomes misinformation.

## Instruction Quality (for rules and agent definitions)

Based on the empirical observation that LLMs follow ~150–200 always-loaded instructions with consistent quality:

- **Each instruction earns its place** — Would removing it cause Claude to make mistakes? If not, cut it.
- **Concrete over abstract** — "Check for ticket references in section titles" beats "ensure no stale data."
- **Positive guidance over prohibition** — "Describe deployed state" beats "Don't describe defaults."
- **Include the why** — Rules with motivation are followed more reliably than bare directives.
- **One principle, not one instance** — A rule should prevent the class of mistake, not just the exact scenario that prompted it.

## Structure

- **Progressive disclosure** — Core instructions in the main file, detailed references in sub-files loaded on demand.
- **Section titles describe content, not context** — "Currently exempted paths" not "Currently exempted paths (TICKET-1234)".
- **Authoritative source pointers** — When a doc summarizes content from code, identify the source so readers know where truth lives.
