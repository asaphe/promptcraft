# Learning Capture System

A set of three hooks that automatically detect corrections and patterns from Claude Code sessions and queue them for review as candidate rules.

## How it works

```text
SessionStart ──→ Check pending learnings → Inject into context
                                            ↓
                              (Claude works, user corrects)
                                            ↓
PreCompact ────→ Scan for corrections → Append to pending file
                                            ↓
SessionEnd ────→ Scan full transcript → Append to pending file
                                            ↓
                              (Next session starts)
                                            ↓
SessionStart ──→ "2 pending learnings found" → Claude proposes rules
```

## Components

### `session-start-learnings.sh` (SessionStart, blocking, 5s timeout)

Checks for pending learning candidates from previous sessions. If found, injects a message into Claude's context prompting it to review and propose rules.

### `session-end-learnings.sh` (SessionEnd, async, 30s timeout)

Scans the session transcript for correction signals:

- User corrections ("no", "wrong", "not that", "I said", "actually,")
- Retry patterns (same tool called repeatedly — indicates confusion)
- Long sessions (50+ tool calls — may indicate complexity or confusion)

Writes candidates to `pending-learnings.md` with session metadata.

### `precompact-preserve.sh` (PreCompact auto, async, 15s timeout)

Runs before context compaction. Scans recent transcript for corrections that haven't been captured yet. Prevents correction context from being lost during compaction.

## Signal detection

The hooks look for these patterns in user messages:

| Signal | Pattern | Threshold |
|--------|---------|-----------|
| User correction | Messages starting with "no", "wrong", "not that", "I said" | 2+ corrections |
| Retry pattern | Same tool name appearing consecutively | Any duplicates |
| Long session | Total tool call count | 50+ calls |
| Message length | Correction messages must be 30+ chars | Filters false positives |

## Output format

Candidates are written to `memory/pending-learnings.md`:

```markdown
## Session abc123 (2025-03-23T19:30:00Z)

- **Working directory:** /path/to/repo
- **Tool calls:** 45
- **Corrections detected:** 3
- **Retry patterns:** 1

### Correction signals

​```
no, that's not right — use terraform workspace list first
actually, the profile should be prod-tf not prod
​```

---
```

## Classification

When Claude reads pending learnings, it classifies each as:

- **Team-wide** → `.claude/rules/{subdirectory}/{rule}.md` (shared via git)
- **Agent-specific** → `.claude/agents/{agent}.md` (shared via git)
- **Personal** → auto memory (not shared)

## Layer

**Project** (`.claude/settings.json`) — Shared learning system, entire team benefits from captured patterns.

## Settings configuration

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start-learnings.sh",
        "timeout": 5
      }]
    }],
    "SessionEnd": [{
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-end-learnings.sh",
        "async": true,
        "timeout": 30
      }]
    }],
    "PreCompact": [{
      "matcher": "auto",
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/precompact-preserve.sh",
        "async": true,
        "timeout": 15
      }]
    }]
  }
}
```
