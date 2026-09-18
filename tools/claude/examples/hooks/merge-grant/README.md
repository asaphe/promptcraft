# Merge Grant

A **UserPromptSubmit** hook that lets the agent merge a PR only in the turn whose prompt asked for it.

## Why

Both obvious defaults fail:

- **A hard block on every merge** means "merge #17" is a request the agent can never carry out, so a one-word ask sends the user to the forge UI.
- **A plain permission prompt** makes a merge approvable in *every* turn — including a resumed session where a stray keystroke answers a prompt nobody requested.

The grant keeps "unapprovable" as the default and lifts it for exactly one turn, on the user's own words. It never makes a merge silent: the best a grant buys is a permission prompt.

## How it works

| Piece | Event | Does |
|---|---|---|
| `merge-grant.sh` | UserPromptSubmit | A prompt that asks for a merge writes `<store>/<session_id>.json` with a two-hour expiry and tells the model the grant is armed. Every other prompt deletes it. |
| [`destructive-guard.sh`](../destructive-guard/) | PreToolUse | Reads the grant. Armed: `gh pr merge`, `gh api .../pulls/N/merge` and `gh stack merge` raise a permission prompt that quotes the request. Not armed: all three hard-block. |

The store is `$CLAUDE_MERGE_GRANT_DIR`, default `~/.claude/merge-grants`; both hooks read the same variable. Without this hook installed no grant is ever written, so the guard behaves as a hard block on every merge. `gh pr merge --admin` hard-blocks either way: a grant covers the merge the user asked for, never one past branch protection.

The two-hour expiry is a backstop, not the lifetime. The next prompt clears the grant, so it normally lasts one turn; the expiry covers a turn that outlives its user — a long CI wait, a session resumed the next day.

## What arms it

The word `merge` — not `merged`, `merging` or `mergeable` — used at least once without a negation directly before it: `don't`, `dont`, `do not`, `not`, `never`, `no`, `without`. A `yet` in between is skipped (`don't yet merge`), a typographic apostrophe counts (`don’t merge`), and punctuation ends a negation (`no, merge it` arms).

| Prompt | Grant |
|---|---|
| `merge 1-8, 18. fix 19.` | armed |
| `Merge PR 17, but don't merge 19 until I look` | armed — one un-negated use is enough |
| `don't merge yet` | cleared |
| `the merged PR looks fine, what's the mergeable state?` | cleared |

The predicate is deliberately loose in one direction. **Over-arming** costs one permission prompt the user can refuse; **under-arming** costs a re-phrase. It cannot tell *which* PRs were named — the prompt quotes the request so the approver can compare, and confirming an ambiguous list ("the ones above", a range) before the first merge is the agent's job, which the armed-grant context says in so many words.

## Fails closed

Every state short of a live grant is a hard block:

- no `session_id` in the payload, or one containing anything but `A-Z a-z 0-9 _ -` (the id becomes a file name, so a `../` cannot reach a grant outside the store)
- no grant file, an unparseable one, or an `expires_at` that is missing, non-integer or past
- a grant written for a different session

In practice, background-task completions can reach UserPromptSubmit as prompt text wrapped in `<task-notification>`. That is not the user speaking, so it neither arms nor clears. This is observed behavior, not a documented contract.

## What it does not protect against

- **A forged grant.** The store is a directory the agent's own shell can write. A forged grant still only turns a hard block into a prompt, so it buys a question the user answers, never a merge. Do not pair it with a permission rule that auto-approves merges.
- **Unattended sessions.** A [capability ceiling](../../../guides/unattended-mode-guide.md) that hard-blocks merges still wins: any hook's exit 2 blocks the call, whatever another hook answered.

## Setup

Register it alongside `destructive-guard.sh`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "/path/to/merge-grant.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/path/to/destructive-guard.sh" }
        ]
      }
    ]
  }
}
```

Requires `jq`. To go back to a hard block on every merge, unregister this hook — the guard needs no change.

## Testing

Run from the repository root:

```bash
# Which prompts arm a grant, and proof the fixture notices when that breaks
python3 tools/claude/examples/hook-tests/run-fixtures.py merge-grant --hooks-dir tools/claude/examples/hooks
python3 tools/claude/examples/hook-tests/mutate-fixtures.py --hooks-dir tools/claude/examples/hooks merge-grant

# The two hooks together: every merge form, one-turn lifetime, session scoping, fail-closed states
python3 tools/claude/examples/hook-tests/test-merge-grant.py
```

The two hooks share one contract, the grant file, so neither hook's own suite can see it break — `test-merge-grant.py` exists for that seam. Each of its `ask` cases answers `hard` against a guard with no grant path, which is what keeps them from passing vacuously.
