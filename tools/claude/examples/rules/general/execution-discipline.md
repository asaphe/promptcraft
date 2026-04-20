# Execution Discipline

- **Answer questions before acting** — When the user asks a question or presents analysis, answer the question first. Never execute state-changing commands (apply, deploy, trigger workflow, create/delete resources) in response to a question. Present the plan/command and wait for explicit approval.

- **"Show the command" means display it, not execute it** — When the user says "show me the command", "display the command", or "what would the command be", only output the command text. Do not execute it. Execute only when the user explicitly says "run it", "execute", "go ahead", or similar.

- **Never trigger CI/CD workflows without explicit request** — Do not dispatch GitHub Actions workflows, trigger deployments, or initiate pipeline runs unless the user explicitly asks. Monitoring existing CI runs is fine; initiating new ones requires explicit authorization.

- **Use the correct branch ref when triggering workflows** — When testing changes on a feature branch, always pass `--ref <branch>` to `gh workflow run`. Verify the ref matches the current working branch. Never default to `main` when the intent is to test branch changes.

- **Don't retry in loops — stop and ask** — When a command fails or returns unexpected results, do not retry the same approach repeatedly. Stop after 1-2 attempts, explain what happened, and ask the user for guidance. Looping on failures wastes time and may cause damage. This especially applies to `git push` failures — diagnose the cause (auth, branch protection, hook failure) rather than retrying the same push.

- **Use project management MCP tools, not raw curl** — Always use configured MCP tools for project management operations (ClickUp, Jira, etc.). Never fall back to raw `curl` against project management APIs.
