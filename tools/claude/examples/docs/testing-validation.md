# Testing & Validation

What has to be true before "done" is said out loud. Companion to [`../rules/general/evidence-nulls.md`](../rules/general/evidence-nulls.md) (results that look like answers) and [`../rules/general/shell-traps.md`](../rules/general/shell-traps.md) (commands that return a confident wrong answer) — those two cover *reading* a result; this covers *producing* one.

## Diagnosis

- **A workaround without a diagnosis is a guess.** On any failure — CI, runtime, lint — the fix must answer two questions: what caused it, and why does this fix avoid that cause. If either answer is "not sure" or "the simpler version works", it is unverified.
- **Three failed fix attempts on the same symptom → stop and re-derive the root cause.** Do not try a fourth patch. Repeated patching without re-investigating is guessing with extra steps. If the answer is still unclear after re-deriving, question whether the underlying design or assumption is wrong, rather than narrowing the patch further.
- **Investigate and report every unexpected diff.** "Not our change" and "pre-existing" are conclusions, not starting assumptions.

## What counts as a test

- **"Test" means end-to-end verification.** Deploy and verify live. Unit tests are a prerequisite, not the test itself.
- **Lint and syntax checks are not runtime tests.** CI workflow YAML, infrastructure code, and shell logic must each execute once before "done". A local linter proves syntax, not semantics — it will not surface a CI permission error, a cross-resource validation failure, or an environment-dependent runtime error. For non-trivial YAML or IaC, observe it execute on a branch before merging.
- **Validate actual output, not just the exit code.** Test format-generating code with breaking characters (`|` in markdown, `"` in JSON), cross-platform scripts on both macOS and Linux, validators with deliberate error injection. The same holds after creating or pushing an artifact: exit 0 confirms the operation ran, not that the result matches intent. Read the state back — commit author and committer, the resource's live fields — and diff against intent. An unset git `user.email` silently falls back to a hostname-based default, so verify identity explicitly for anything public-facing.
- **Test hand-written pattern-matching code before the first push.** Regex, parsers, and argument handling over free-form or untrusted input get a positive-and-negative corpus before the first commit. Review is not a substitute for a test suite: it finds gaps one round trip at a time, while a corpus finds them all in one local pass. Measured cost of skipping it once: ten rounds of review findings — anchoring, contractions, negation, portability — while the identical bug class sat unaddressed in a sibling component the whole time.
- **A scripted edit over structured files encodes an assumption about that file's shape.** A codemod locating CI steps by `- name:` walks straight past steps that declare `- id:` first, and writes into the *next* step. Enumerate the shape variants actually present in the corpus before running the transform, then re-verify every edited site by parsed structure, not by eyeballing the diff.

## Making a verification able to fail

- **A verification step must be able to fail, and must assert the property you are claiming.** Two shapes produce a false "verified". The first is *structurally vacuous* — the check cannot report failure at all, because the shell construct carrying it never propagates one; [`../rules/general/shell-traps.md`](../rules/general/shell-traps.md) has that family, and a pipeline's exit status is the usual culprit. The second is *asserts the wrong property*, which no shell rule catches: `yaml.safe_load(f)` proves the file parses, not that it means what you intended, so a mis-inserted key yields valid YAML with a corrupted value and a silently dropped list entry. Assert the parsed *values* of the keys you changed, and prove non-vacuity by running the check once against a known-bad input.
- **The fix for a finding is the likeliest place for a new instance of that finding.** An assertion written to close a vacuity finding, and a matcher rewritten to close a substring bug, fail the same way: by resting on the same unstated premise that made the original look safe. "That field cannot contain the delimiter" is exactly the argument the finding just falsified, so re-using it one level up rebuilds the defect. Re-run the original attack against your own fix, and mutation-prove each new assertion as a precondition of the commit that adds it — per assertion, not per language.
- **A mutant that reverts your own diff tests the diff, not the design.** When the implementation is coupled — a predicate deriving from the very helper it anchors — reverting the changed line breaks both halves at once, so the input never reaches the branch under test and the assertion passes vacuously. That reads as a coverage gap rather than as the broken mutant it is. Build the mutant as the **competent alternative implementation** a reasonable engineer would have written instead — the design you rejected, not the line you changed — and require a *named* test to fail against it. Pair it with the inverse: an over-application mutant (force the predicate always-true, then always-false) proves the negative controls are not vacuous.
- **When a change makes an outcome *stricter*, input-level mutation is not sufficient.** An input already at the strict outcome for an unrelated reason answers identically with and without the change. Replay each new assertion against a build that lacks the feature and require a **different** answer. Worked example and harness shape: [`../../guides/unattended-mode-guide.md`](../../guides/unattended-mode-guide.md) § Testing.

## CI verdicts

The null-shaped CI traps — an in-flight check rendering as absent, `conclusion: ""` defeating a `//` fallback — are in [`../rules/general/shell-traps.md`](../rules/general/shell-traps.md). These are the ones that survive a correct read of the API:

- **Green CI with skipped jobs proves nothing about the skipped path.** Runs with `paths:` filters mark gated jobs `skipped`, and branch protection counts a skipped required check as passing — so a workflow can be merge-green without the gated tests ever running. Before using "CI is green" to dismiss a finding, enumerate the jobs that actually executed and confirm the relevant conclusion is `success`, not `skipped`.
- **A required check that was never *dispatched* is absent, not red — and every watcher reports it as fine.** A skipped job at least appears in the list; a workflow that never produced a run contributes no check at all, so a watch command exits 0 having watched everything that exists. Reconcile the *reported* set against the *required* set, read from the branch's own rules, and treat any required context missing from the PR's check list as unresolved rather than passing.
- **A check name is not a unique key.** The check-runs endpoint returns several runs per name, and taking the first match reports whichever the API happened to order first — routinely an earlier check *suite* on the same SHA, which the default `filter=latest` does not collapse. Select the latest `completed_at` per name, or read the PR's `statusCheckRollup`, which resolves it for you. This generalizes past CI: wherever a list is keyed by a name the API never promised to be unique, take the latest, never the first.
- **After pushing a CI fix, the previously-failing job must pass before declaring done.** Do not claim "fixed" from code analysis. Watch the run until that job goes green on the new commit. If you cannot wait, say "pushed; CI in progress" — never "fixed".

## Infrastructure

- **"Plan + apply" means generate the plan to a file and read it in full.** Do not trust `terraform plan`'s tail or summary lines. Run `terraform plan -out=plan.tfplan && terraform show plan.tfplan > plan.txt` and read that file before requesting apply approval. Destructive changes — replacement, deletion, an IAM principal swap — hide mid-file behind dozens of in-place updates, and tail-only review has missed them. The plan file is the artifact; the stream is not.
- **Compare against running infrastructure.** Extract real values from the deployed system, not just from repo code.
- **Roll out to a non-production environment first, and monitor continuously** — throughout the rollout, not only after it.

## Before declaring done

- **Report all findings**, not just the ones the task was about.
- **Run test-plan items before opening the PR.** Do not list verification steps as checkboxes and wait. If a test needs resources you cannot reach, say so explicitly rather than leaving the box ambiguous.
- **Say what is still pending** if asked for status while CI or reviews are in flight.
- **Pre-merge checklist** — all changes applied and verified; PR body reflects the final state; the tracking issue updated; commit history clean; infrastructure config matches deployed state, with no uncommitted variable overrides.
