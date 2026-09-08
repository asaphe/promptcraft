# Report & Runbook Output Standards

Formatting rules for investigation reports, runbooks, comparison tables, and other human-facing artifacts. Chat messages are a different register — see the last two sections.

## Reports and runbooks

- **Default to a sectioned, skimmable structure without being asked** — labeled sections sized for a quick pass (exec summary → detail → appendix), not one undifferentiated block, for any human-facing artifact including HTML. Bake it into the first draft; don't wait for a "make it readable" follow-up.
- **Lead with a one-line executive summary** — status + recommendation, before any table or section header. The reader should be able to act on the first line without scrolling.
- **FIX columns state the fix in 5-10 words** — not links to PRs. Links go in a separate column.
- **Tables max 5 columns** — if more, switch to grouped sub-tables or HTML.
- **Render HTML when length >2 screens** or when the reader is comparing rows visually.
- **No empty section headers** — if there are no next steps, don't write "## Next Steps".
- **Don't encode in a title what the structure already conveys** — an ID scheme prefixed onto every heading (`PB-1 ·`, `SEC-3:`) duplicates position the document already expresses through nesting and order, and the reader skips past it on every heading to reach the words that actually differ. Number sections only when those numbers are referenced from somewhere else; otherwise the title is the name of the thing and nothing more.

## Choosing a format for a persisted doc

Pick deliberately — never default to HTML because it renders nicely, and never default to Markdown because it is cheaper to write.

- **The user named a format → that wins outright.** No heuristic needed.
- **Primary consumer is an agent in a future session** (task-local context, tracker files, research findings meant to be re-read to resume work, anything that will be grepped or diffed) → **Markdown**, or structured text/JSON for genuinely tabular data. Token-efficient to re-read, diff-friendly, and editable with targeted string replacement — HTML's markup is pure overhead when no human is the reader.
- **Primary consumer is a human reading, reviewing or sharing it**, and the doc is long or comparison-heavy (the >2-screens / visual-comparison threshold above) → **HTML**. Richer typography, theme-aware, easier to scan — worth the extra weight when a human is the one reading.
- **Both consume it** — the common case, where the agent needs it to resume work and a human wants to review it → keep the working source in Markdown and generate an HTML rendering only at genuine review checkpoints, not in lockstep on every edit.
- **Deliverables with a native home elsewhere** (a design doc going to your issue tracker, a PR body, a chat message) use that destination's native format. This section covers ad-hoc and durable file storage, not every output surface.
- **Architecture documents (HLD, LLD, RFC, ADR) answer to their own authoring standard first** — section spine, evidence bar and readability contract. The format split that follows from the rules above: a human-reviewed HLD or RFC is a self-contained single HTML file, so it survives being emailed; an LLD consumed by an executor is Markdown. Keep every version of one design in a single directory.

## Chat messages

A chat message is a conversation with a colleague, not a report pasted into the channel — the linked artifact (PR, doc, ticket) is the record of substance, and the message's only job is to get the right person to look at it.

- **Open with a plain sentence, not a status-label header** — say what happened and what it means the way you would say it out loud. "Requesting changes on #1234 — one real blocker, easy fix" beats "Review posted: *Requesting changes* (1 BLOCKING, 2 ISSUE…)".
- **Carry only what the recipient does not already have.** They know what they just fixed and what they asked for, so "all your findings are resolved" is noise dressed as an update. State the verdict, then only the delta: an open blocker they believe is closed, a red check whose cause they cannot see, an action owed and by whom. **Never narrate what you checked, or that you checked and found nothing** — "I re-verified X against upstream and it all checks out" reports diligence, which is not information. The finding is the message; the effort behind it never is.
- **Compress findings into prose — don't reproduce a bullet-per-finding wall.** Fold counts and severity into a sentence or two and link out for the full breakdown. If it takes more than five or six lines of structure to say what happened, that detail belongs in the linked artifact.
- **Match the platform's markup dialect.** Slack mrkdwn uses single `*bold*` (not `**bold**`), `_italic_`, and backtick code — writing CommonMark into it renders literally.
- **Use bare URLs in any message a human will paste manually** — rich `<url|label>` link syntax renders only when sent through the platform's API or webhook payload; pasted into the client it shows literally. Bare URLs auto-link on paste. Drafts meant for programmatic posting may use the labeled-link syntax.
- **Anything past a plain sentence — a header plus bullets, multiple sections — MUST use the platform's structured-block format, never plain text with markup in it.** Posting `text` with bullet characters and single `\n` breaks collapses into one run-on paragraph: the markdown parser behind a plain-text field treats a lone newline as a space, because in CommonMark only a blank line starts a new paragraph. On Slack that means real `section` blocks for headers and prose, `rich_text` + `rich_text_list` for bullets, and `context` for links. A message that looks correctly formatted in the text you composed is not evidence it will render that way.

## Posting discipline

A post to a shared channel is a shared-state action other people read — the bar is "would I be comfortable if this needed no follow-up ever", not "close enough, I can correct it after".

**Scope: this section governs posts whose content the agent chose.** When the user asks for a post and says what it should say, send it as asked — the checks below guard the agent's own drafting and judgment, not the user's instruction, and running them against an explicit request is friction rather than safety. They apply in full when the agent decided on its own to post, and when the ask named a destination but left the content open ("reply in this thread", "let them know"). That second case is where the real failures come from.

- **Preview any structured post you composed in a direct message to the user before posting it to a shared channel, and wait for explicit sign-off.** Send the exact payload intended for the destination, and post to the shared channel only after affirmative approval of *that* content — a prior approval does not carry to a revised draft. A chat integration typically posts as the authenticated user's own account rather than a separate bot identity, so a malformed or wrong post is indistinguishable from something the user said themselves, somewhere shared and permanent. The DM preview is the only correction window before that happens. A single trivial one-liner does not need the round-trip; anything with headers, bullets or multiple sections does.
- **Scope strictly to what was authorized — never fold in an unrelated finding, even as an aside.** Authorization to post one thing covers exactly that. A separate discovery made during the same session — an operational incident, a finding about a different system, anything outside the linked artifact's subject — does not ride along in the same message. Surface it to the user in-session and wait to be asked. One thread serves one topic; mixing streams degrades the channel for everyone reading it, not just that one message.
- **Read the thread before posting anything you decided to post or worded yourself.** Another session, a bot or a human may have already posted the same status, a correction, or context that changes what is worth saying. Posting blind risks duplicating or contradicting what is already there, and reading first is also how the established convention for that specific thread is learned rather than guessed.
- **Verify a status claim before posting it, not after.** "Approved", "CI green", "no blocking issues" are claims the reader acts on immediately. Getting one wrong and walking it back a few minutes later costs more trust than posting slightly later with the claim actually checked — a retraction is not a cheaper alternative to verifying first, it is evidence the verification pass was too shallow.
- **One message per logical update.** If part of an update turns out incomplete right after posting, that is a signal to verify more thoroughly next time, not a licence to normalize a post/correct/re-correct cycle. Genuinely new information arriving later — CI finishing, a separate follow-up — is a legitimate new message; walking back a claim that should have been checked before the first post is not.
