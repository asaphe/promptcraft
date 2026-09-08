# Git Worktree Pre-flight and Squash Safety

The long-form reference behind [`../rules/general/git-safety.md`](../rules/general/git-safety.md). That file carries the rules; this one carries the mechanics and the reasons.

## Worktree pre-flight

Never switch branches in a repo root, and never work in one. This covers **any** work — a one-line hook edit earns a worktree exactly as a multi-file feature does. There is no size below which the repo root becomes acceptable.

```bash
git -C <repo> fetch origin
git -C <repo> worktree add /tmp/<name> -b <branch> --no-track origin/main
```

**Cut from the fetched remote tip, and pass `--no-track`.** Two separate hazards, one command:

- *Staleness* — local `main` is behind from the moment anyone else merges, so a worktree cut from it starts on a stale base. `origin/main` after a fetch is the real tip.
- *Tracking* — branching off a remote-tracking ref sets the new branch's upstream to `origin/main`, so a later bare `git push` aims at main. `--no-track` suppresses it. Verified directly: without the flag the new branch's upstream is `origin/main`; with it, there is no upstream.

This form depends on **nothing** about the repo root — it need not be on `main`, clean, or fast-forwarded. An earlier version of this protocol required all three, and a precondition on root state is a precondition that gets skipped when a change feels too small to bother with.

Work in `/tmp/<name>`, push from there, then `git worktree remove /tmp/<name>`.

## Restacking when the base PR was squash-merged

A stacked branch whose base PR merges mid-flight cannot be rebased with a plain `git rebase origin/main`. A squash-merge puts the base PR's whole tree on `main` under **one new SHA**, so the base branch's own commits are not ancestors of `main` — the rebase replays every one of them again, on top of a `main` that already contains their content.

Replay only the commits above the base instead, naming the branch's **original** base head:

```bash
git rebase --onto origin/main <sha-the-branch-was-cut-from>
```

The non-obvious half is which SHA that is. If the base PR took an "Update branch" before merging, its final head is *not* where the stacked branch forked — use the fork point (`git merge-base` against the pre-merge base ref, or the SHA recorded when the branch was cut), never the base PR's merged head. Getting this wrong is quiet: the rebase succeeds and the PR shows the base's changes as if they were yours.

Expect one conflict per file both PRs touched, and audit each one — "ours" now means the pre-merge version of a file that `main` has already moved past.

Where the forge supports native stacked pull requests, it performs this retarget server-side; see [`../../guides/stacked-prs-guide.md`](../../guides/stacked-prs-guide.md). This section still governs hand-rolled dependent branches and cross-repo work.

## Squash protocol

Before `git reset --soft origin/main` inside a worktree:

```bash
git fetch origin main
git merge --ff-only origin/main   # must succeed before squashing
```

**If `merge --ff-only` fails (diverging branches): stop.** Reset to the backup branch, then use `git rebase origin/main` instead of `reset --soft`. A failed ff-only that continues to squash silently sweeps main's new commits into your commit.

**`set -e` does not catch this.** In a chained command, `git merge --ff-only` prints `fatal: Not possible to fast-forward, aborting.` and the script continues anyway. Either check the exit code explicitly (`git merge --ff-only origin/main || exit 1`) or use rebase, which fails loudly.

**A squash rewrites commits you did not author.** The ff-only gate protects `main`'s commits; nothing protects a *co-author's* commits on the branch being squashed, and the instruction to squash is normally given without knowing they exist. Run `git log origin/main..HEAD --format='%an'` first and surface every other author rather than executing — collapsing their commits destroys attribution and is not yours to decide.

**After squashing:** confirm with `git diff origin/main...HEAD --name-only` that only the intended files appear. Re-fetch `origin/main` once more — if it advanced during the squash, note the SHA delta in the PR body so reviewers know the diff includes newer commits.

**A backup branch records the state it was taken at, and nothing after it.** That is the point of a backup, but it means that after any later amend, squash, or rebase the backup no longer describes the branch — and a tracker or handoff recording the backup's SHA from memory rather than from `git rev-parse <branch>-backup` names a commit that was squashed away. Read the SHA before writing it down, and re-point the backup if what you want preserved is the current tip; otherwise stop calling it a backup of this branch. `git branch -d` refusing the delete is frequently the only signal that the two ever diverged.

## Verifying a squash-merge landed

These repos merge by squash, so the branch commit is never an ancestor of `main` afterwards. `git merge-base --is-ancestor` correctly reports "no" and reads as a failed merge.

Diff the content instead:

```bash
git diff origin/main <branch-tip> --name-only   # empty means the content landed
```

## Auto-allowing a force-push: the predicate that actually holds

If you build a guard that skips the force-push prompt in a provably-safe case — the shipped [`destructive-guard`](../hooks/destructive-guard/) example deliberately does **not**, it always asks — get the predicate right.

**Ref existence is not the predicate; SHA-equality is.** "A `<branch>-backup` ref exists" is too weak: per the squash protocol above, a backup records the state it was taken at and nothing after it, so a stale backup left over from an earlier rewrite satisfies "a backup exists" while the tip actually being overwritten goes unsaved. What proves recoverability is that `refs/heads/<branch>-backup` resolves to the same SHA as `refs/remotes/origin/<branch>`.

Everything else must fail closed and still prompt:

| Case | Why it still asks |
|---|---|
| No explicit ref (`git push --force`) | Pushes the current branch; nothing in the command names what gets overwritten |
| A refspec (`HEAD:feat`, `a:b`) | Source and destination differ, so the backup name cannot be derived from the ref |
| A remote other than `origin` | The backup would be compared against the wrong remote's tip |
| `main` / `master` | Never auto-allowed, whatever the backup says |
| A second `git push` in the same command | That push's own block would be cleared along with this one |
| Backup missing, or not equal to `origin/<branch>` | The state being overwritten is not provably saved |

**Known limit: `origin/<branch>` is only as fresh as the last fetch.** The predicate proves the backup matches the remote tip *as last observed locally*, not as it stands on the server now — a collaborator pushing between your fetch and your force-push is invisible to it. `--force-with-lease` is the guard for that case.

**Test such a predicate with known-positives, not only with the cases it must refuse.** Delete the entire auto-allow block and every "still prompts" row above keeps passing, so a negatives-only suite cannot distinguish working logic from dead logic. The positives — backup equals origin tip, in every force spelling — are the control.

## Squashing via git plumbing

When `git checkout`/`git switch` are unavailable (blocked by a worktree-safety hook, for instance), squashing with plumbing instead of `git reset --soft` is a valid workaround — but plumbing commands do not inherit their porcelain equivalents' side effects:

```bash
NEW_COMMIT=$(git commit-tree -S "$(git rev-parse HEAD^{tree})" -m "message")
git update-ref refs/heads/<branch> "$NEW_COMMIT"
```

**`git commit-tree` does not honor `commit.gpgsign`/`user.signingkey`** the way `git commit` does — omitting `-S` silently produces an unsigned commit even with global signing configured and every prior commit genuinely signed. There is no error and no warning; the only signal is `verification.verified: false` on the resulting commit. Before pushing a plumbing-built commit, compare its `verification` block (`gh api repos/{owner}/{repo}/commits/{sha}`) against a known-signed sibling. Do not assume a plumbing substitution preserves everything the porcelain command would have.
