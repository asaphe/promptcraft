# Merge Grant

A **UserPromptSubmit** hook that lets the agent merge a PR only after a prompt in which the user asked for it.

## Why

Both obvious defaults fail:

- **A hard block on every merge** means "merge #17" is a request the agent can never carry out, so a one-word ask sends the user to the forge UI.
- **A plain permission prompt** makes a merge approvable in *every* turn — including a resumed session where a stray keystroke answers a prompt nobody requested.

The grant keeps "unapprovable" as the default and lifts it only on the user's own words, until they next speak. It never makes a merge silent: the best a grant buys is a permission prompt.

## How it works

| Piece | Event | Does |
|---|---|---|
| `merge-grant.sh` | UserPromptSubmit | A prompt that asks for a merge writes `<store>/<session_id>.json` with a two-hour expiry and tells the model the grant is armed. The user's next prompt that does not ask again deletes it. |
| [`destructive-guard.sh`](../destructive-guard/) | PreToolUse | Reads the grant. Armed: `gh pr merge`, `gh api .../pulls/N/merge`, `gh api graphql` with `mergePullRequest` or `enablePullRequestAutoMerge`, and `gh stack merge` raise a permission prompt that quotes the request. Not armed: all four hard-block. |

The store is `$CLAUDE_MERGE_GRANT_DIR`, default `~/.claude/merge-grants`; both hooks read the same variable. Without this hook installed no grant is ever written, so the guard hard-blocks every merge. `--admin` anywhere in a `gh pr merge` command — including through a variable, `F=--admin; gh pr merge 17 $F` — hard-blocks either way: a grant covers the merge the user asked for, never one past branch protection.

The two-hour expiry is a backstop, not the lifetime. The lifetime is "until the user's next prompt". The expiry bounds the cases where that prompt never comes — a long CI wait, a session left open overnight.

## What arms it

The word `merge` — not `merged`, `merging` or `mergeable` — used at least once outside the reach of a negation. `don't`, `dont`, `not`, `never` and `without` negate every later word in their clause; a clause ends at `. , ; : ! ? ( )`, a line break, or `but`. `no` negates only the word right after it, because it is usually a determiner (`there are no blockers so merge 17`). Hyphens, backticks, asterisks and quotes separate words without ending a clause, and a typographic apostrophe counts (`don’t merge`).

| Prompt | Grant |
|---|---|
| `merge 1-8, 18. fix 19.` | armed |
| `Merge PR 17, but don't merge 19 until I look` | armed — the first clause asks |
| `don't close 19 but merge 17` | armed — `but` ends the negation |
| `I asked you not to merge` | cleared |
| `don't auto-merge this` | cleared |
| `the merged PR looks fine, what's the mergeable state?` | cleared |

The predicate is lexical, so it errs in both directions, and the two errors cost different things. **Over-arming** — a question such as `should I merge this?` arms — costs one permission prompt the user can refuse, and the prompt quotes the question they asked. **Under-arming** — `it's not flaky so merge it` stays negated — costs a re-phrase. It cannot tell *which* PRs were named: confirming an ambiguous list ("the ones above", a range) before the first merge is the agent's job, which the armed-grant context says in so many words.

## Background-task notifications

In practice, a background-task completion can reach UserPromptSubmit as prompt text wrapped in `<task-notification>` … `</task-notification>`. This is observed behavior, not a documented contract. The hook strips every such block before reading the prompt:

- **A prompt that is only notifications** neither arms nor clears. The turn it starts continues the user's last request, which is what lets "merge 17 when CI is green" finish after a background CI watch reports. The expiry bounds how long that can last.
- **A prompt with the user's own words around a pasted notification** is the user speaking. Only their words count, so a pasted "ready to merge" arms nothing, and "actually, do NOT merge anything" clears the grant.

## Fails closed

Every state short of a live grant is a hard block:

- no `session_id` in the payload, or one containing anything but `A-Z a-z 0-9 _ -` (the id becomes a file name, so a `../` cannot reach a grant outside the store)
- no grant file, an unparseable one, or an `expires_at` that is missing, non-integer or past
- a grant written for a different session

## What it does not protect against

- **A forged grant.** The store is a directory the agent's own shell can write. A forged grant still only turns a hard block into a prompt, so it buys a question the user answers, never a merge. Do not pair it with a permission rule that auto-approves merges.
- **A grant that outlives a skipped hook.** The grant ends when this hook next runs. If it does not run — unregistered, removed, failing to start — an existing grant lasts until it expires. A missing `jq` or `perl`, or an unusable session id, stops this hook early, but the guard then refuses the merge on its own for the same reason.
- **Merge spellings a command-text guard cannot read.** The mutation in a `--input` or `-F query=@file` payload, a raw HTTP call, or a command assembled in `eval` never reaches the guard as text.
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

Requires `jq` and `perl`. To go back to a hard block on every merge, unregister this hook **and** empty the store (`rm -f ~/.claude/merge-grants/*.json`, or your `$CLAUDE_MERGE_GRANT_DIR`): the guard honours a grant already on disk until it expires, and with the hook gone nothing deletes it. The guard itself needs no change.

## Testing

Run from the repository root:

```bash
# Which prompts arm a grant, and proof the fixture notices when that breaks
python3 tools/claude/examples/hook-tests/run-fixtures.py merge-grant --hooks-dir tools/claude/examples/hooks
python3 tools/claude/examples/hook-tests/mutate-fixtures.py --hooks-dir tools/claude/examples/hooks merge-grant

# The two hooks together: every merge form, the grant's lifetime, notifications, session scoping, fail-closed states
python3 tools/claude/examples/hook-tests/test-merge-grant.py
```

The two hooks share one contract, the grant file, so neither hook's own suite can see it break — `test-merge-grant.py` exists for that seam. Each of its `ask` cases answers `hard` against a guard with no grant path, which is what keeps them from passing vacuously.
