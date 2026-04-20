# Content Quality Discipline

This is a knowledge base — accuracy is the product. Getting a pattern wrong teaches it wrong.

- **Verify every code example against reality** — Shell scripts must use POSIX ERE (no `\s`, `\d`, `\b` — macOS `grep -E` doesn't support PCRE). Hook exit codes must match documented Claude Code behavior. Settings JSON must use valid configuration fields.

- **Cross-reference before adding** — Before creating a new file, check if the content already exists elsewhere in the repo. Before referencing another file, verify the path exists. Before claiming a hook does X, read the hook.

- **Examples must be self-contained** — Each hook, agent, skill, or rule example must work if copied verbatim. No implicit dependencies on other files unless documented in the README.

- **Distinguish "works in practice" from "documented behavior"** — If a hook pattern works but isn't in the official docs, note it. Users need to know what they can rely on vs. what might change.

- **Keep examples and scaffolding in sync** — When updating a pattern in `tools/claude/examples/`, check if the same pattern exists in `tools/claude/scaffolding/` and update both. When adding a new hook to `tools/claude/examples/hooks/`, consider whether `tools/claude/scaffolding/` should reference it.
