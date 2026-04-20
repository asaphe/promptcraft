# DECISIONS.md

Architecture and structural decisions behind the current repo layout. ADR-lite — just the decision, the alternatives considered, and the rationale.

Decisions recorded here were made during the repo-wide restructure in early 2026. For subsequent changes, add a new entry rather than edit old ones.

---

## D1 — Split into `shared/` + `tools/`

**Decision:** Universal content lives under `shared/`. Tool-specific adaptations live under `tools/<tool>/`.

**Alternatives considered:**

1. Keep flat top-level directories (`core/`, `languages/`, `infrastructure/`, `claude/`, `cursor/`, `chatgpt/`, `examples/`) — the original layout.
2. All content organized by tool first (`claude/principles/`, `cursor/principles/`, etc.) with no shared layer.

**Why this one:** A tool-first structure forces triplication: the same Python standards would live under `claude/`, `cursor/`, and `chatgpt/`. A flat structure mixes universal and tool-specific concepts at the same level, making it unclear where a new file belongs. The `shared/`-plus-`tools/` split gives one canonical location per universal rule and one tool-specific layer where adaptation is genuinely needed.

---

## D2 — `tools/claude/` subdirectory taxonomy

**Decision:** Under `tools/claude/`, split content by *kind*, not by topic:

- `guides/` — end-to-end instructional content.
- `templates/` — starter files to copy and edit.
- `examples/` — complete, curated reference `.claude/` directory.
- `scaffolding/` — minimal copy-and-go `.claude/` skeleton.
- `specs/` — RFC-style normative standards.

**Alternatives considered:**

1. Split by topic (`tools/claude/hooks/`, `tools/claude/agents/`, `tools/claude/skills/`) — groups related content but buries guides inside feature folders.
2. Single flat `tools/claude/` with all files at top level.

**Why this one:** Readers arrive with different intents — "teach me how hooks work" (guide) vs. "give me a hook to copy" (example/template). Splitting by kind surfaces the right file for each intent. Topic-organized subdirectories appear *inside* each kind (e.g., `tools/claude/examples/hooks/` contains topic-grouped hook examples).

---

## D3 — `tools/cursor/rules/user/` + `tools/cursor/rules/mdc/`

**Decision:** Cursor rules are split into two subdirectories by destination, not topic:

- `user/` — markdown files for Cursor's User Rules UI (Settings → Rules).
- `mdc/` — `.mdc` files for `.cursor/rules/` project-rule directories.

**Alternatives considered:**

1. One flat `tools/cursor/rules/` with both markdown and `.mdc` files mixed.
2. Named `rules/user-rules/` and `rules/mdc-rules/` (redundant suffix).

**Why this one:** The two file formats are destined for completely different UIs (Cursor Settings vs. the `.cursor/rules/` directory inside a repo). Grouping by destination matches how users actually adopt them. The directory names stay short because the parent is already `rules/`.

---

## D4 — `.claude/` stays live contributor config, NOT example content

**Decision:** The top-level `.claude/` directory is Claude Code's config for *editing promptcraft itself*. It is NOT a reference for users to copy. Reference content lives under `tools/claude/examples/`.

**Alternatives considered:**

1. Move `.claude/` into `tools/claude/examples/` to avoid duplication.
2. Keep `.claude/` at the root but make it identical to `tools/claude/examples/`.

**Why this one:** Claude Code auto-loads `.claude/` from the repo root. That's where live hooks actually fire, contributor rules actually load, and dogfooding actually happens. Moving it would break the auto-load. Keeping it identical to `examples/` would force two-way sync for every change. The current rule: `.claude/` hosts live working config; `tools/claude/examples/` hosts polished reference content; a sync rule keeps dogfooded hooks consistent.

A `.claude/README.md` disambiguates the two for anyone who lands there by accident.

---

## D5 — Adopt the `AGENTS.md` convention ([agents.md](https://agents.md))

**Decision:** Add a root-level `AGENTS.md` containing instructions for AI agents editing this repo. Nested `AGENTS.md` under subdirectories allowed if local conventions diverge.

**Alternatives considered:**

1. Put all contributor guidance in `CONTRIBUTING.md` (traditional OSS convention).
2. Put contributor guidance in a global `CLAUDE.md` template and reuse it as `AGENTS.md`.
3. Skip — rely on `.claude/CLAUDE.md` only.

**Why this one:** `agents.md` is emerging as a cross-assistant convention — Codex, Cursor, Aider, and Claude Code all read it. It scopes to *contributing to this repo*, which is distinct from the universal content the repo publishes. `CONTRIBUTING.md` traditionally targets human contributors and focuses on licensing / CLA / PR flow; `AGENTS.md` is for the AI agent's session context. They coexist.

---

## D6 — Universal `environment-preferences.md` split

**Decision:** The original `environment-preferences.md` mixed universal CLI conventions with personal pyenv / shell / naming quirks. Split into:

- `shared/principles/cli-design.md` (universal)
- `shared/workflows/version-management.md` (universal)
- `shared/infrastructure/cost-optimization.md` (universal)
- `shared/principles/personal.md` (repo-owner-specific, marked as such)

**Alternatives considered:**

1. Keep as one file with a disclaimer at the top.
2. Delete the personal parts entirely.

**Why this one:** The original file was one of the larger sources of confusion — readers couldn't tell which rules applied to them. Splitting lets universal rules live alongside their peers and isolates the personal content so it can be skipped or replaced without breaking anything else.

---

## D7 — `llms.txt` at the root

**Decision:** Ship a root-level `llms.txt` per the [llmstxt.org](https://llmstxt.org) convention — a machine-readable index with brief descriptions.

**Alternatives considered:**

1. Skip it; rely on README + directory READMEs.
2. Generate automatically in CI.

**Why this one:** Hand-written gives the description field quality that auto-generation doesn't match. The file is short enough to maintain manually. When structure changes, `llms.txt` is updated in the same commit as the structure change.

---

## D8 — Root docs: `README` + `AGENTS` + `ADOPTION` + `CONVENTIONS` + `DECISIONS` + `llms.txt`

**Decision:** Six top-level documents at the repo root, each with a distinct scope:

| File | Audience | Scope |
|------|----------|-------|
| `README.md` | Humans landing on GitHub | Entry point, persona-based routing, layout overview. |
| `AGENTS.md` | AI agents editing this repo | Contributor conventions, per agents.md spec. |
| `ADOPTION.md` | Humans adopting content | Per-tool step-by-step setup. |
| `CONVENTIONS.md` | Contributors | Structural and stylistic rules. |
| `DECISIONS.md` | Future-self / reviewers | Rationale for structure. |
| `llms.txt` | AI assistants indexing the repo | Machine-readable catalog. |

**Why not merge any of them:** Each answers a distinct question ("what is this?", "how do I edit it?", "how do I use it?", "what rules apply?", "why is it shaped this way?", "index everything"). Merging two forces readers to scan past irrelevant content.

---

## D9 — `docs/index.html` stays untouched

**Decision:** The `docs/index.html` file is GitHub Pages' social-preview landing page, not documentation. It remains at `docs/index.html` untouched by the restructure.

**Alternatives considered:**

1. Move to `.github/` or delete — assumed it was stale documentation.
2. Repurpose `docs/` for new restructure docs.

**Why this one:** A grep revealed `docs/index.html` is the rendered social preview card (OG tags, branding). Moving or deleting it would break the GitHub preview. Fresh documentation goes to the repo root where it's easier to find.
