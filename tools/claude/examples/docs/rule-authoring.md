# Rule Authoring Standards

## Incident-agnostic bodies

Rules autoload as evergreen context; incidents are point-in-time events. Rule bodies must NOT contain ticket numbers, PR refs, specific role/module/file names that exist solely because of the originating incident, or dates. Use generic placeholders (`<role>`, `<module>`, `<path>`). Stable codebase pointers (canonical IDs, long-lived paths, sibling rule filenames) are fine in a Reference / Related section.

Incident narrative belongs in the PR description, the issue tracker, and `git log` — not the rule.

**Discriminator:** replace every named role/module/path in the body with `<placeholder>`. If the rule still teaches the pattern, the originals were illustrative — keep them. If unintelligible, the rule is incident-anchored — rewrite before merging.

## No dates

`git blame` / `git log` are the source of truth for when content landed. Dates inside files rot quickly; a future-dated entry reads as broken on its face.

Scope: rule bodies, hook comments, doc bodies, ticket descriptions, anywhere durable content lives.

**Allowed exceptions** (state the reason on inclusion):

- Decision logs / ADRs where the date is the load-bearing fact
- External calendar events with hard cutoffs (deprecation, freeze window)
- Memory entries where a relative date must be converted to remain interpretable later
- Illustrative examples where the date IS the example content

## Rule placement scope

`.claude/rules/general/` auto-loads on **every** session — reserve it for patterns that apply in the majority of sessions. Rules for narrow-scenario or infrequent operations (e.g., "enable this setting only during a specific access window", "run this CLI only for queue cleanup") waste context budget on sessions where they're irrelevant.

Placement decision:

- **Needed in >80% of sessions?** → `rules/general/`
- **Specific to one domain/provider?** → `{provider}/.claude/rules/`
- **Rare operation or narrow scenario?** → on-demand doc under `.claude/docs/`, linked from CLAUDE.md

## Extending a rule for a new edge case

Fold the abstract pattern into Counter-indications or Mechanism. Do NOT append "Incident log" / "Related" / "Recent example" subsections — same anti-pattern at a different level.

## Consolidate, don't proliferate

Merge related rules into one file per domain. One file per incident creates unsustainable bloat — the rule count grows without bound and overlapping rules drift out of sync. A new edge case usually belongs *inside* an existing domain rule, not in a new file.

## Titles lead with the non-obvious insight

A rule's title must surface the gotcha, not name the tool. "`repository_owner` in OIDC trust breaks cross-repo role assumption" teaches at a glance; "OIDC config" does not. The reader scanning the file should learn the lesson from the heading alone.

## Validate before presenting

Run a new or edited rule through an agent-config reviewer, and cross-reference existing rules for overlap, before presenting it. A rule that duplicates an always-loaded rule or contradicts a sibling is worse than no rule.

## Adjust rules to allow needed patterns — don't add bypasses

When an intentional, correct pattern is blocked by an existing hook / lint / rule, update the rule to explicitly allow it. Never reach for `// eslint-disable`, `--no-verify`, hook exceptions, or skip flags to punch through — the bypass removes the guard for the wrong case too. Fix the rule's predicate, not the one invocation.

## Editing a load-bearing rule fans out

Skills, agents, and docs sometimes verbatim-quote the global CLAUDE.md / a shared kernel / `.claude/docs/` as enforcement anchors; rewriting the source silently rots those quotes. After editing the source, grep the previous text **and** the section title across your skills, agents, docs, and repo `.claude/` directories — update each hit, or remove the quote and link canonically. If the quote was an enforcement anchor (a skill step body, an agent decision rule), re-verify the consumer's logic still fires after the edit.
