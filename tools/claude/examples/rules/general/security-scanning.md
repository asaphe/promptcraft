# Security Scanning Rules

Authoring rules for security scanners (vulnerability scanning, package verification, malicious-code detection) that operate on third-party content.

- **Isolate security scanners from scanned code** — When running scans inside containers that may contain malicious code, use `python3 -S` to suppress site module processing (which executes `.pth` files at startup) and `--network none` on `docker run` to prevent exfiltration. Without these, the scanner triggers the code it's trying to detect.

- **Security allowlists must verify content, not just names** — Filename-only allowlists are permanent bypasses. Use content hashes (sha256) so tampering is caught even for known-good packages.

- **Security-critical error handling must be fail-closed** — Avoid `|| echo "default"` fallbacks and other patterns that silently continue on failure. When a verification step fails (hash query, signature check, allowlist lookup), the operation must stop, not degrade gracefully. A silent failure in a security path is equivalent to disabling the check.

- **Prefer native verification over custom checksums** — Before building custom hash / checksum verification for third-party binaries (extensions, plugins, packages), check if the target system already verifies cryptographic signatures natively. Custom SHA256 checksums add maintenance burden (hash updates on version bumps) without additional security when the system already signs and verifies its own artifacts. Example: DuckDB signs all official extensions and verifies signatures on every `LOAD`, making manual SHA256 checksums redundant.
