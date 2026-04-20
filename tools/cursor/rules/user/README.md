# tools/cursor/rules/user/

Markdown rules for Cursor's **user rules** UI. Copy-paste content into Settings → Rules → User Rules.

## Contents

| File | Scope |
|------|-------|
| `core-principles.md` | Communication, verification, scope discipline. |
| `general-principles.md` | Development principles, surgical changes, goal orientation. |
| `code-quality.md` | Linting, formatting, review gates. |
| `language-standards.md` | Per-language conventions applied across projects. |
| `infrastructure-tools.md` | Cloud/infra patterns (AWS, Docker, K8s). |
| `terraform-infrastructure.md` | Terraform discipline (state, workspace, apply). |
| `ansible-automation.md` | Ansible conventions. |
| `workflow-patterns.md` | CI/CD, pipeline, and automation patterns. |
| `project-specific-standards.md` | Project-environment conventions (terminal, CLI, naming). |

## Note on overlap

Much of this content is a Cursor-formatted restatement of what lives in `../../../shared/`. When you update a universal rule in `shared/`, also update the Cursor-formatted copy here. A future commit may replace these copies with thin pointers.
