# Claude Code Hooks Guide

Hooks are shell commands that execute automatically in response to Claude Code events. They enable validation, guardrails, automation, and quality gates without consuming context window tokens.

## Hook Types

| Hook | When It Fires | Use Cases |
|------|--------------|-----------|
| `PreToolUse` | Before a tool call executes | Block dangerous commands, validate parameters, inject context |
| `PostToolUse` | After a tool call completes | Verify results, capture learnings, trigger follow-up actions |
| `Notification` | When Claude Code sends a notification | Custom alerting, logging, external integrations |
| `Stop` | When Claude finishes a response | Self-check reminders, structured output, handoff prompts |
| `SubagentStop` | When a subagent completes | Aggregate results, chain to next agent |

## Registration

Hooks are defined in `settings.json` (global `~/.claude/settings.json` or project `.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/validate-bash.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/on-stop.sh"
          }
        ]
      }
    ]
  }
}
```

### Matcher Patterns

- **Empty string `""`** — Matches all tool calls / all events
- **Tool name `"Bash"`** — Matches only that specific tool
- **Glob pattern `"Bash(*git*)*"`** — Matches tool calls where the input contains the pattern

### Hook Input

Hooks receive a JSON payload on stdin with context about the event:

```json
{
  "session_id": "abc123",
  "tool_name": "Bash",
  "tool_input": { "command": "git push --force" }
}
```

### Hook Output

Hooks communicate back via exit codes and optional stdout/stderr:

| Exit Code | Effect |
|-----------|--------|
| `0` | Tool call proceeds (default). Optional JSON stdout for advisory signals. |
| `2` | **Hard block** — tool call is stopped before permission rules are evaluated. Reason on stderr is shown to Claude. |
| Other non-zero | Treated as hook error; tool call proceeds. |

#### Hard Blocks (exit 2) vs Soft Blocks (JSON)

This distinction is critical for hooks that coexist with wildcard permissions like `Bash(*)`:

| Method | How | Overridden by allow list? |
|--------|-----|--------------------------|
| `exit 2` + stderr | Hard block — stops before permissions | **No** — always blocks |
| JSON `"decision": "block"` + `exit 0` | Soft signal — evaluated with permissions | **Yes** — `Bash(*)` overrides it |

**Always use exit code 2 for safety guardrails.** If your hook uses JSON `"decision": "block"` with exit 0, and the user has `Bash(*)` in their allow list, the block is silently overridden — the command executes without any prompt.

```bash
# Hard block pattern (recommended for safety hooks)
if [ -n "$REASON" ]; then
  echo "$REASON" >&2
  exit 2
fi

# Soft block pattern (for advisory hooks where allow list should win)
if [ -n "$REASON" ]; then
  jq -n --arg r "$REASON" '{"decision":"block","reason":$r}'
  exit 0
fi
```

## Design Patterns

### 1. Validation Guardrails (PreToolUse)

Block dangerous operations before they execute:

```bash
#!/bin/bash
# validate-bash.sh — Block destructive git commands
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE '(git push --force|git reset --hard|rm -rf)'; then
  echo '{"decision": "block", "reason": "Destructive command blocked. Use --force-with-lease or confirm with user first."}'
fi
```

### 2. Quality Gates at Commit (PreToolUse)

Block commits until tests pass:

```bash
#!/bin/bash
# pre-commit-gate.sh — Matched on "Bash" with pattern containing "git commit"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -q 'git commit'; then
  if ! npm test --silent 2>/dev/null; then
    echo '{"decision": "block", "reason": "Tests failing. Fix tests before committing."}'
  fi
fi
```

### 3. Self-Check Reminders (Stop)

Display non-blocking reminders after Claude finishes:

```bash
#!/bin/bash
# stop-check.sh — Analyze edited files for risky patterns
INPUT=$(cat)
# Parse session context, check for patterns like try-catch without logging,
# async without error handling, DB operations without transactions
echo '{"message": "Reminder: Check error handling in async functions and DB operations."}'
```

### 4. Skill Auto-Activation (PreToolUse)

Inject skill reminders based on prompt content. This solves the problem of manual skills being forgotten ~90% of the time:

```bash
#!/bin/bash
# auto-activate.sh — Matched on UserPromptSubmit
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')

if echo "$PROMPT" | grep -qiE '(deploy|release|rollout)'; then
  echo '{"message": "Consider using /deploy skill for this task."}'
fi
```

### 5. Learning Capture (PostToolUse)

Capture patterns and corrections for the learning system:

```bash
#!/bin/bash
# capture-learning.sh — Log tool usage patterns for later analysis
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
echo "[$(date -Iseconds)] $TOOL" >> ~/.claude/tool-usage.log
```

## Testing Hooks

Test hooks by piping sample JSON:

```bash
echo '{"tool_name": "Bash", "tool_input": {"command": "git push --force"}}' | ./validate-bash.sh
```

Verify the output matches expectations before registering.

## Hook Layering

Hooks follow the same layering as settings:

1. **Global** (`~/.claude/settings.json`) — Apply everywhere, personal to your machine
2. **Project** (`.claude/settings.json`) — Apply to this repo only, committed and shared with the team
3. **Local** (`.claude/settings.local.json`) — Personal overrides for this repo, not committed

### Choosing the Right Layer

| Hook Type | Best Layer | Why |
|-----------|-----------|-----|
| Auto-lint on edit (PostToolUse) | **Project** | Everyone benefits from consistent formatting |
| Destructive command guard (PreToolUse) | **Global** | Personal safety preference, applies everywhere |
| Pre-push quality gate (PreToolUse) | **Global** | Personal quality bar, may differ between team members |
| Learning capture (SessionStart/End) | **Project** | Shared learning system, team-wide benefit |
| Stale reference detection | **Project** | Repo-specific validation, committed with the repo |
| Notification on idle (Notification) | **Global** | Personal workflow preference |

**Principle:** If the hook enforces a team standard (linting, formatting, testing), put it at project level. If it reflects a personal preference (safety guards, notifications, quality bar), put it at global level. If it's experimental, put it at local level until proven.

Multiple hooks on the same event run sequentially. If any PreToolUse hook returns `"block"`, the tool call is prevented.

## Token Optimization via Command Rewriting

A high-impact PreToolUse pattern is rewriting CLI commands through a token-optimized proxy. Tools like [RTK (Rust Token Killer)](https://github.com/rtk-ai/rtk) intercept Bash commands and filter verbose output, achieving 60-90% token savings on common developer operations (git, terraform, kubectl, aws CLI).

The hook pattern is a thin delegator:

1. Hook receives the Bash command from stdin JSON
2. Delegates to an external binary for rewrite logic (single source of truth)
3. Returns the rewritten command via `updatedInput` in the hook response
4. Gracefully degrades (exits 0 with no output) if the binary is missing or too old

**Key design insight:** Keep rewrite rules in the external tool, not the hook script. This lets the tool maintain its own registry of supported commands and keeps the hook script stable across updates.

See `../examples/hooks/rtk/` for a production implementation.

**Gotcha:** Token-optimized output can truncate list commands, causing Claude to conclude a resource doesn't exist when it does. For commands where a missing entry changes the decision (workspace lists, secret inventories, image registries), bypass the proxy and use the raw command.

### Destructive Operation Guard

A two-tier PreToolUse hook for destructive operations. **Hard blocks** (exit 2) for irreversible data loss — cannot be overridden. **Soft blocks** (JSON + exit 0) for risky-but-approvable actions — user sees a warning and can approve in the permission prompt.

This solves the tension between safety and usability: `exit 2` for everything is too strict (blocks operations the user explicitly asked for), while JSON-only is too weak (`Bash(*)` silently overrides it).

See `../examples/hooks/destructive-guard/` for a production implementation with two-tier blocking, customization examples for Terraform, kubectl, Helm, and AWS.

## Hooks vs Rules Decision Framework

Hooks and rules serve different purposes. Choosing wrong leads to either wasted overhead (hook for something that needs judgment) or unreliable enforcement (rule for something that must always happen).

| Signal | Use a Hook | Use a Rule |
|--------|-----------|-----------|
| Must be enforced 100% of the time | Yes (deterministic) | No (can be forgotten under context pressure) |
| Requires context or judgment to apply | No (hooks are binary) | Yes (rules guide reasoning) |
| Blocks a specific tool/command pattern | PreToolUse with matcher | Not enforceable as a rule |
| Guidance for approach or style | Overkill | Yes (rules shape behavior) |
| Performance-sensitive (runs on every call) | Must be < 100ms | N/A (rules are just text in context) |
| Formatting or linting | PostToolUse (auto-fix after edit) | Unreliable (agent may skip) |

**Key principle:** Hooks enforce; rules guide. If the behavior can be expressed as "block X when Y", use a hook. If it requires the agent to weigh trade-offs ("prefer X but consider Y"), use a rule.

**Migration path:** When a rule is violated repeatedly despite being clearly stated, escalate it to a hook. The rule failed as advisory guidance — deterministic enforcement is needed. See the [poka-yoke section](claude-best-practices.md#instruction-design-principles) for the full preference order.

## Failure Modes

Hooks can fail silently, leaving the impression they're protecting you when they aren't.

| Failure Mode | Symptom | Prevention |
|-------------|---------|------------|
| Script not executable | Tool call proceeds unblocked | `chmod +x` and test before registering |
| Invalid JSON output | Claude treats output as empty (proceeds) | Pipe through `jq` in testing |
| Script exits non-zero without JSON | Treated as "no opinion" (proceeds) | Always exit 0; use JSON `decision` field to block |
| Matcher too broad | Every tool call triggers the hook | Test matcher against common tool calls (`Edit`, `Read`, `Bash`) |
| Matcher too narrow | Hook never fires for target pattern | Test with exact tool input strings from a real session |
| Hook timeout | Kills hook, proceeds without it | Add `timeout 2` wrapper; profile with `time` |
| Reads `$ENV_VAR` instead of stdin | Gets empty input, exits with no effect | Hooks receive JSON on stdin, not env vars |

**Testing protocol:** Before registering a hook, test it with realistic input:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | ./your-hook.sh
```

Verify the output is valid JSON and the exit code is 0.

## Performance Considerations

- **Budget: < 100ms for PreToolUse, < 500ms for PostToolUse/Stop** — PreToolUse blocks the tool call interactively; PostToolUse runs after completion
- Avoid network calls in PreToolUse hooks (they block every matching tool call)
- Use `matcher` patterns to narrow scope — don't run expensive checks on every tool call
- For expensive validation, consider PostToolUse (non-blocking) instead of PreToolUse
- **Measure before deploying:** `time echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | ./hook.sh`
- **Total hook overhead** per tool call should stay under 200ms across all matching hooks combined

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Hook blocks everything because matcher is too broad | Use specific tool names or glob patterns |
| Hook silently fails (no output) | Always test with sample JSON before registering |
| Hook consumes too many resources | Profile with `time` command; keep under 100ms |
| Hook output isn't valid JSON | Validate with `jq` before deploying |
| Hook path is relative | Use absolute paths or `$CLAUDE_PROJECT_DIR` in settings.json |
| Hook reads env vars instead of stdin | Claude Code passes hook data on stdin as JSON |

## Related Resources

- [Learning System Guide](learning-system-guide.md) — Hooks for automated knowledge capture
- [Settings JSON Guide](settings-json-guide.md) — Where hooks are registered and how layering works
- [Skill Design Guide](skills/skill-design-guide.md) — Skills that hooks can auto-activate
- [Best Practices](claude-best-practices.md) — Quality gates and hook integration patterns
