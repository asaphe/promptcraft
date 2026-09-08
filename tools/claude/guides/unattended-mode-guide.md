# Unattended Mode — a Capability Ceiling, Not a Permission Mode

A session armed unattended is a **productive autonomous loop with an absolute ceiling**. It may research, read, open tickets, write code, open a PR, watch CI and keep fixing what CI finds. It may never merge, never apply, never destroy.

The ceiling is the point. The risk being engineered away is returning to discover the session deleted production, applied a plan, or landed a PR — so those are not "ask" cases with nobody to answer them. They are refusals with no approval path at all.

This is the [`consent-gated-capabilities`](../../../shared/principles/consent-gated-capabilities.md) thesis applied end to end: an enumerated list decides, not a judgment call made under pressure at 3am with no human watching.

## Why a ceiling beats a permission mode

A permission mode asks "may this session approve things?" and answers yes or no for everything at once. Neither answer is what you want overnight: yes is a blanket allow, and no turns every gate into a hang — a prompt emitted into a session with nobody to answer it is worse than a refusal, because the loop stops without reporting why.

A ceiling asks a different question: "is this act recoverable after the fact?" That splits cleanly, and the split is stable enough to enumerate.

## The policy table

| Class | Unattended behaviour | Members |
|---|---|---|
| **Never** | Hard block, no approval path — stop and report | merge in every spelling, `terraform apply` / `destroy` / `state rm`, `helm uninstall` / `rollback`, `kubectl apply` / `delete` / `patch` / `scale` / `drain`, every destructive cloud verb, push to the default branch, PR close, **remote branch deletion in either spelling** (`push origin :branch`, `push --delete`), a review verdict, posting a new inline finding, deleting a comment |
| **Allowed** | Runs with no prompt | read-only research and diagnostics, ticket creation, **git on a branch this session owns** — commit, push, force-push, `reset --hard`, `rebase`, `cherry-pick`, `revert`, branch switch, `restore` — reading CI and review-bot comments, posting a PR comment, editing code, PR creation and PR body edits. Every one of their own gates still runs |
| **Everything else** | Hard block — **default deny** | anything not classified above |

**Default-deny on the third row is what makes the guarantee hold for commands nobody has classified yet.** A destructive verb added to any tool is refused unattended on the day it appears, without anyone having to remember to list it. Without that row the policy is an allowlist of known dangers, which is a denylist wearing a disguise, and it decays every time a vendor ships a new subcommand.

### Why git is allowed, and where the line falls inside it

An unattended loop that opens a PR and then fixes what CI finds is the whole point of the mode, and it dies on `git rebase` — a reflog-recoverable local operation — if git is gated wholesale. Meanwhile `terraform apply` and `kubectl patch` are the risk the mode was built to stop. Those are not the same class and should not share a rule.

**The membership test is: nothing in the allowed row can mutate infrastructure, and every member is recoverable after the fact.**

Two git shapes stay in the never row, and both are the same act rather than an abundance of caution: **deleting a remote branch auto-closes its PR**, which is PR-close wearing a git spelling. A push naming a ref *set* the guard cannot resolve (`--all`, `--mirror`, `--tags`, `--prune`, a bare colon refspec) is withheld for the same reason — the branch it would delete is not derivable from the command text. Push to the default branch was already hard, force or not.

### Scope a carve-out by act *and* by content

If you carve out a class — say, replying in a review thread on an internal repo — keep it narrow on two axes:

- **By act.** A new inline finding still hard-blocks, a review verdict still prompts, a comment delete still prompts. Only the reply and the edit move.
- **By body, not just by act.** Content checks on what is being posted are verdicts about the *post*, so they keep firing inside an allowed act. An unreadable payload still fails closed for the same reason.

**Repository visibility is decided per repo, never per org.** An organisation that owns public repos alongside private ones makes an owner allowlist grant on exactly the class the carve-out excluded. The shipped [`_lib/pr-author.sh`](../examples/hooks/_lib/pr-author.sh) asks the forge for the repo's own visibility, caches it with a short TTL — visibility changes, unlike authorship — and fails closed on public, on an unresolvable target, on a missing CLI and on a timeout. Failed lookups are cached too, on a much shorter TTL, or every command naming an unresolvable repo pays a fresh API round-trip inside a `PreToolUse` hook.

## Where the policy lives

Keep the policy in **one** closed set, matched **whole-string against a guard's derived trigger label** — never against raw command text. Substring matching lets `gh pr create --web && kubectl delete ...` ride in on a label describing only its first clause.

Each guard keeps its own command matching and asks the policy about the label it derived. Adding a member then means editing one variable and adding a test case, not touching a guard.

Two properties of a consuming guard are load-bearing and easy to lose in a refactor:

- **Derive the verdict from every flagged segment**, not the first and not the handful the display keeps — otherwise `git rebase && kubectl apply` rides in on its first clause.
- **Withhold a label rather than granting one and relying on a downstream guard to re-block.** A downstream block exists only for the shapes that hook happens to match, so leaning on it lets through precisely the never-row members the grant must not reopen.

A guard whose remaining gated acts are all in the never row should never consult the allowlist at all — it reaches the policy only to turn its own `ask` into a hard block.

## Arming, and how it ends

Arming is **per session**, never global. A hook's environment does not carry the session id, so guards read it from the hook payload on stdin. A concurrent session must be unaffected — assert that directly in a test.

It should end three ways:

- **Attendance (primary).** The first user prompt after arming disarms it — a human typing means someone is watching. Wire it into `UserPromptSubmit`, first in the chain.
- **TTL (backstop).** Long enough never to fire mid-run on a legitimate overnight job; short enough that an abandoned session does not stay armed. An expired arming is not an arming.
- **Explicit off.**

Re-arming is one command, so a false disarm costs nothing. Deliberately have **no mid-run expiry**: a cap that fires at 04:00 is itself the kind of wall this mode exists to remove.

## Audit trail

Append every decision — armed, allowed, blocked, disarmed. **Both directions, not just refusals.** An unattended grant with no audit trail is a blanket allow with extra steps, and "what did it decide to *do*" matters as much as what it refused.

Test and replay harnesses must redirect diagnostic output to a temp dir, or probe firings pollute the corpus the tally is read from. That cost 42 of 145 recorded force-push asks once already.

## Testing: two assertion families, and one that grades nothing

- **REGRESSION** — must hold identically armed and disarmed. These pass against a guard *without* the feature too; that is exactly what makes them a control on "did this change attended behaviour".
- **NEW** — must answer *differently* without the feature.

**A NEW assertion that passes against a guard lacking the feature is vacuous.** It prints `ok` even if the feature is deleted, which is worse than no test because it buys false confidence.

Prove they bind: check out the pre-feature revision of every file involved, and replay each NEW case against that baseline, requiring a **different** answer.

```bash
R=<pre-feature-rev>
for f in <each guard and the policy file>; do
  git show "$R:$f" > "/tmp/$(basename "$f")"; chmod +x "/tmp/$(basename "$f")"
done
# run the probe with each baseline injected by env var
```

Two details decide whether this harness works:

- **Roll back the policy file too, not only the guards.** For a grant that lives in the *allowlist* rather than in a guard — every git member above — swapping only the guard leaves the new policy in place, so the baseline answers `allow` for the same reason the feature does, and a perfectly bound case reports vacuous.
- **A case whose baseline is not supplied must report `UNPROVEN` and fail.** An omitted variable can then never read as a passed one.

The first full run of such a harness found three vacuous assertions. Two were long-standing, because the guard behind them had gone inert and the probe had not been re-run since. The third was written the same day: *"a reply on a public repo fails closed when armed"* — true, and true of the baseline as well, which hard-blocked every reply via an unrelated misclassification. Same verdict, unrelated cause.

That third one is the argument for the harness in one line: it was a *correct* assertion about a *real* behaviour, written by someone who had just read the code, and it still graded nothing.

## What is deliberately not built

Each of these was measured, not argued:

- **A read-only-diagnostics bundle.** A no-op: under a broad Bash permission those commands never prompt, so a bundle has nothing to unblock.
- **A git-hygiene bundle.** Superseded by allowing git wholesale on a branch the session owns, with the two remote-branch-deletion shapes withheld. Its original members auto-allowed attended via proven-safe predicates that clear the prompt before the policy is consulted, so neither was ever the thing that blocked.
- **Auto-retry on a soft-block class.** Measured against 138 blocks from one advisory guard over 6 days: 91% of call sites are blocked exactly once and self-correct on the next attempt, only 4% of blocks land beyond a second attempt at one call site, and the median gap inside a same-file run is 602 seconds — separate later edits, not a retry loop. `exit 2 → stderr → model → fix → retry` is already the auto-retry loop and needs nothing from a human.

That last one is the general trap: the design counted block *volume* and read it as wall height. **A wall is a block the session cannot get past**, not a block that happens often.
