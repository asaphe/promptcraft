# tools/cursor/recovery/

Utilities for Cursor's local state — recover lost chat history, sync conversations across workspaces.

## Contents

- `sync_conversations_to_workspace.py` — copies conversation metadata from Cursor's global storage into a workspace's `allComposers` list so prior chats become visible in a freshly-opened workspace.

## When to run

- You opened a new workspace and your conversation history isn't showing up.
- You moved a project directory and Cursor lost the link to prior chats.

## Prerequisites

1. Close Cursor: `killall Cursor`
2. Run: `python3 sync_conversations_to_workspace.py [workspace_hash]`
3. Reopen Cursor.

Script creates a timestamped backup under `~/cursor-conversation-history/backups/` before mutating state.

## Caveats

- Cursor's internal storage format can change between versions. If the script fails after a Cursor update, inspect the schema before re-running.
- This is a workaround for a gap in Cursor's own UX; upstream may ship a proper fix at any time.
