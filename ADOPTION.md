# ADOPTION.md

How to start using promptcraft content in your own AI assistant setup. Three tools, three starting paths.

Nothing here is installed — you copy, paste, edit, commit. The repo is source material, not a dependency.

## Claude Code

### 1. Fastest path: grab the global CLAUDE.md template

The single highest-leverage file for a DevOps-oriented Claude Code setup:

```bash
cp tools/claude/examples/config/global-CLAUDE.md ~/.claude/CLAUDE.md
```

Edit it — every section has `<TODO>` markers and inline comments. Replace company-specific paths, add your own on-demand docs, prune domains you don't work in.

### 2. Extend with hooks

The `tools/claude/examples/hooks/` directory has ~20 production-tested hooks. Each is a standalone directory with a README and shell script.

```bash
# Copy a hook:
cp -r tools/claude/examples/hooks/destructive-guard ~/.claude/hooks/

# Register it in ~/.claude/settings.json (see the hook's README for exact JSON).
```

Start with `destructive-guard` (blocks `rm -rf`, `git push --force` to main), `stateful-op-reminder` (nudges before AWS/K8s/DB mutations), and `kubectl-context-inject` (auto-injects `--context` on every kubectl command).

### 3. Project-level `.claude/`

For repo-scoped rules, agents, and skills, use the scaffolding:

```bash
cp -r tools/claude/scaffolding/.claude/ /path/to/your-project/.claude/
```

Then read [`tools/claude/guides/claude-best-practices.md`](tools/claude/guides/claude-best-practices.md) end-to-end — it's the reference for what goes in `.claude/CLAUDE.md`, when to define agents, and when to write skills.

## Cursor

### User rules (global, personal)

Settings → Rules → **User Rules** takes one big markdown blob. The files under `tools/cursor/rules/user/` are meant to be pasted in, either all at once or individually.

Recommended minimum:

- `core-principles.md` — communication, verification, scope discipline.
- `code-quality.md` — linting, formatting, review gates.
- `language-standards.md` — per-language conventions.

### Project rules (`.cursor/rules/*.mdc`)

Cursor's project rules live in `.cursor/rules/` inside your repo and auto-load based on globs. Copy the relevant `.mdc` file:

```bash
mkdir -p /path/to/your-project/.cursor/rules/
cp tools/cursor/rules/mdc/<rule>.mdc /path/to/your-project/.cursor/rules/
```

The frontmatter controls activation — see Cursor's [Rules for AI](https://docs.cursor.com/context/rules) docs.

### MCP servers

If you use Cursor's MCP support, `tools/cursor/mcp/` has a reference configuration and per-server guides.

## ChatGPT

### Global Custom Instructions

Pick the profile that matches your work:

- `tools/chatgpt/global/general-instructions.md` — multi-stack development (Python, TS, Bash, infra).
- `tools/chatgpt/global/professional-instructions.md` — primarily DevOps / platform engineering.

Each file has two code blocks — copy them into the matching fields under Settings → Personalization → Custom Instructions.

**Budget:** 1500 characters per field. Don't extend the files without counting.

### Project Instructions

Inside a ChatGPT Project, set Instructions by pasting one of:

- `tools/chatgpt/projects/development-project.md`
- `tools/chatgpt/projects/infrastructure-project.md`
- `tools/chatgpt/projects/mixed-project.md`

These layer on top of your global Custom Instructions.

## Universal content (any assistant)

The files under `shared/` are the canonical versions. Tool-specific copies exist for convenience, but when you adapt:

- Principles (communication, tool safety, agent design) → `shared/principles/`
- Language conventions → `shared/languages/`
- Infrastructure patterns → `shared/infrastructure/`
- CI/CD & workflows → `shared/workflows/`
- Code / docs / research quality → `shared/quality/`

These are meant to be read, understood, and selectively transplanted — not pasted wholesale.

## Common questions

**Can I just point my assistant at this repo as a data source?**
Technically yes (via MCP, file-loading tools, etc.), but the content is not structured for ingestion — it's structured for reading and adaptation. You'll get better results by copying what's relevant into your own config.

**Is anything here a hard dependency?**
No. Every hook, rule, and template is meant to be forked and edited. There is no stable API to depend on.

**How do I stay in sync with upstream?**
Watch the repo. Upstream changes land as regular commits. Diff against your local copies periodically — they're short enough to merge by hand.

**Can I contribute back?**
Yes. See [`AGENTS.md`](AGENTS.md) for contribution conventions.
