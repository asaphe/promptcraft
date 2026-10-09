# ADOPTION.md

How to start using promptcraft content in your own AI assistant setup. Each tool has its own starting path.

Nothing here is installed — you copy, paste, edit, commit. The repo is source material, not a dependency.

## Quickstart by goal

Choose the standalone baseline first. Hooks, the operations profile, and the scaffold are separate opt-in routes. Run the commands from the promptcraft repository root using Bash. Existing destinations cause a nonzero exit before copying; compare and merge existing configuration manually instead. The guards reject symlinked configuration parents as well as existing or dangling destination links.

### Standalone global baseline

Copy-ready: [global-CLAUDE.md](tools/claude/examples/config/global-CLAUDE.md) installs only user instructions, with no rules, hooks, helpers, plugins, or TODOs. It needs only Claude Code's instruction-loading mechanism; instructions guide behavior rather than enforcing permissions. See [Claude memory documentation](https://code.claude.com/docs/en/memory).

<!-- adoption:basic -->

```bash
set -eu
if [ -L "$HOME/.claude" ] || [ -e "$HOME/.claude/CLAUDE.md" ] || [ -L "$HOME/.claude/CLAUDE.md" ]; then
  printf '%s\n' 'Configuration collision: compare and merge manually.' >&2
  exit 1
fi
mkdir -p "$HOME/.claude"
cp tools/claude/examples/config/global-CLAUDE.md "$HOME/.claude/CLAUDE.md"
```

<!-- /adoption:basic -->

### Optional project operations profile

Copy-ready after explicit selection: [operations.md](tools/claude/examples/profiles/operations.md) contains six rules for stateful infrastructure work, with no stack or companion-file dependency. Set `PROJECT_DIR` to an existing project you selected (for example, `export PROJECT_DIR="/path/to/your project"`). It loads throughout that project as `.claude/rules/operations.md`, never globally. The scaffold below is a separate starter; review overlap before combining them.

<!-- adoption:operations -->

```bash
set -eu
: "${PROJECT_DIR:?Select an existing project with PROJECT_DIR}"
[ -d "$PROJECT_DIR" ]
if [ -L "$PROJECT_DIR/.claude" ] || [ -L "$PROJECT_DIR/.claude/rules" ] || [ -e "$PROJECT_DIR/.claude/rules/operations.md" ] || [ -L "$PROJECT_DIR/.claude/rules/operations.md" ]; then
  printf '%s\n' 'Configuration collision: compare and merge manually.' >&2
  exit 1
fi
mkdir -p "$PROJECT_DIR/.claude/rules"
cp tools/claude/examples/profiles/operations.md "$PROJECT_DIR/.claude/rules/operations.md"
```

<!-- /adoption:operations -->

### Optional core safety hooks

Copy-ready dependency bundle: Bash, jq, Perl, git for repository checks, and ordinary shell utilities are required. An authenticated `gh` is optional for the own-PR force-push exemption; without it, that operation asks rather than receiving the exemption. These guards cover their documented patterns, not every possible mutation.

<!-- adoption:hooks -->

```bash
set -eu
if [ -L "$HOME/.claude" ] || [ -L "$HOME/.claude/hooks" ]; then
  printf '%s\n' 'Configuration collision: compare and merge manually.' >&2
  exit 1
fi
for name in destructive-guard stateful-op-reminder pr-create-guard _lib; do
  if [ -e "$HOME/.claude/hooks/$name" ] || [ -L "$HOME/.claude/hooks/$name" ]; then
    printf '%s\n' 'Hook collision: compare and merge manually.' >&2
    exit 1
  fi
done
mkdir -p "$HOME/.claude/hooks"
cp -R tools/claude/examples/hooks/destructive-guard "$HOME/.claude/hooks/"
cp -R tools/claude/examples/hooks/stateful-op-reminder "$HOME/.claude/hooks/"
cp -R tools/claude/examples/hooks/pr-create-guard "$HOME/.claude/hooks/"
cp -R tools/claude/examples/hooks/_lib "$HOME/.claude/hooks/"
```

<!-- /adoption:hooks -->

The complete `_lib` directory is required, including `hook-diag.sh`, `pr-author.sh`, `resolve-workdir.sh`, `strip-cmd.sh`, `strip-quoted-args.pl`, and `split-cmd-segments.pl`. Keep it beside the three hook directories. Registration is a separate manual activation step in `~/.claude/settings.json`, using each hook's README and these actual nested script paths (quote paths containing spaces in command strings):

- `~/.claude/hooks/destructive-guard/destructive-guard.sh`
- `~/.claude/hooks/stateful-op-reminder/stateful-op-reminder.sh`
- `~/.claude/hooks/pr-create-guard/pr-create-guard.sh`

The optional [merge-grant](tools/claude/examples/hooks/merge-grant/) remains a separate choice with its own dependency and registration review; without it, the destructive guard's default merge policy remains intact. Optional companions and test documentation use public upstream help links; all local Markdown links remain within the selected bundle.

### Optional infrastructure project scaffold

Copy-ready starter after selecting `PROJECT_DIR` as above. It installs `.claude/` rules, agents, skills, docs, and specs; review and customize its TODOs and infrastructure assumptions before use. Public repository links in the copied scaffold are optional help; all local Markdown links stay within the copied tree. No settings registration or hook installation is included.

<!-- adoption:scaffold -->

```bash
set -eu
: "${PROJECT_DIR:?Select an existing project with PROJECT_DIR}"
[ -d "$PROJECT_DIR" ]
if [ -e "$PROJECT_DIR/.claude" ] || [ -L "$PROJECT_DIR/.claude" ]; then
  printf '%s\n' 'Configuration collision: compare and merge manually.' >&2
  exit 1
fi
cp -R tools/claude/scaffolding/.claude "$PROJECT_DIR/.claude"
```

<!-- /adoption:scaffold -->

### Advanced reference and specialized examples

[global-CLAUDE-advanced.md](tools/claude/examples/config/global-CLAUDE-advanced.md) preserves the full opinionated author profile for browsing and section-by-section adaptation in its source layout. It is reference-only, not a complete runtime installation. Specialized [rules](tools/claude/examples/rules/) remain browse/adapt material; do not bulk activate them.

### Cursor starter pack

You use Cursor and want the smallest viable rule set.

```bash
# 1. Open Cursor Settings → Rules → User Rules.
# 2. Paste these three files (concatenated) into the User Rules text area:
cat tools/cursor/rules/user/core-principles.md \
    tools/cursor/rules/user/code-quality.md \
    tools/cursor/rules/user/general-principles.md \
  | pbcopy   # macOS; on Linux use xclip / xsel

# 3. For a specific project, add the one ready-to-use Project Rule:
mkdir -p /path/to/your-project/.cursor/rules/
cp tools/cursor/rules/mdc/kubernetes/kubernetes-helm.mdc /path/to/your-project/.cursor/rules/
```

Add language-specific files from `tools/cursor/rules/user/` as relevant.

### ChatGPT-only minimum

You only use ChatGPT (no Claude Code, no Cursor) and want sensible defaults.

```bash
# Open ChatGPT → Settings → Personalization → Custom Instructions.
# Paste the two code blocks from one of:
cat tools/chatgpt/global/general-instructions.md       # multi-stack default
cat tools/chatgpt/global/professional-instructions.md  # infrastructure focus
```

Each file has two code blocks for the two text fields. **Budget: 1500 chars per field** — don't extend without counting.

---

The full per-tool sections below cover the same paths plus the rest of the optional content.

## Claude Code

Use the four guarded recipes above; they are the only Claude copy-ready routes declared here. The [manifest](.claude/evals/adoption-manifest.json) lists the artifacts, required destination paths, and optional upstream source links. CI executes the actual delimited snippets in isolated temporary homes and projects, checks bytes and dependencies, checks all copied Markdown links, and rejects collisions. This verifies copy/setup behavior, not live Claude integration.

The `tools/claude/examples/hooks/` directory includes retained executable examples and migration stubs. [RETIRED.md](tools/claude/examples/RETIRED.md) maps withdrawn scripts and examples moved into maintained plugins. Remove any retired settings registration before deleting its local script.

Start with `destructive-guard` (hard-blocks pushes to main — force included — and destructive AWS commands), `stateful-op-reminder` (nudges before AWS/K8s/DB mutations), and `pr-create-guard` (checks PR creation prerequisites). Select Kubernetes targets explicitly with kubectl `--context` or Helm `--kube-context`; the automatic context injector is retired.

Read [claude-best-practices.md](tools/claude/guides/claude-best-practices.md) for the broader reference. Other tools below retain their paste, conversion, and translation routes; these checks do not validate their live UIs.

## Cursor

### User rules (global, personal)

Settings → Rules → **User Rules** takes one big markdown blob. The files under `tools/cursor/rules/user/` are meant to be pasted in, either all at once or individually.

Recommended minimum:

- `core-principles.md` — communication, verification, scope discipline.
- `code-quality.md` — linting, formatting, review gates.
- `language-standards.md` — per-language conventions.

### Project rules (`.cursor/rules/*.mdc`)

Cursor's project rules live in `.cursor/rules/` inside your repo and auto-load based on globs.

**Ready-to-use rules** are in [`tools/cursor/rules/mdc/`](tools/cursor/rules/mdc/) (currently `kubernetes/kubernetes-helm.mdc`). Copy directly:

```bash
mkdir -p /path/to/your-project/.cursor/rules/
cp tools/cursor/rules/mdc/kubernetes/kubernetes-helm.mdc /path/to/your-project/.cursor/rules/
```

**JSON templates** that need conversion to `.mdc` first are in [`tools/cursor/rules/mdc-templates/`](tools/cursor/rules/mdc-templates/) — see that directory's README for the conversion recipe (it's mechanical for simple rules, judgment-heavy for complex ones).

The `.mdc` frontmatter controls activation — see Cursor's [Project Rules docs](https://cursor.com/docs/context/rules).

### MCP servers

If you use Cursor's MCP support, `tools/cursor/mcp/` has a reference configuration and per-server guides.

## ChatGPT

### Global Custom Instructions

Pick the profile that matches your work:

- `tools/chatgpt/global/general-instructions.md` — multi-stack development (Python, TS, Bash, infra).
- `tools/chatgpt/global/professional-instructions.md` — infrastructure and automation: Terraform, Kubernetes, Docker, AWS, CI/CD.

Each file has two code blocks — copy them into the matching fields under Settings → Personalization → Custom Instructions.

**Budget:** 1500 characters per field. Don't extend the files without counting.

### Project Instructions

Inside a ChatGPT Project, set Instructions by pasting one of:

- `tools/chatgpt/projects/development-project.md`
- `tools/chatgpt/projects/infrastructure-project.md`
- `tools/chatgpt/projects/mixed-project.md`

These layer on top of your global Custom Instructions.

## Codex

Codex reads its own config, so this content does not copy across unchanged. Start from your Claude Code setup:

1. Map each piece with [`tools/codex/claude-code-translation.md`](tools/codex/claude-code-translation.md). Instruction files, skills and subagents move. `.claude/rules/` has no Codex equivalent, and several `config.toml` fields need absolute paths.
2. Run your Claude Code Bash hooks under Codex through [`tools/codex/bash-hook-dispatcher.sh`](tools/codex/bash-hook-dispatcher.sh). Registered directly, a guard that asks for confirmation lets the command through. [`tools/codex/shared-hooks.md`](tools/codex/shared-hooks.md) explains why.

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
