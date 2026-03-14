# Version Selection Policy

When introducing or bumping any dependency — Python packages, Terraform providers, Terraform itself, Docker base images, Node packages, Go modules — follow this policy.

- **Always check the source of truth** — Look up the current latest stable release from the official registry (PyPI, Terraform Registry, Docker Hub, npm, Go proxy). Never rely on training knowledge for version numbers.

- **Prefer newest stable over LTS unless LTS exists and is < 6 months old** — Use the latest stable (non-RC, non-alpha, non-beta) release. If the project offers an explicit LTS track (e.g., Node.js, PostgreSQL), prefer the newest LTS that has been out for at least 2 weeks (avoid day-zero releases).

- **Check for security advisories** — Before adopting a version, search for known CVEs or security advisories. If the latest has an unpatched CVE, fall back to the newest unaffected version.

- **Prefer official over community** — For Terraform providers, prefer HashiCorp or vendor-official providers over community-maintained ones. For Docker images, prefer official library images. For Python, prefer packages maintained by the upstream project.

- **Match major version to existing usage** — Don't bump major versions without explicit approval (e.g., don't jump from Terraform AWS provider v4 to v5 without asking). Minor and patch bumps within the same major are fine.

- **Document the version choice** — When introducing a new dependency or bumping an existing one, state in the PR/commit why that version was chosen (e.g., "latest stable as of 2026-03-04, no known CVEs").

- **When unable to decide, ask the user** — If multiple versions are viable and the tradeoffs are unclear (e.g., LTS vs. latest stable, competing official packages, version with a known issue vs. older proven version), present the options with pros/cons and let the user decide. Do not silently pick one.
