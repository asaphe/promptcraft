# Bash Command Patterns

Non-obvious gotchas and conventions when invoking the Bash tool, `gh`, and other CLIs from Claude Code or shell scripts.

- **Never start bash commands with `#` comments** — use the Bash tool's `description` parameter instead.
- **When writing inline Python / scripts with heredocs containing `#` comments and quotes**, write the script to a file first, then run it separately. Heredoc quoting interactions with `#` and embedded quotes silently produce wrong content otherwise.
- **Prefer separate parallel Bash calls** over chaining with `;` or `&&` when commands are independent. Parallel tool calls run concurrently; chained commands run sequentially in one shell and lose individual error visibility.

## `gh api` patterns

- **Use `--input` for `gh api` payloads with nested arrays / objects** — `gh api --field` stringifies nested JSON (arrays, objects), causing 422 errors. For structured payloads (PR reviews with `comments[]`, GraphQL with nested variables), write the JSON to a temp file and use `--input /tmp/payload.json`.
- **`gh api` switches from GET to POST the moment any `-f` / `-F` is present.** For GET requests that need query parameters, add `--method GET` explicitly.
- **`-F` and `-f` always send strings, not integers.** The PR comment reply endpoint requires `in_reply_to` as a JSON integer; sending it via `-F in_reply_to=12345` produces a 422 ("not a number"). Use `--input` with a JSON file for any endpoint that requires non-string types:

  ```bash
  cat > /tmp/reply.json <<EOF
  {"body": "...", "in_reply_to": 3145702701}
  EOF
  gh api repos/{owner}/{repo}/pulls/{n}/comments --input /tmp/reply.json
  ```

## `gh pr edit` and bodies

- **Compose PR bodies in one shot** — never incrementally patch via repeated `gh pr edit --body`. Each call rewrites the full body. Build the complete body first, then post once.

## GitHub rulesets

- **`PUT /rulesets/{id}` replaces the entire `rules` array** — always `GET` the full ruleset first (`gh api repos/{org}/{repo}/rulesets/{id}`) and include ALL rule types in the PUT payload. A scoped GET (e.g., `jq 'select(.type == "required_status_checks")'`) hides other rule types that will be silently dropped — including `pull_request`, `deletion`, `non_fast_forward`, and `branch_name_pattern`.

## CLI flag refactors

- **Check `--help` before committing CLI flag refactors** — shellcheck and actionlint validate shell syntax, not CLI semantics. Before committing any change that alters how a CLI is invoked (adding / removing / reordering flags, changing arg structure, switching between URL-embedded and flag-based args), check the tool's actual runtime behavior. Default behaviors shift in subtle ways: `gh api` switches GET to POST on any `-f` / `-F`; `aws` flag order changes stdout vs stderr for some subcommands; `kubectl --force` means different things per resource.

## Path expansion gotchas

- **The Glob tool's `pattern` does NOT expand `~`** — silent zero-match failure. `Glob({pattern: "~/foo/*"})` returns nothing even when files exist. For tilde-relative checks, use Bash (which does expand `~`) or pass an absolute path.

## `set -e` traps

- **`set -e` does not reliably catch `git merge --ff-only` failures in chained Bash tool calls** — the merge prints `fatal: Not possible to fast-forward, aborting.` but the script continues to subsequent commands. Either explicitly check the exit code (`git merge --ff-only origin/main || exit 1`) or use `git rebase origin/main` which fails loudly. The unchecked path corrupts squashes silently — keep a backup branch.

## macOS `/bin/bash` 3.2

- **`${array[-1]}` is unsupported** in bash 3.2 — silently expands to empty string with `bad array subscript` to stderr. Bash 4.2+ supports negative indexing, but the system bash on macOS is 3.2 forever. Use a `for d in glob/*/; do last="$d"; done` loop pattern instead. Affects any code that runs through a snapshot-replayed shell or system `bash`.
- **`${var:offset:length}` is byte-based on bash 3.2** (macOS `/bin/bash`) but character-based on bash 5.x (Linux / CI). Multi-byte characters (em-dash = 3 bytes) produce different output. Use `perl -CSD -ne 'print substr($_, 0, N)'` for portable character-based truncation.

## Claude Code shell snapshot

- **Single-underscore shell functions get filtered out of Claude Code's shell snapshot** — the snapshot tool treats `_*` as zsh autoload completion helpers. Wrappers that depend on a single-underscore helper (e.g., lazy-load shims like `_load_nvm`) break in the harness shell because the wrapper survives but the helper disappears. Use no leading underscore or two leading underscores (`__helper`) for helpers that need to survive snapshotting. Symptom: `<wrapper>:1: command not found: _<helper>` error or `FUNCNEST` infinite recursion.

## Slash command interactions

- **Slash commands with `disable-model-invocation: true` cannot be invoked by skills.** Skills must call the underlying companion script or binary directly. Don't write `Skill(plugin:command)` from another skill if `disable-model-invocation: true` is set on the target — it won't fire.
