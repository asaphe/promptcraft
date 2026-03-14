# PR Bot Comment Handling

- **Minimize bot comments, don't reply to them** — When addressing automated review findings (Bugbot, CodeQL, Codex, etc.), never reply to bot comments. Instead: fix the issue or determine it's a false positive, then `minimizeComment` with classifier `RESOLVED`. Replying to bots creates noise — nobody reads reply threads on bot comments. Resolve the thread via `resolveReviewThread` AND minimize the comment so it collapses in the PR timeline.

- **Minimize our own replies to bots too** — If reply comments were already left on bot findings, minimize those as well. They add no value once the thread is resolved.

- **Bot comment workflow**: (1) fix code or classify as false positive, (2) `resolveReviewThread` with the thread ID (`PRRT_` prefix) for inline threads, (3) `minimizeComment` with the appropriate classifier on the comment node ID. `minimizeComment` works on all three node types: inline review comments (`PRRC_`), issue/PR comments (`IC_`), and PR review body comments (`PRR_`). Both mutations are needed for inline threads — resolving hides the thread, minimizing collapses the comment in the timeline. Available classifiers: `RESOLVED` (addressed), `OUTDATED` (no longer relevant), `DUPLICATE` (covered elsewhere), `OFF_TOPIC`, `SPAM`, `ABUSE`.

- **Dismissing a bot review is not enough — also minimize the review body** — `dismissals` removes the "Changes Requested" badge but leaves the review body visible in the PR timeline. Always follow dismiss with `minimizeComment` on the review's `PRR_` node ID (available as `node_id` in the reviews API response). Both steps are required for the comment to fully collapse.

- **Bot reviewers re-post comments on every new commit** — Cursor Bugbot, CodeQL, and similar automated reviewers post review comments on each push. After resolving threads and minimizing bot comments per the bot comment workflow, monitor the PR for new unresolved threads after every subsequent push. A clean PR timeline before pushing does not mean clean after — re-check thread status post-push before declaring PR ready.
