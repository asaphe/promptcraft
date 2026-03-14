---
paths:
  - "**/Dockerfile*"
  - "**/*.Dockerfile"
---

# Dockerfile Conventions

- **Search both Dockerfile naming patterns** — Repos may use two naming conventions: `*.Dockerfile` (e.g., `my-service.Dockerfile`) and `Dockerfile*` (e.g., `Dockerfile.job`/`Dockerfile.web`, or plain `Dockerfile`). When searching or making bulk changes, use both globs: `**/*.Dockerfile` and `**/Dockerfile*`.

- **Compact WORKDIR/RUN pairs for repetitive operations** — When multiple WORKDIR + RUN pairs do the same operation (e.g., `poetry build` for each module), use compact style with no blank lines between pairs. Use blank lines only to separate logically distinct sections (e.g., between COPY blocks and build blocks, or between stage boundaries).
