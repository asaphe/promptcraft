# CLI Tool Design

Conventions for any CLI tool you build — favor predictable defaults and consistent flags across tools so users can transfer knowledge without re-reading `--help`.

## Error Display and Output

- **Default output is summary-only.** Show the minimum needed to know what happened.
- **`--verbose` reveals detail.** Full stack traces, full error messages, debug logs belong behind this flag.
- **Table row display is controlled by `--max-rows` only.** Do not invent alternate names (`--limit`, `--rows`, `--top`).
  - Default: `--max-rows 30`.
  - `--max-rows 0` means show all rows.

## Command Interface Design

- **Consistent flag patterns across tools.** If one tool uses `--env stg`, every sibling tool should too.
- **Provide both verbose and summary modes** — not just one.
- **Sensible defaults for the common case.** The user should not have to specify flags for the most frequent invocation.
- **Expose fine-grained control via flags**, not by forcing config files for one-off changes.

## Exit Codes

- `0` — success.
- Non-zero — distinct codes per failure class when the caller benefits from distinguishing them (e.g., `1` = bad input, `2` = remote unreachable, `3` = partial success).

## Machine-Readable Output

- When humans and machines both consume the CLI, offer `--json` or `--format json`.
- Default to human-readable; switch to machine-readable on explicit flag, not by TTY detection alone (detection breaks CI redirects).
