# Batch Approval Grants

One prompt authorises a known-size set of identical guarded calls, instead of one prompt per call or a session-wide blanket approval.

This is a design pattern, not a shipped hook — the repo publishes the guards it gates ([`destructive-guard`](../hooks/destructive-guard/), [`pr-create-guard`](../hooks/pr-create-guard/)) but not a grant broker. It extends [`consent-gated-capabilities.md`](../../../../shared/principles/consent-gated-capabilities.md), which gates *whether* an expensive capability fires; this gates *how many times* a guarded one may fire on a single approval.

## When it applies

Before a run of N identical calls that a guard prompts on, where N is known up front — the canonical case being "open twelve tracker tickets for this epic". Declare the batch *before* the first call, so the prompt the user sees states the real scope.

Do not use it to make a single call quieter, and never to pre-authorise a set whose size the user has not seen.

## The user pre-approves the commands; approval is never assumed

Write the actual calls out, one line each, ask, and wait for an explicit yes before declaring the batch.

**A count is not a plan.** "Twelve tickets" says how many prompts are being traded away, not what is being authorised, and the whole value of batching is that the user can see the set at once instead of one call at a time. The first-call prompt is a backstop against a denied batch, not the consent mechanism — arriving at it without having shown the list means the batch was assumed rather than granted.

## Why staging cannot self-approve

The design property that makes this safe is that declaring a batch grants nothing on its own.

A `declare` step only *stages*. The first matching call still raises a prompt — the reason line just widens to name the whole batch ("1 of 12 · approving authorizes the remaining 11"). The grant flips to approved from a **PostToolUse** hook, which fires only after the call actually executed, and that can happen only if the user approved it.

So a denial unlocks nothing: the grant stays staged and expires at its TTL. There is no code path in which declaring a batch grants anything by itself. Build it this way or not at all — a staging step that approves itself is a blanket allow with extra ceremony.

## Bounds

Session-scoped, tool-scoped, count-capped, time-capped, revocable. Every one of those is load-bearing:

| Bound | Why |
|---|---|
| Session | A grant must not survive into a session the user did not arm |
| Tool | A grant for ticket creation must not clear a `git push` |
| Count | The user approved a set size; N+1 was never authorised |
| Time | An abandoned session must not stay armed indefinitely |
| Revocable | Handing the approvals back must be one command |

## Wiring a guard in

A guard opts in with two calls — consume before deciding, and a PostToolUse activator:

```bash
if "$GRANT" consume --tool "$TOOL_NAME" --session "$SESSION_ID" >/dev/null 2>&1; then
  exit 0   # silent exit falls through to the normal allow rule, raising no prompt
fi
BATCH=$("$GRANT" describe --tool "$TOOL_NAME" --session "$SESSION_ID" 2>/dev/null)
```

**A destructive-operations guard should deliberately not be wired in.** Teardown and deletion require itemized per-resource approval, which is exactly what a batch grant is designed to collapse.

## Worked refusal: no batch grant for `gh pr create`

Worth reading in full, because the reasoning is the transferable part — the volume argument is the one that loses.

Measured over 6.6 days of a guard's own ask log (823 asks, probe firings excluded), `gh pr create` was the second most batchable trigger:

| Trigger | Asks | Bursts | Largest | Removable by batching |
|---|---|---|---|---|
| `git branch -D` | 285 | 61 | 38 | 217 (76%) |
| `gh pr create` | 199 | 64 | 18 | 122 (61%) |
| `git push --force` | 103 | 50 | 8 | 42 (41%) |
| `gh run delete` | 0 | — | — | — |

It is still not wired, for a reason the volume cannot outvote: **that prompt exists because PRs were being opened without first verifying a PR was warranted.** Collapsing N of those confirmations into one removes exactly the check that was installed against that failure. The 122 "removable" prompts are the gate working, not waste.

Relocating the ask to the PR-creation guard (which already matches `gh pr create`) and wiring the grant there does not solve it, and is unsafe as a straight move besides: that hook exits 0 when `origin/main` does not resolve, so the confirmation disappears entirely in any repo whose default branch is not `main`.

**Reversal condition.** The objection is that the agent picks the count. It does not survive the pre-approval rule above: if the user is shown the exact commands and approves that specific set, the intent check has moved earlier and become *more* visible, not less. Revisit only with that mechanism actually in force — and note the relocation hole still needs fixing first if the ask is ever moved.

`gh run delete` fired **zero** times in the window. Any future proposal naming a trigger should show demand first.

## What this cannot do

It cannot suppress prompts on **protected paths** (`.claude`, `.git`, `.zshrc`, `.npmrc`, …). Verified empirically: a `PreToolUse` hook returning `permissionDecision: "allow"` fires and is ignored for those paths — the protected-path check sits above both hooks and `permissions.allow` rules. Only the permission *mode* changes that behaviour. Do not attempt to build a grant around it.
