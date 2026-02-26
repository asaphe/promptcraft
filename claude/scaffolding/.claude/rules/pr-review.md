# PR Review Rules

- **Route reviews by file scope** — Always determine what changed before choosing a reviewer. Never do ad-hoc reviews in the main context. Spawn all applicable reviewers in parallel for mixed PRs.

  | Changed files | Reviewer |
  | --- | --- |
  | `devops/`, `.github/`, `**/Dockerfile*`, `**/*.sh` | Spawn `devops-reviewer` agent |
  | `.claude/` | Spawn `config-reviewer` agent |
  | Application code (Python, TypeScript, Go, Java) | Application code reviewer |
  | Mixed | Spawn all applicable reviewers in parallel |

- **Present findings before posting** — After the review agent returns findings, present them to the user for approval. Do not let agents post directly to the PR without review.

- **Suggestive tone when intent is unknown** — Use suggestive language ("worth considering", "you might want to") rather than prescriptive ("add this", "change this"). Reserve directive language for clear standards violations.

- **Post findings as inline file comments via the Reviews API** — Use `gh api POST /repos/{owner}/{repo}/pulls/{number}/reviews` with a `comments` array (each entry: `path`, `line`, `body`). Never use `gh pr review --comment --body` for large markdown — it can fail silently.

- **Only report problems — skip "GOOD" sections** — Review output should contain only blocking issues and suggestions. Do not include positive findings sections.

- **Hypothetical-future observations are suggestions, not blockers** — Observations about what could break if the code is extended later are valid as suggestions. Never classify them as blocking.

- **Spec is authoritative over existing convention** — If existing code violates the spec, the spec wins — flag the violation for migration, don't suggest the PR match the existing (incorrect) convention.

- **Verify every finding against codebase patterns** — Before presenting findings, check sibling files for the same pattern. If the "violation" is the established norm, downgrade to suggestion or drop entirely.

- **Delete wrong comments — never reply-correct your own** — If a posted comment is incorrect, delete it and post a new corrected one if needed. Replying to your own comment with "actually, this was wrong" creates noise.
