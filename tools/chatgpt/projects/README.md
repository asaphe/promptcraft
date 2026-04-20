# tools/chatgpt/projects/

ChatGPT **Projects** let you set custom instructions scoped to a single Project. Use these files when you want a Project's chats to behave differently from your global Custom Instructions (`../global/`).

## Contents

| File | Project type |
|------|--------------|
| `development-project.md` | Application / library development (TS, Python, Bash). Language-specific conventions, linting, testing. |
| `infrastructure-project.md` | DevOps / platform work. Terraform, Kubernetes/Helm, Docker, AWS, GitHub Actions. |
| `mixed-project.md` | Full-stack projects spanning both code and infra. Balanced guidance with clear priority order. |

## How to use

1. Open ChatGPT → create or open a Project.
2. Project settings → **Instructions** → paste the code block contents.
3. Save.

The Project's instructions are injected into every chat inside that Project, in addition to your global Custom Instructions.

## Character budget

ChatGPT Projects currently allow a larger instruction body than global Custom Instructions, but still impose a limit. Each file here is already tight; if you extend it, keep it short — long instruction blocks dilute signal.

## vs `../global/`

- **`../global/`:** one baseline across every chat.
- **Here (projects):** layered additions for one specific Project. Prefer this for rules that only make sense in a specific stack (e.g., "every command must pass `tflint`" — only relevant in an infra project).
