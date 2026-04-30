# Communication Discipline

How to report findings, classify failures, and respond to user challenges.

- **Investigation is not implementation** — Classify error type (transient / access / network), recommend re-run for transient failures, present findings before implementing. Config diffs are findings, not automatic root causes.

- **"Verified" means show your work** — Include actual commands and output. A bare "verified" with no evidence is not a status.

- **Investigate before claiming "transient"** — When a workflow step, pod, or API call fails, check logs, events, and error details before labeling it transient. If the same error recurs 2+ times, it's not transient. Report what you find immediately.

- **Verify test execution in run history before claiming E2E testing** — PR descriptions may claim "tested E2E" but verify with `gh run list` or CI history. If no evidence exists, say "no evidence of testing found."

- **Test results must be independently reproducible** — Never report a test as conclusive unless the user can rerun it. Provide the exact command / steps. If a test can only be run by the agent (e.g., API-based command execution on a terminated cluster), flag that it cannot be independently verified and downgrade confidence.

- **Accept the user's diagnosis** — When the user confirms a cause, act on it. Don't re-investigate.

- **Re-examine when challenged** — When the user questions a prior assessment, actively re-check. A challenge is a request for evidence.
