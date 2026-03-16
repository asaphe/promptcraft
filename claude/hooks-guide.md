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

Hooks communicate back via stdout JSON:

| Field | Effect |
|-------|--------|
| `"decision": "block"` | Prevents the tool call (PreToolUse only) |
| `"reason": "..."` | Shown to Claude as the reason for blocking |
| No output / empty | Tool call proceeds normally |

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

1. **Global** (`~/.claude/settings.json`) — Apply everywhere
2. **Project** (`.claude/settings.json`) — Apply to this repo only
3. **Local** (`.claude/settings.local.json`) — Personal overrides, not committed

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

## Performance Considerations

- Hooks run synchronously — keep them fast (< 100ms ideally)
- Avoid network calls in PreToolUse hooks (they block every matching tool call)
- Use `matcher` patterns to narrow scope — don't run expensive checks on every tool call
- For expensive validation, consider PostToolUse (non-blocking) instead of PreToolUse

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Hook blocks everything because matcher is too broad | Use specific tool names or glob patterns |
| Hook silently fails (no output) | Always test with sample JSON before registering |
| Hook consumes too many resources | Profile with `time` command; keep under 100ms |
| Hook output isn't valid JSON | Validate with `jq` before deploying |
| Hook path is relative | Use absolute paths in settings.json |

## Related Resources

- [Learning System Guide](learning-system-guide.md) — Hooks for automated knowledge capture
- [Settings JSON Guide](settings-json-guide.md) — Where hooks are registered and how layering works
- [Skill Design Guide](skills/skill-design-guide.md) — Skills that hooks can auto-activate
- [Best Practices](claude-best-practices.md) — Quality gates and hook integration patterns
