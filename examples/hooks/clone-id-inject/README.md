# Clone ID Inject

A **UserPromptSubmit** hook that injects the current repo clone identity into the conversation context.

## Why

When working with multiple clones of the same repo (for parallel work on different features), the AI agent has no inherent awareness of which clone it's in. This leads to:

- Commits pushed to the wrong branch
- Files read from one clone, edits applied to another
- Confusion about which worktree has which changes

This hook adds ~50 characters of context per turn: `Working directory: myproject-3 clone (/home/user/myproject-3)`. The agent sees this on every message and can reference the correct clone.

## Behavior

The hook checks `$PWD` against a pattern of known clone directories. If it matches, it injects the clone identity. If not, it exits silently (zero token cost).

## Setup

1. Edit the script: change the `case` pattern to match your clone naming convention
2. Register as a UserPromptSubmit hook:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/clone-id-inject.sh"
          }
        ]
      }
    ]
  }
}
```

## Customization

**Worktree-based:** If you use git worktrees instead of clones:

```bash
# Detect worktree and inject branch name
WORKTREE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if git rev-parse --is-inside-work-tree &>/dev/null && [ "$(git rev-parse --show-toplevel)" != "$(git rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')" ]; then
  jq -n --arg ctx "In worktree: $WORKTREE_BRANCH ($PWD)" '{...}'
fi
```

**Always inject:** Remove the `case` guard to always inject the working directory, regardless of naming pattern.

## Token Cost

~50 tokens per user message. Over a 100-message session, that's ~5,000 tokens — negligible compared to the confusion cost of working in the wrong clone.
