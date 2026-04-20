# tools/chatgpt/global/

ChatGPT **Custom Instructions** — the two text boxes under Settings → Personalization → Custom Instructions (ChatGPT Plus/Team/Enterprise).

Apply globally to every chat unless overridden by a Project (`../projects/`).

## Contents

| File | Use when |
|------|----------|
| `general-instructions.md` | Your day-to-day work spans multiple technologies (Python, TypeScript, Bash, infra). |
| `professional-instructions.md` | Your primary work is DevOps / infrastructure / platform engineering. |

Each file has two code blocks:

1. **"What would you like ChatGPT to know about you?"** — context about role and stack.
2. **"How would you like ChatGPT to respond?"** — response style and priorities.

## How to use

1. Open ChatGPT → Settings → Personalization → **Custom Instructions**.
2. Copy the content of each code block into the matching text field.
3. Save.

## Character budget

ChatGPT enforces a **1500-character limit per field**. Both files are already within budget; if you edit, keep them under 1500 or ChatGPT will silently truncate.

## vs `../projects/`

- **Here (global):** applies to every chat.
- **`../projects/`:** applies to chats inside a specific Project only — use for per-project overrides.
