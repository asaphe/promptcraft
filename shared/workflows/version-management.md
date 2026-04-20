# Version Management

Single source of truth for package and tool versions across CI, containers, and deployment configs.

## Core Principle

**One place defines each version. Everything else reads from there.**

Duplicating a version string across `Dockerfile`, `.github/workflows/*.yml`, `pyproject.toml`, and a README is a drift bug waiting to happen. When the version bumps, at least one reference will be missed.

## Source-of-Truth Locations

Pick the most authoritative file per toolchain:

| Language / Tool | Source of truth |
|-----------------|-----------------|
| Python | `pyproject.toml` (`[project]` requires-python, dependency pins) |
| Node | `package.json` + `package-lock.json` / `pnpm-lock.yaml` |
| Terraform | `.terraform-version` (tfenv) or `required_version` in the root module |
| Go | `go.mod` |
| Docker base images | `Dockerfile` — but reference via `ARG` so CI can pass it in |
| CI tool versions (asdf, mise, rtx) | `.tool-versions` |

## Dynamic Fetching in CI

CI workflows should **read** versions from the source, not hardcode them:

- GitHub Actions: parse `pyproject.toml` / `package.json` / `.tool-versions` at job start and export to env vars.
- Dockerfiles: use `ARG` and inject via `--build-arg` from CI.
- Helm charts: fetch app version from `Chart.yaml` in a pipeline step rather than re-declaring it in values files.

## Lockfiles Are Authoritative

When a lockfile (`package-lock.json`, `poetry.lock`, `Pipfile.lock`, `go.sum`) exists, the deployed artifact is built from the lockfile. Any spec file (`package.json`, `pyproject.toml`) that disagrees is either lagging or wrong — reconcile before shipping.

## Version Pinning Discipline

- **Never ship `latest`.** Pin explicit versions in Dockerfiles, base images, GitHub Actions, and Helm charts.
- **Pin major+minor at a minimum**; pin full patch version for anything touching production.
- **Comment why** next to unusual pins (e.g., `# pinned: 1.22.x broke ARM builds`).
