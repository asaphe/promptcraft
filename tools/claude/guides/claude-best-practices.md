# Claude Code Best Practices

A practical guide to getting the most out of Claude Code, synthesized from community patterns, production experience with a 40+ service monorepo, and the configuration patterns documented throughout this repository.

## Three Core Principles

1. **Context management is the primary success factor.** Most failures trace back to bloated context, stale state, or Claude losing track of what matters. Manage your context window obsessively.
2. **Plan before you code.** Every quality source and our own experience confirms: upfront planning prevents rework. Claude is better at executing a clear plan than improvising from a vague prompt.
3. **Keep systems simple.** Simple control loops outperform multi-agent orchestration. Debuggability matters more than sophistication.

---

## Context Management

Context is your most constrained resource. Everything else follows from managing it well.

### CLAUDE.md File Design

Your root `CLAUDE.md` is auto-loaded every session. Keep it to **100-200 lines** (under ~2000 tokens). It should contain:

- Critical behavioral rules (commit format, safety constraints, auth patterns)
- Essential commands (build, test, lint)
- Repository structure overview
- Pointers to deeper docs (not the docs themselves)

Use **subdirectory CLAUDE.md files** (50-100 lines each) for project-specific context that only loads when working in that directory.

**Anti-patterns to avoid:**

| Don't | Do Instead |
|-------|------------|
| Embed entire docs via `@file` references | Point to docs conditionally: "For X error, see `path/to/docs.md`" |
| Write long lists of things to never do | State preferred alternatives directly |
| Write comprehensive manuals | Document what Claude gets wrong — corrections are higher signal |
| Add every possible rule upfront | Start minimal, add rules only when Claude makes a repeated mistake |

See: [global-claude-md-guide.md](global-claude-md-guide.md) for detailed design guidance.

### Aggressive Context Clearing

Don't wait for automatic compaction — it's opaque and loses precision.

- **Clear at 60k tokens or 30% context usage** (whichever comes first)
- Use `/clear` followed by a fresh prompt for simple restarts
- For complex tasks, use the **Document & Clear** pattern:
  1. Have Claude write progress to a markdown file (plan, decisions, remaining work)
  2. `/clear` the context
  3. Start a fresh session: "Read `task-progress.md` and continue from where we left off"
  4. Continue work with clean context

**Why not `/compact`?** Automatic compaction is lossy — it discards details Claude might need. Explicit clearing with documented state gives you control over what's preserved.

### Token Budget Awareness

Your total context has a budget. Monitor where tokens go:

| Component | Target Budget | Risk if Over |
|-----------|--------------|--------------|
| CLAUDE.md (root + subdirectory) | < 2,000 tokens | Crowds out working memory |
| MCP tool definitions | < 20,000 tokens | Significantly degrades reasoning |
| Rules (auto-loaded) | Proportional to task | Irrelevant rules waste tokens |
| Conversation history | Clear before saturation | Quality degrades as context fills |

Use `paths:` frontmatter on rules files to conditionally load only what's relevant to the current task. See: [learning-system-guide.md](learning-system-guide.md#rules-organization) for the subdirectory pattern.

### Instruction Design Principles

Beyond token counts, how you write instructions determines whether they're followed.

**Instruction Budget** — Frontier models follow approximately 150-200 discrete instructions with consistent quality. Each auto-loaded rule file, CLAUDE.md bullet, and agent behavioral rule competes for the same working memory. When total instruction count exceeds this range, compliance drops on lower-priority rules. Audit quarterly: `grep -c '^\- \*\*' .claude/rules/**/*.md` plus CLAUDE.md bullet count.

**Right Altitude** — Instructions should be specific enough to act on but general enough to cover variants. Too abstract ("be careful with state") gives no actionable guidance. Too specific ("when file X has error Y, run command Z") only catches one case. The sweet spot: state the principle with one concrete example so the agent can generalize. Test: "Would this instruction also prevent the next variant of this problem?"

**Primacy and Recency Effects** — Instructions at the beginning and end of a config file receive disproportionate attention under context pressure. Place highest-priority rules (safety guards, destructive-operation blocks) at the top of CLAUDE.md and at the top of each agent's behavioral section. Place less critical preferences in the middle. Ordering within the file matters as much as total size.

**Progressive Disclosure** — Not everything needs to be in context at once. Three mechanisms reduce baseline token cost: (a) subdirectory CLAUDE.md files load only when working in that directory, (b) `.claude/docs/` files are read on-demand via pointers in CLAUDE.md, (c) agent `skills` field loads skill descriptions (~24 tokens each) until the full body is needed on invocation. See the [skill design guide](../templates/skills/skill-design-guide.md) for the three-level disclosure model.

**Poka-Yoke (Mistake-Proofing)** — Design configurations that make mistakes structurally harder rather than relying on the agent remembering a rule. Preference order: hooks (deterministic, blocks the action) > tool scoping in `allowed-tools` (structural, prevents access) > rules (judgment-dependent, can be forgotten). If a behavior must happen 100% of the time, it belongs in a hook, not a rule. See the [hooks guide](hooks-guide.md#hooks-vs-rules-decision-framework) for the decision framework.

---

## Planning & Workflow

### The Four-Phase Workflow

Structure every non-trivial task as: **Explore → Plan → Code → Commit**.

**Phase 1: Explore** — Explicitly tell Claude NOT to write code yet. Let it read files, understand the codebase, identify patterns and constraints.

**Phase 2: Plan** — Use Planning Mode or ask for a written plan. Review it before approving. Use "think" / "think hard" / "ultrathink" for deeper analysis. Challenge assumptions. Ask for 2-3 alternative approaches with trade-offs.

**Phase 3: Code** — Implement in stages (1-2 sections at a time). Review between stages. If context gets large, use the Document & Clear pattern.

**Phase 4: Commit** — Update docs if needed. Create the PR. Review the full diff.

Skipping phases 1-2 is the most common source of wasted effort. Claude will jump straight to coding if you let it — explicit phase boundaries prevent this.

### Prompt Chaining

For complex tasks that exceed a single prompt's effective scope, break them into sequential prompts where each step's output feeds the next:

1. **Explore** — "Read module X. List all public functions with their signatures. Do NOT suggest changes."
2. **Analyze** — "Given this inventory, identify functions that lack input validation or error handling."
3. **Plan** — "For each finding, propose a fix. Show before/after signatures. Do NOT implement."
4. **Implement** — "Implement the approved fixes, one function at a time. Run tests after each."

**Why chaining beats monolithic prompts:**

| Single Prompt | Chained Prompts |
|---------------|-----------------|
| Entire task must fit in working memory | Each step has focused context |
| Errors compound across steps | Course correction between steps |
| Hard to review intermediate reasoning | Each step produces reviewable output |
| Context fills on large codebases | Each step can start with clean context |

**Common chains:**

- **Bug fix:** Reproduce → Trace root cause → Propose fix → Implement → Verify
- **Feature:** Explore patterns → Plan → Implement backend → Implement frontend → Integration test
- **Review:** Summarize changes → Check security → Verify tests → Write summary

See [prompting-examples.md](../../../shared/principles/prompting-examples.md) for concrete examples with input/output pairs.

### Dev Docs Pattern

For features spanning multiple sessions, maintain a working document set:

```
project-docs/
├── feature-plan.md      # The accepted plan (update as you go)
├── feature-context.md   # Key files, decisions, constraints
└── feature-tasks.md     # Checklist of remaining work
```

These files serve as handoff documents between sessions. A fresh Claude instance can pick up exactly where the last one left off by reading these files first.

### Specification Quality

The quality of your specification directly determines output quality. Be specific about what you want.

**Vague (produces vague results):**
> Add a user settings page

**Specific (produces focused results):**
> Create a user settings page at /settings with:
>
> - Profile section (name, email, avatar upload)
> - Notification preferences (checkboxes for email/push)
> - Use existing UserProfile component from `src/components/`
> - Follow the existing MUI v7 layout grid pattern
> - Add tests for form validation

---

## Quality Gates & Hooks

### Test-Driven Development

Write tests before implementation. This is the single highest-leverage practice for code quality:

1. Write the test. Confirm it fails (rules out mock implementations).
2. Commit the test separately.
3. Implement until the test passes.
4. Do NOT modify tests during implementation — if the test seems wrong, that's a design signal.

### Continuous Validation

Run validation after every meaningful change:

- **TypeScript/linter checks** after every edit
- **Build validation** before commits
- **Test execution** on changes

Automate these with hooks. The most effective hook pattern is **block-at-commit** — let Claude write freely, but block `git commit` until tests pass. Don't block at write time; that interrupts flow. See: [learning-system-guide.md](learning-system-guide.md) for hook implementation patterns.

### Code Review

AI-generated code needs the same review rigor as human code. Effective patterns:

- **Self-review via subagent**: Spawn a fresh context to review the diff. Fresh eyes catch what the writing context normalized.
- **Multi-instance verification**: One Claude writes, another reviews. The reviewer has no sunk cost in the implementation decisions.
- **Manual human review**: Non-negotiable. Check behavior, test coverage, and architectural fit.

What to look for: unnecessary imports, missing error handling, API changes with incomplete impact analysis, spaghetti control flow, security issues.

Our experience: **self-verify every review finding before presenting it**. Wrong findings destroy reviewer credibility and cost more time to clean up than they save. See: [pr-review-protocol.md](pr-review-protocol.md)

---

## Tool Strategy

### Skills System

Skills (slash commands) are the primary way to codify reusable workflows. Keep them simple — a skill is a shortcut, not a complex workflow engine.

**The auto-activation problem**: Manual skills get forgotten ~90% of the time. Solve this with hooks:

- **UserPromptSubmit hook**: Analyzes the prompt for keywords/intent, injects a reminder to use the relevant skill before Claude processes the message.
- **Stop event hook**: Analyzes edited files for risky patterns (try-catch, DB ops, async), displays a non-blocking self-check reminder.

See: [../templates/skills/skill-design-guide.md](../templates/skills/skill-design-guide.md) for design patterns.

### MCP Strategy

Heavy MCP usage is an anti-pattern. If your MCP tools consume more than 20k tokens of context, they're crowding out working memory.

**Effective MCP design** (the "scripting model"):

| Bad Pattern | Better Pattern |
|-------------|----------------|
| Dozens of tools mirroring a REST API | Few powerful gateways |
| `read_user`, `read_org`, `read_team` | `download_raw_data(filters...)` |
| Rigid abstractions | MCP handles auth/security; Claude scripts against raw data |

Most stateless tools should be simple CLIs documented in skills, not MCP servers. Reserve MCP for stateful environments (e.g., browser automation, database connections).

### Subagents vs Clone Pattern

Two approaches to delegation:

| Approach | When to Use |
|----------|-------------|
| **Custom specialized subagents** | Highly specific, narrow tasks (PR review, build error resolution) with clear domain boundaries |
| **Clone pattern** (Task spawning) | Most other delegation; preserves full context, more flexible |

Default to the clone pattern. Custom subagents make sense when you need strict tool scoping or domain-specific system prompts. See: [../templates/agents/agent-design-guide.md](../templates/agents/agent-design-guide.md)

### Simple Control Loops

Resist the temptation to build complex multi-agent orchestration. Claude Code's own architecture is instructive: one main thread, maximum one branch (subagent), flat message list. No complex multi-agent graphs.

Every abstraction layer makes debugging exponentially harder. Simple iterative tool calling handles most tasks. Add complexity only when simple approaches demonstrably fail.

---

## Workflow Optimization

### Course Correction

Claude won't always take the right path. Know your correction tools:

1. **Ask for a plan first** — Confirm the approach before coding starts
2. **Press Escape** — Interrupt mid-generation; redirect without losing context
3. **Double-tap Escape** — Jump back in conversation history; edit a previous prompt
4. **Ask to undo** — Often combined with Escape to try a different approach

Active collaboration (reviewing, redirecting, correcting) usually produces better results than autonomous mode.

### Visual References

For UI work, visual references dramatically improve output quality:

1. Provide a screenshot or design mock as reference
2. Claude implements
3. Take a screenshot of the result
4. Compare to the reference, iterate
5. Usually 2-3 iterations for a good match

### Git Worktrees for Parallel Work

Run multiple Claude instances on independent tasks using git worktrees:

```bash
git worktree add ../project-feature-a feature-a
cd ../project-feature-a && claude

# In another terminal:
git worktree add ../project-feature-b feature-b
cd ../project-feature-b && claude
```

Best practices:
- One terminal tab per worktree
- Consistent naming conventions
- Separate IDE windows per worktree
- Clean up when done: `git worktree remove ../project-feature-a`

### Headless Mode

For automation and CI/CD integration, Claude Code runs headless:

**Fan-out pattern** (large migrations):
```bash
claude -p "migrate foo.py from React to Vue. Return OK or FAIL" \
  --allowedTools Edit "Bash(git commit:*)"
```

**Pipeline pattern**:
```bash
claude -p "<prompt>" --json | your_command
```

Use cases: issue triage, linting, code review, pre-commit checks, build scripts.

---

## Production Lessons

Patterns validated through extensive production use.

### Investigation is Not Implementation

When investigating a failure or reviewing code, the default output is a **report**, not a fix. Present findings and get explicit approval before transitioning from analysis to implementation. The user may want to fix it themselves, fix it differently, or defer it.

### Decision Checkpoints

Stop at decision points and present options before executing multi-step operations. Never chain destructive or state-changing steps without approval between each step. A plan approval does not imply blanket authorization — each phase needs its own confirmation.

### Finding Verification

Before presenting any finding (review comment, bug report, architectural concern):

1. Re-check it against the actual codebase
2. Verify against official docs or primary sources
3. If uncertain, downgrade the severity or drop the finding entirely

Wrong findings destroy credibility faster than missing findings. See: [pr-review-protocol.md](pr-review-protocol.md)

### Commit Hygiene

- Use conventional commit format: `type(scope): description`
- Never include AI attribution ("Generated by AI", "Claude", "Co-Authored-By")
- Commit early and often with meaningful messages
- Each commit should compile and pass tests
- Commit tests separately from implementation when doing TDD

### Operational Safety

These patterns prevent the most common production mistakes:

- **Re-verify state after context continuation** — Never trust summaries from a previous context window
- **Read before editing** — Never modify a file that hasn't been read in the current turn
- **Enumerate before destroying** — Produce an explicit list of what will be affected; get per-item confirmation
- **Fix diagnostics immediately** — Every warning is a finding; don't classify them as "minor" to avoid fixing them
- **Never dismiss unexpected diffs** — An unexpected diff means something WILL change on the next apply

See: [../../../shared/principles/operational-safety-patterns.md](../../../shared/principles/operational-safety-patterns.md)

### Context Budget Consolidation

As your configuration grows, always-loaded context (CLAUDE.md, rules, agent definitions) can silently consume your token budget. A common trajectory:

1. **Growth phase** — Rules accumulate as you encounter issues. One file per incident is easy to write.
2. **Bloat phase** — 50-60 rule files, 30-40K tokens of always-on context. Quality degrades because working memory is crowded.
3. **Consolidation phase** — Merge by domain, scope to directories, migrate niche content to on-demand docs.

A real-world consolidation reduced 60 rule files (~35K tokens) to 14 (~18K tokens) — a 50% reduction in baseline context cost. The approach:

| Action | Token Impact |
|--------|-------------|
| Merge related rules into one file per domain | Eliminates duplicate frontmatter and redundant context |
| Scope rules to directories via `paths:` frontmatter | Rules only load when working in relevant directories |
| Move niche rules to `.claude/docs/` (on-demand) | Zero cost until explicitly read |
| Extract workflows to skills | Zero cost until invoked |

**Audit periodically:** Count your always-on token budget with `wc -c .claude/rules/**/*.md CLAUDE.md` (rough: 4 chars ≈ 1 token). If it exceeds 15-20K tokens, consolidate.

### MCP Tool Definition Budget

Each MCP server's tool definitions consume context tokens in every session — even if you never call the tools. Cloud-synced MCPs from claude.ai connectors are particularly insidious: they're enabled by default and load silently.

Audit with `claude mcp list`. If you see servers you never use, remove them or disable cloud MCPs entirely with `ENABLE_CLAUDEAI_MCP_SERVERS=false`. See the [MCP Management Guide](mcp-management-guide.md#cloud-synced-mcp-hygiene) for details.

---

## Getting Started

### Week 1: Foundations

1. Create your `CLAUDE.md` — 100-200 lines max, focus on what Claude gets wrong
2. Practice the Explore → Plan → Code → Commit workflow
3. Start clearing context at 60k tokens
4. Review all AI-generated code manually

### Week 2: Quality Systems

1. Set up TDD workflow (tests first, commit separately)
2. Create 2-3 slash commands for common tasks
3. Implement a build-checker hook
4. Use visual references for UI work

### Week 3: Advanced Context

1. Implement the dev docs pattern (plan/context/tasks files)
2. Create 1-2 skills for your most common patterns
3. Add auto-activation hooks for skills
4. Use subagents for code review

### Week 4: Optimization

1. Audit context usage mid-session
2. Optimize CLAUDE.md (remove bloat, add conditional pointers)
3. Add quality gate hooks (tests, linting)
4. Experiment with git worktrees for parallel work

---

## Success Metrics

### Context Efficiency

- Baseline context cost: < 20k tokens (< 10% of context window)
- CLAUDE.md total size: < 2,000 tokens
- MCP tool definitions: < 20,000 tokens
- Context clearing frequency: every 60k tokens or sooner

### Code Quality

- Test coverage: > 80% for new code
- Zero linter/type errors before commits (enforced by hooks)
- Track common review findings; update CLAUDE.md when patterns emerge
- Production bugs from AI code should decrease over time

### Productivity

- Time from plan to PR: track and optimize
- Plan iterations: should stabilize at 1-3
- Context compactions needed: should decrease with better practices
- Parallel tasks with worktrees: can scale to 3-4 simultaneously

---

## Anti-Patterns

| Pattern | Why It Fails |
|---------|-------------|
| Auto-formatting hooks | Consumes 160k+ tokens in 3 rounds; run formatters manually |
| Heavy MCP usage (> 20k tokens) | Crowds out working memory |
| Complex multi-agent orchestration | Debugging becomes exponential; simple loops work better |
| RAG for code search | LLM-driven search (ripgrep + iterative reading) is simpler and more effective |
| Vague instructions | Produces vague results; specificity compounds |
| Skipping planning | Jumping straight to code leads to rework |
| Letting context fill to limits | Quality degrades well before hitting the wall |
| Embedding full docs in CLAUDE.md | Point to docs; let Claude read on demand |
| Rules with metadata (dates, counts) | Waste tokens; rules should be pure actionable guidance |

---

## Related Resources

- [Auto Memory Guide](auto-memory-guide.md) — Designing effective persistent memory for cross-session learning
- [Public Contribution Guide](public-contribution-guide.md) — End-to-end open source contribution workflow
- [Issue Writing Guide](issue-writing-guide.md) — Structuring effective issues and proposals
- [PII Prevention Guide](pii-prevention-guide.md) — Preventing sensitive data leakage in public repos
- [CLAUDE.md Design Guide](global-claude-md-guide.md) — How to structure your personal and project CLAUDE.md files
- [Agent Design Guide](../templates/agents/agent-design-guide.md) — Building specialized subagents with proper boundaries
- [Skill Design Guide](../templates/skills/skill-design-guide.md) — Creating slash commands for reusable workflows
- [Learning System Guide](learning-system-guide.md) — Automated knowledge capture from sessions
- [PR Review Protocol](pr-review-protocol.md) — Structured review with finding verification
- [Operational Safety Patterns](../../../shared/principles/operational-safety-patterns.md) — Session safety and destructive operation protocols
- [Portability Guide](portability-guide.md) — Dotfiles, symlinks, backups, and multi-machine setup
- [MCP Management Guide](mcp-management-guide.md) — Adding, removing, and managing MCP servers across scopes
- [Review Agent Trio](../templates/agents/review-agent-trio.md) — Specialized reviewer agents for higher-quality PR review
- [Session Analytics Guide](session-analytics-guide.md) — Mining session history for tool call waste patterns
- [Hooks Guide](hooks-guide.md) — Designing PreToolUse, PostToolUse, and Stop hooks
- [Settings JSON Guide](settings-json-guide.md) — Permissions, env vars, hook registration, layering
- [GitHub Actions Integration](github-actions-integration.md) — Claude Code in CI/CD via claude-code-action
- [Prompting Examples](../../../shared/principles/prompting-examples.md) — Multishot examples, XML structuring, prompt chaining demos
- [Scaffolding Directory](../scaffolding/) — Complete example `.claude/` directory ready to customize

---

## Sources

This guide synthesizes:
- Community best practices from [rosmur.github.io/claudecode-best-practices](https://rosmur.github.io/claudecode-best-practices/) (12-source synthesis)
- Production experience from a 40+ service monorepo with 11 specialized agents, automated learning hooks, and conditional rule loading
- Patterns documented throughout this repository
