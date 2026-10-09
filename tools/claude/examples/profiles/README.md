# Optional project profile

Select [operations.md](operations.md) for stateful infrastructure work in one project. It has no stack assumptions, hook installation, or companion-file dependencies.

Use the guarded [operations recipe](../../../../ADOPTION.md#optional-project-operations-profile) after explicitly selecting a project. Its `.claude/rules/operations.md` has no path frontmatter and loads throughout that chosen project, never globally. Instructions guide behavior; they do not enforce permissions.

The [project scaffold](../../scaffolding/README.md) is a separate infrastructure-oriented starter. Review overlapping rules before combining them. More specialized rules remain browse/adapt examples; the [advanced global profile](../config/global-CLAUDE-advanced.md) is reference-only.
