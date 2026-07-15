# promptcraft

Rules, agents, skills, and configs for AI coding assistants — Claude Code, Cursor, ChatGPT.

Distilled from real production use. Copy what fits, ignore what doesn't, adapt to your stack.

## Start here

Pick your assistant:

- **Claude Code** → [`tools/claude/`](tools/claude/) — CLAUDE.md patterns, hooks, agents, skills, full example config.
- **Cursor** → [`tools/cursor/`](tools/cursor/) — `.cursor/rules/*.mdc` project rules, user-rules UI copy-paste, MCP configuration.
- **ChatGPT** → [`tools/chatgpt/`](tools/chatgpt/) — Custom Instructions (global) and Project Instructions (scoped).

The universal content — principles, language standards, infra patterns, CI/CD, quality — lives in [`shared/`](shared/) and is referenced by all three tool directories.

## Who this is for

- **DevOps / platform engineers** setting up Claude Code for infra work — `tools/claude/examples/config/global-CLAUDE.md` is the highest-leverage single file.
- **Developers** tuning Cursor or ChatGPT to match their team's code style — `shared/languages/` + `tools/<tool>/` gets you 80% of the way.
- **AI tooling tinkerers** wanting hook / agent / skill patterns to fork — `tools/claude/examples/hooks/` and `tools/claude/examples/agents/`.

## Distinguishing patterns

The strongest ideas in this repo are concentrated in a handful of files. If you only read seven things:

- **Modular composition (the Lego principle)** — module boundaries are agent task boundaries; one agent owns one module via a typed contract. [`shared/principles/modular-composition.md`](shared/principles/modular-composition.md).
- **Specialist agent roster** — split work across bounded specialists with sibling deferral tables, instead of one general-purpose agent. [`shared/principles/agent-design-patterns.md`](shared/principles/agent-design-patterns.md).
- **Failure triage tables** — `Symptom → Root Cause → Fix` tables are the highest-value-per-token section any specialist agent can carry. Same file: [`agent-design-patterns.md`](shared/principles/agent-design-patterns.md).
- **Stateful operations protocol** — query-state → backup-full-object → mutate → verify-against-backup, for any change to external systems (cloud, DB, K8s, secrets, identity). [`shared/principles/operational-safety-patterns.md`](shared/principles/operational-safety-patterns.md).
- **Approval interpretation** — "looks good" ≠ "execute everything"; "show me X" ≠ "run X". Explicit phrases gate destructive operations. Same file: [`operational-safety-patterns.md`](shared/principles/operational-safety-patterns.md).
- **Hooks as deterministic guardrails** — enforce rules at the tool layer (PreToolUse hooks) rather than relying on the agent to remember. Safer and cheaper than instruction-only enforcement. [`tools/claude/examples/hooks/`](tools/claude/examples/hooks/).
- **Context management is the #1 success factor** — most agent failures trace to bloated or stale context, not weak reasoning. Manage the window obsessively. [`tools/claude/guides/claude-best-practices.md`](tools/claude/guides/claude-best-practices.md).

## Repo layout

```text
.
├── shared/               # Tool-agnostic content (universal rules)
│   ├── principles/       # Process, architecture, style, safety, agents, prompting, CLI
│   ├── languages/        # TS, Python, Bash, Java, Go conventions
│   ├── infrastructure/   # Terraform, K8s, Docker, AWS, cost
│   ├── workflows/        # CI/CD, GitHub Actions, version mgmt
│   └── quality/          # Code, docs, research standards
├── tools/
│   ├── claude/           # Claude Code — guides, templates, examples, scaffolding, specs
│   ├── cursor/           # Cursor — user rules, project rules (.mdc), MCP, recovery
│   └── chatgpt/          # ChatGPT — global Custom Instructions, Project Instructions
├── AGENTS.md             # Per-repo instructions for AI agents editing this repo
├── ADOPTION.md           # How to adopt content into your own setup
├── CONVENTIONS.md        # File naming, structure, link format
├── DECISIONS.md          # Why things are laid out this way
├── llms.txt              # Machine-readable index (llmstxt.org convention)
└── .claude/              # Contributor config (loaded when editing this repo)
```

Each second-level directory has its own README listing contents and when to use them.

## Adopting content

See [`ADOPTION.md`](ADOPTION.md) for step-by-step per-tool setup.

TL;DR:

- **Claude Code:** drop files from `tools/claude/examples/` into your own `.claude/` directory and edit to taste.
- **Cursor:** copy `tools/cursor/rules/user/*.md` into Settings → Rules → User Rules; drop `tools/cursor/rules/mdc/*.mdc` into your repo's `.cursor/rules/`.
- **ChatGPT:** paste `tools/chatgpt/global/*.md` into Settings → Custom Instructions; paste `tools/chatgpt/projects/*.md` into a Project's instructions.

## Built with this

Real repos using patterns adopted from here:

- **[claude-learning-loop](https://github.com/asaphe/claude-learning-loop)** — a Claude Code plugin implementing the self-improvement feedback-loop pattern.
- **[clickup-mcp](https://github.com/asaphe/clickup-mcp)** — an MCP server for ClickUp, built with the Claude Code agent/skill/hook conventions from `tools/claude/`.

## Conventions

- **Shared is canonical.** Universal rules live in `shared/` once; tool dirs reference them, not duplicate.
- **Nothing here is a hard dependency.** Every file assumes you will read, edit, and adapt — not consume verbatim.
- **Zero PII.** This is a public repo. No company names, internal service names, account IDs, or personal data.

Full conventions in [`CONVENTIONS.md`](CONVENTIONS.md).

## Contributing

Edits welcome. See [`AGENTS.md`](AGENTS.md) for contribution guidelines and [`CONVENTIONS.md`](CONVENTIONS.md) for structure.

## License

CC BY 4.0 — see [`LICENSE`](LICENSE).
