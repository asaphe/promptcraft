# Review Verdicts and Finding Grades

Always-loaded: this file carries no `paths:` frontmatter, so it loads every session. It is split out from the review docs because the verdict/grade decision has to fire at the moment a review is *posted*, not when a methodology doc happens to be open. `../../docs/pr-review-rules.md` owns *how* to review and stays canonical for the severities a review actually posts; this file owns what the review is worth and what to call each finding before it gets there.

## The review state is a merge authorization, not a tone

A forge offers exactly three — approve, comment, request-changes — and "approve with comments" is not one of them, so mapping it to approve-plus-a-body is how a review that wants changes ends up clearing the gate.

- **If anything in the review is a thing you want done, the state is request-changes** — or comment, where the point is informational but you still do not want to authorize merge.
- **Approve means you would accept it merging exactly as-is**, with every comment either FYI or wholly the author's discretion. That is the only legitimate "approve with comments".
- **The tell is self-contradiction in your own prose.** "I'd like this fixed before merge" inside an approval says merge and don't-merge in the same breath. Re-read the draft for that shape before submitting.

Three rationalizations produce a wrong approval, and all three are rejected:

1. *Another reviewer already blocks it, so mine is costless.* That reviews the situation, not the change — their block can be dismissed without your finding ever being revisited.
2. *Blocking is disproportionate for a small or docs-only change.* Proportionality governs how much you write, never which state you pick.
3. *The file belongs to another team, so my approval does not really cover it.* Approval is repo-wide, not per-file. Not owning the file argues for comment, never for approve-with-a-caveat.

Authors act on the state. The prose is what they read *after* the state already told them it was fine.

## Finding grades

Grade a finding by what kind of thing it is, not by how much attention you want it to get.

| Grade | What it means |
|---|---|
| **BLOCKING** | Breaks correctness or security if merged |
| **ISSUE** | A real defect in what the change does or leaves behind |
| **GAP** | Not a defect in the diff — work the change implies but did not do: a tenant half-wired, a parallel map not extended, one of N call sites migrated. Reads *incomplete*, not *wrong* |
| **WARNING** | Nothing to fix; an operational consequence the reader must act on — a manual apply someone owns, a merge-order constraint, a required follow-up in another repo |
| **SUGGESTION** | Optional improvement, wholly the author's call |
| **NIT** | Cosmetic, style, or convention, with no functional effect |

Inflating a by-design operational step to `ISSUE` and deflating missing work to `NIT` are the same error in opposite directions — both substitute a volume knob for a category.

- **`GAP` is the grade most often lost.** Without a category for "not wrong, but not finished", missing work falls to `NIT`, reads as cosmetic, and gets skipped. If a tenant, environment, call site, or consumer is left half-wired, it is a `GAP` even when every line in the diff is correct.
- **`NIT` is reserved for genuinely cosmetic findings.** If acting on the finding would change system behaviour, it was never a `NIT`.
- **Before posting `BLOCKING`, name what breaks on merge alone.** The grade is defined by merging, so the test is one sentence: with nobody taking any other action, what is wrong the moment this lands? If the answer needs someone to also apply, deploy, migrate, or run something, the merge is inert and the grade is `WARNING` — the work is real, it just isn't a defect in the diff. This is the over-blocking twin of the approval tell above and has the same shape: conceding correctness inside a blocking finding — "the gate you documented is correct", "that is by design", "nothing to change here" — says not-a-defect and blocks in the same breath. Check the draft for that shape in *both* directions before submitting.
- **A manual infrastructure apply is a `WARNING`, not an `ISSUE`.** Where CI does not run it and an operator must, that is the design, not a defect in someone's PR. Say what must run, who runs it, and what breaks until it does. The same holds for "this module has no CI plan coverage" when that is the intended arrangement.

## These six grades are an instrument, not the posting scheme

The severities a review posts, and their forge-event mapping, are the three in `../../docs/pr-review-rules.md` § Severity Classification, which stays canonical. Map before posting:

| Internal grade | Posts as |
|---|---|
| `BLOCKING` | `BLOCKING` |
| `ISSUE` | `ISSUE` |
| `GAP` | `ISSUE` — it is real work someone must do |
| `WARNING` | `SUGGESTION`, leading with the action and its owner |
| `SUGGESTION` | `SUGGESTION` |
| `NIT` | `SUGGESTION` |

Never invent a posted severity outside that set, and never add an output subsection for one: reviewer output templates enumerate three, so an unmapped grade renders nowhere the reader has a category for. A `[WARNING]` prefix, or a "1 WARNING" line in a summary count, is the internal taxonomy escaping its container.

**The map binds on corrections too, and that is where it gets dropped.** A regraded finding re-enters the map: the posted artifact shows only the newly-mapped severity, never the grade name and never the regrade history. "Regraded from BLOCKING", "originally graded X", "*Edited: that was wrong*" tell the author about your review's revision process — which they have no model of, did not ask for, and cannot act on. Correct the artifact instead (clean replacement text or delete-and-repost, severity counts updated) and state the withdrawal and its reason in your report to the user, not as an errata trailer in the thing the author reads. The disclosure moves surface; it is never dropped.
