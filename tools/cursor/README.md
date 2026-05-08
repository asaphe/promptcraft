# Cursor Integration

Cursor-specific adaptations of promptcraft content. Universal rules live under `../../shared/`; this directory holds Cursor-specific adaptations and starter rules in Cursor's two native formats (User Rules and Project Rules).

## Layout

```text
tools/cursor/
├── README.md                          # This file
├── multi-tool-coexistence.md          # Coexistence guide: AGENTS.md + CLAUDE.md + Cursor rules
├── rules/
│   ├── README.md
│   ├── user/                          # Markdown for Cursor's User Rules UI (Settings → Rules)
│   │   ├── core-principles.md
│   │   ├── code-quality.md
│   │   ├── language-standards.md
│   │   ├── general-principles.md
│   │   ├── infrastructure-tools.md
│   │   ├── terraform-infrastructure.md
│   │   ├── workflow-patterns.md
│   │   └── ansible-automation.md
│   ├── mdc/                           # Ready-to-use Cursor Project Rules (.mdc files)
│   │   ├── README.md
│   │   └── kubernetes/
│   │       └── kubernetes-helm.mdc
│   └── mdc-templates/                 # JSON templates that need conversion to .mdc
│       ├── README.md
│       ├── naming/
│       ├── formatting/
│       ├── structure/
│       ├── documentation/
│       ├── language-specific/
│       └── terraform/
├── mcp/                               # MCP server configuration for Cursor
└── recovery/                          # Conversation history recovery utility
```

## Cursor's two rule formats — choose by destination

| Format | Lives in | Loaded by | Use for |
|--------|----------|-----------|---------|
| **User Rules** | Cursor Settings → Rules → User Rules | Cursor Agent (chat), globally | Personal preferences applied across every project |
| **Project Rules** | `.cursor/rules/*.mdc` inside a project | Cursor Agent, scoped + glob-matched | Project-specific standards, version-controlled |

Per [Cursor's rule precedence](https://cursor.com/docs/context/rules): Team Rules → Project Rules → User Rules. User Rules fill gaps; Project Rules win for project-specific guidance.

## User Rules setup (`rules/user/`)

User Rules are the easiest way to add personal preferences without touching project repos. They apply globally across all projects.

1. Open Cursor Settings (`Cmd/Ctrl + ,`).
2. Navigate to **Rules → User Rules**.
3. Pick one or more files from `rules/user/` and paste their contents into the User Rules text area. Concatenate multiple files if needed.
4. Save.

Recommended starter set:

- `core-principles.md` — communication discipline, verification, scope.
- `code-quality.md` — linting, formatting, review gates.
- `general-principles.md` — universal naming and environment conventions.

Add language- or infra-specific files as relevant to your work.

## Project Rules setup (`rules/mdc/` + `rules/mdc-templates/`)

Project Rules version-control rule logic alongside the codebase. Cursor loads `.mdc` files from `.cursor/rules/` based on each rule's globs.

**Ready-to-use** (copy directly):

```bash
mkdir -p /path/to/your-project/.cursor/rules/
cp tools/cursor/rules/mdc/kubernetes/kubernetes-helm.mdc /path/to/your-project/.cursor/rules/
```

**JSON templates** (convert first — see [`rules/mdc-templates/README.md`](rules/mdc-templates/README.md)):

The templates directory holds rule logic encoded as structured JSON. Conversion to `.mdc` is mechanical for simple naming/formatting rules, judgment-heavy for complex ones. The README walks through the conversion shape with one worked example.

## Coexistence with other AI assistants

If you use Cursor alongside Claude Code, GitHub Copilot, or Aider, see [`multi-tool-coexistence.md`](multi-tool-coexistence.md). It covers `AGENTS.md` + `CLAUDE.md` + Cursor rules in one repo without conflicts.

## See also

- [`../../shared/principles/`](../../shared/principles/) — tool-agnostic principles that underlie these rules.
- [`../claude/`](../claude/) — equivalent setup for Claude Code.
- [`../chatgpt/`](../chatgpt/) — equivalent setup for ChatGPT.
