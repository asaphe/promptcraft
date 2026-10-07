# Merge Grant

Per-turn grants: a **UserPromptSubmit** hook that lets the agent merge a PR, or open one without a second prompt, only in a turn whose prompt asked for it.

## Why

Both obvious defaults fail:

- **A hard block on every merge** means "merge #17" is a request the agent can never carry out, so a one-word ask sends the user to the forge UI.
- **A plain permission prompt** makes a merge approvable in *every* turn — including a resumed session where a stray keystroke answers a prompt nobody requested.

The grant keeps "unapprovable" as the default and lifts it only on the user's own words, until they next speak. It never makes a merge silent: the best a grant buys is a permission prompt.

Opening a PR has the opposite problem. It is a soft block that asks every time, so "open the PR" is followed by a permission prompt asking for the approval the user just gave. Here the grant removes the prompt for that turn instead of enabling one.

## How it works

| Piece | Event | Does |
|---|---|---|
| `merge-grant.sh` | UserPromptSubmit | A prompt that asks for an action writes that action's grant, with a two-hour expiry, and tells the model it is armed. The user's next prompt that does not ask again deletes it. |
| `merge-grant.sh` | PostToolUse on `AskUserQuestion` | A menu answer can arm `pr`, never `merge`, and clears nothing. See [Menu answers](#menu-answers). |
| [`destructive-guard.sh`](../destructive-guard/) | PreToolUse | Reads the grants. **`merge` armed:** `gh pr merge`, `gh api .../pulls/N/merge`, `gh api graphql` with `mergePullRequest` or `enablePullRequestAutoMerge`, and `gh stack merge` raise a permission prompt that quotes the request. Not armed: all four hard-block. **`pr` armed:** `gh pr create` runs without the guard's prompt. Not armed: it asks. |

| Action | Grant file | Lifts |
|---|---|---|
| `merge` | `<store>/<session_id>.json` | a hard block, to a permission prompt |
| `pr` | `<store>/<session_id>.pr.json` | a permission prompt, entirely |

The store is `$CLAUDE_MERGE_GRANT_DIR`, default `~/.claude/merge-grants`; both hooks read the same variable. Without this hook installed no grant is ever written, so the guard hard-blocks every merge and asks on every `gh pr create`. `--admin` anywhere in a `gh pr merge` command — including through a variable, `F=--admin; gh pr merge 17 $F` — hard-blocks either way: a grant covers the merge the user asked for, never one past branch protection.

The two-hour expiry is a backstop, not the lifetime. The lifetime is "until the user's next prompt". The expiry bounds the cases where that prompt never comes — a long CI wait, a session left open overnight.

## What arms it

**`merge`:** the word `merge` — not `merged`, `merging` or `mergeable` — used at least once outside the reach of a negation.

**`pr`:** `open`, `create` or `raise` outside the reach of a negation, followed within the next four words by `PR`, `PRs` or `pull request(s)` — `pull` alone is not a PR (`pull main`, `a pull-down menu`). `open` that starts its clause is the verb (`open PRs for both branches`); anywhere else it is the verb only when a determiner follows it — `a`, `an`, `the`, `this`, `that`, `these`, `those`, `my`, `our`, `your`, `its`, `their`, `one`, `two`, `both`, `new`, `another`, `separate` (`please open a PR`, `then open the two PRs`). Otherwise it is the adjective (`list my open PRs`, `list the open draft PRs`, `how many open dependabot PRs are there?`).

Negation is the same for both. `not`, `never`, `without`, `cannot`, any `…n't` word (`don't`, `can't`, `won't`, `shouldn't`, …) and the apostrophe-less `dont`, `cant`, `wont`, `shouldnt`, `couldnt` and `wouldnt` negate every later word in their clause. A clause ends at `. ; ! ?`, a line break, or `but`. A `,`, `:` or parenthesis is an aside inside the clause, so `Do not, under any circumstances, merge 17` stays negated. `no` negates only the word right after it, because it is usually a determiner (`there are no blockers so merge 17`, `no, merge it`). Hyphens, asterisks and quotes separate words without ending a clause, and a typographic or backtick apostrophe counts (`don’t merge`, ``don`t merge``).

| Prompt | Grant |
|---|---|
| `merge 1-8, 18. fix 19.` | merge |
| `Merge PR 17, but don't merge 19 until I look` | merge — the first clause asks |
| `don't close 19 but merge 17` | merge — `but` ends the negation |
| `I asked you not to merge` | none |
| `don't auto-merge this` | none |
| `the merged PR looks fine, what's the mergeable state?` | none |
| `looks good, open the PR` | pr |
| `create a PR for this, then merge it` | pr and merge |
| `don't open a PR yet` | none |
| `Don't (yet) open a PR` | none — the parenthesis does not end the negation |
| `how many open PRs do we have?` | none — `open` is the adjective |
| `list the open draft PRs` | none — no determiner after a mid-clause `open` |
| `the PR is open, what's its CI state?` | none — no verb before the PR |

The predicate is lexical, so it errs in both directions, and the errors cost different things. **Over-arming** — `should I merge this?` arms `merge`, `open questions on the PR` arms `pr` — costs one permission prompt the user can refuse for a merge. For a PR it costs more: a PR opened that nobody asked for, with no prompt. [`pr-create-guard`](../pr-create-guard/) still checks its prerequisites, not whether the user wanted it, so the PR side of the predicate leans toward under-arming. **Under-arming** — `it's not flaky so merge it` stays negated, and so does `don't wait, merge 17` — costs a re-phrase. It cannot tell *which* PRs were named: confirming an ambiguous list ("the ones above", a range) before the first merge is the agent's job, which the armed-grant context says in so many words.

## The pr grant

A `pr` grant removes a prompt, where a `merge` grant only enables one. The difference is deliberate. A merge lands shared state that is hard to take back, so even an asked-for merge keeps a permission prompt quoting the request. Opening a PR is visible but reversible, and in a turn whose prompt said "open the PR" the prompt only asks again for an approval the user just gave.

What still checks a `gh pr create` in a granted turn:

- **[`pr-create-guard`](../pr-create-guard/)** blocks it on missing prerequisites — zero diff, unpushed commits, uncommitted changes — grant or not.
- **Every other trigger in the same command** keeps its prompt. `gh pr create && gh run delete 5` still asks about the delete, and `gh stack submit`, which opens a PR for every layer, is not covered.
- **Hard blocks** stay hard.

## Menu answers

When the agent asks with `AskUserQuestion` and the user picks "Open the PR", a typed-words-only grant would follow that pick with a permission prompt for the same `gh pr create`. Registered on PostToolUse for `AskUserQuestion`, the hook reads each question and the answer picked for it, and arms `pr` when either:

- the answer itself asks for a PR, by the same test as a typed prompt (this covers a free-text "Other" reply); or
- the question asks for a PR, and the answer is a bare affirmation: every word in it is one of `yes`, `y`, `yep`, `yeah`, `ok`, `okay`, `sure`, `approve(d)`, `confirm(ed)`, `proceed`, `go`, `ahead`, `do`, `it` or `please`, ignoring punctuation and a `(Recommended)` suffix. `Yes, go ahead` consents. `Proceed with the e2e suite first`, `Go back and add tests first` and `Yes, but only after CI` do not: when a question offers alternatives, an answer that says anything more may be choosing one of them.

A bare "Yes" to a question that names no action arms nothing.

A menu answer **never arms `merge`**. The option text is written by the model, and a merge needs the user's own words. A menu answer also **clears nothing**, so confirming a PR list in a menu keeps a grant the typed prompt armed. The next typed prompt that does not ask again clears a menu grant like any other.

The hook reads the answers from `tool_response.answers`, falling back to `tool_input.answers`: an object mapping each question's text to the label picked. This shape is observed in current Claude Code transcripts, not a documented contract. If it changes, the menu path arms nothing and the typed path is unaffected.

## Harness-injected blocks

Some text reaches UserPromptSubmit as prompt text without the user writing it:

- **A background-task completion**, wrapped in `<task-notification>` … `</task-notification>`.
- **A message another agent sent this session**, such as a subagent's hand-back, wrapped in `<agent-message …>` … `</agent-message>`.

Both are observed behavior, not documented contracts. The hook strips every such block before reading the prompt:

- **A prompt that is only such blocks** neither arms nor clears. The turn it starts continues the user's last request, which is what lets "merge 17 when CI is green" finish after a background CI watch reports. The expiry bounds how long that can last.
- **A prompt with the user's own words around a block** is the user speaking. Only their words count, so a pasted "ready to merge" or a worker's "open the PR" arms nothing, and "actually, do NOT merge anything" clears the grant.
- **If the strip itself fails, or leaves a tag behind**, every grant is cleared, never armed from the raw prompt. A block's body can quote its own closing tag — an agent reporting what it grepped, say — and the strip ends that block early; the remainder is not the user's words. A typed prompt that mentions one of these tags literally is caught by the same check: it clears, and the user re-phrases.

## Fails closed

Every state short of a live grant is the default — a hard block for a merge, a prompt for a PR:

- no `session_id` in the payload, or one containing anything but `A-Z a-z 0-9 _ -` (the id becomes a file name, so a `../` cannot reach a grant outside the store)
- no grant file, an unparseable one, or an `expires_at` that is missing, non-integer or past
- a grant written for a different session

## What it does not protect against

- **A forged grant.** The store is a directory the agent's own shell can write. A forged `merge` grant still only turns a hard block into a prompt, so it buys a question the user answers, never a merge. A forged `pr` grant skips a prompt that `pr-create-guard` still backs. Do not pair either with a permission rule that auto-approves merges.
- **A grant that outlives a skipped hook.** A grant ends when this hook next runs. If it does not run — unregistered, removed, failing to start — an existing grant lasts until it expires. A missing `jq` or `perl`, or an unusable session id, stops this hook early, but the guard then falls back to its default on its own for the same reason.
- **Spellings a command-text guard cannot read.** The mutation in a `--input` or `-F query=@file` payload, a raw HTTP call, or a command assembled in `eval` never reaches the guard as text.
- **Unattended sessions.** A [capability ceiling](../../../guides/unattended-mode-guide.md) that hard-blocks merges or PR creation still wins: any hook's exit 2 blocks the call, whatever another hook answered.

## Setup

Register it on both events, alongside `destructive-guard.sh`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/merge-grant/merge-grant.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/merge-grant/merge-grant.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/destructive-guard/destructive-guard.sh" }
        ]
      }
    ]
  }
}
```

The PostToolUse entry is optional: without it, menu answers arm nothing and only typed prompts do. Requires `jq` and `perl`. To go back to the defaults, unregister this hook **and** empty the store (`rm -f ~/.claude/merge-grants/*.json`, or your `$CLAUDE_MERGE_GRANT_DIR`): the guard honours a grant already on disk until it expires, and with the hook gone nothing deletes it. The guard itself needs no change.

## Testing

Run from the repository root:

```bash
# Which prompts arm a grant, and proof the fixture notices when that breaks
python3 tools/claude/examples/hook-tests/run-fixtures.py merge-grant --hooks-dir tools/claude/examples/hooks
python3 tools/claude/examples/hook-tests/mutate-fixtures.py --hooks-dir tools/claude/examples/hooks merge-grant

# The two hooks together: every merge form, the pr grant, menu answers, the grant's lifetime,
# harness-injected blocks, session scoping, fail-closed states
python3 tools/claude/examples/hook-tests/test-merge-grant.py
```

The two hooks share one contract, the grant files, so neither hook's own suite can see it break — `test-merge-grant.py` exists for that seam. The fixture file shows only *that* a grant was armed; `test-merge-grant.py` checks *which* one. Each of its merge `ask` cases answers `hard` against a guard with no grant path, and each pr `allow` case answers `ask` against one, which is what keeps them from passing vacuously.
