# Report & Runbook Output Standards

Formatting rules for investigation reports, runbooks, comparison tables, and chat messages.

- **Lead with a one-line executive summary** — status + recommendation, before any table or section header. The reader should be able to act on the first line without scrolling.
- **FIX columns state the fix in 5-10 words** — not links to PRs. Links go in a separate column.
- **Tables max 5 columns** — if more, switch to grouped sub-tables or HTML.
- **Render HTML when length >2 screens** or when the user is comparing rows visually.
- **No empty section headers** — if there are no next steps, don't write "## Next Steps".
- **Chat links: use bare URLs in any message the user will paste manually** — rich `<url|label>` link syntax (Slack mrkdwn and similar) renders only when sent through the platform's API/webhook payload; pasted into the client it shows literally. Bare URLs auto-link on paste. Drafts meant for programmatic posting may use the labeled-link syntax.
