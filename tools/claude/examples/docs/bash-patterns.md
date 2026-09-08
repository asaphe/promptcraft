# Bash Command Patterns

Non-obvious gotchas and conventions when invoking the Bash tool, `gh`, and other CLIs from Claude Code or shell scripts. This doc is read on demand. Constructs that return a *confident wrong answer* rather than an error live in `../rules/general/shell-traps.md`, which is always-loaded because they have to fire while a command is being written; two bullets below overlap it deliberately.

- **Never start bash commands with `#` comments** — use the Bash tool's `description` parameter instead.
- **When writing inline Python / scripts with heredocs containing `#` comments and quotes**, write the script to a file first, then run it separately. Heredoc quoting interactions with `#` and embedded quotes silently produce wrong content otherwise.
- **Prefer separate parallel Bash calls** over chaining with `;` or `&&` when commands are independent. Parallel tool calls run concurrently; chained commands run sequentially in one shell and lose individual error visibility.
- **Shell variables do not persist across separate Bash tool calls** — capture a value a later command needs (e.g. a git SHA for `--force-with-lease`) and use it within the SAME atomic call. Splitting capture and use across two calls silently uses an empty variable, and `--force-with-lease=` with an empty expected-value is rejected as "stale info" — a symptom that reads as a real concurrent-push conflict rather than a shell-state bug.

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

- **`gh api -f field="@path"` posts the literal string `@path`, not the file's contents** — the `@<path>` / `@-` file-read convenience is documented only for `-F` / `--field` (typed parameter); `-f` / `--raw-field` always treats its value as a raw string, with no special-casing for a leading `@`. The call still returns 200 with a valid created object (comment, review, issue) — there is no error signal distinguishing the broken invocation from a correct one, and it stays invisible until a human reads the rendered content. To source a field's value from a file, read it into a shell variable first (`-f field="$(cat path)"`), or switch to `-F field="@path"` if that field's typed-parameter coercion (numbers / booleans / JSON) is acceptable.
- **`/repos/{owner}/{repo}/installation` and `/orgs/{org}/installations/{id}/repositories` both fail under an ordinary `gh` token** — the first requires app-JWT auth (401, "A JSON web token could not be decoded"); the second requires an installation-level token, which even an org-admin `gh` token does not hold (404). Neither confirms *nor* denies a GitHub App's access to a repo, so a 404 here is not evidence the App lacks access. To check an App's real installation scope, search the org audit log for grant events (`gh api "/orgs/{org}/audit-log?phrase=repo:{owner}/{repo}"`, filtered for `integration_installation` actions); if nothing matches — installed before the retention window, or granted at repo creation — fall back to indirect proof, such as a prior green run of a workflow that used that App's token against the repo.

## `gh pr edit` and bodies

- **Compose PR bodies in one shot** — never incrementally patch via repeated `gh pr edit --body`. Each call rewrites the full body. Build the complete body first, then post once.
- **For PR / issue bodies with backticks, always use `--body-file`** — write the body to `/tmp/body.md` then `gh pr create/edit --body-file /tmp/body.md`. This sidesteps the entire `$()` + heredoc escaping question. If you do use `--body "$(cat <<'EOF'...)"` instead: `<<'EOF'` passes everything literally so backticks are safe raw — but the temptation to escape them with `` \` `` is high, and `` \` `` renders as a literal backslash-backtick in GitHub markdown, not a code span. `--body-file` eliminates the ambiguity entirely. Verify the rendered body after posting.

## GitHub rulesets

- **`PUT /rulesets/{id}` replaces the entire `rules` array** — always `GET` the full ruleset first (`gh api repos/{org}/{repo}/rulesets/{id}`) and include ALL rule types in the PUT payload. A scoped GET (e.g., `jq 'select(.type == "required_status_checks")'`) hides other rule types that will be silently dropped — including `pull_request`, `deletion`, `non_fast_forward`, and `branch_name_pattern`.

## CLI flag refactors

- **Check `--help` before committing CLI flag refactors** — shellcheck and actionlint validate shell syntax, not CLI semantics. Before committing any change that alters how a CLI is invoked (adding / removing / reordering flags, changing arg structure, switching between URL-embedded and flag-based args), check the tool's actual runtime behavior. Default behaviors shift in subtle ways: `gh api` switches GET to POST on any `-f` / `-F`; `aws` flag order changes stdout vs stderr for some subcommands; `kubectl --force` means different things per resource.
- **A flag existing ≠ the flag combination working — run the exact command line before committing.** CLI tools reject specific flag *combinations* at runtime with no static signal (`gh api --slurp` exists but is rejected together with `--jq`; `--paginate --jq` runs jq per-page instead of once over the combined result). Checking `--help` for the flag, or testing each flag separately, proves nothing about the composed invocation. Before committing any non-trivial CLI line (gh, aws, jq pipelines, terraform): execute the exact line — all flags together, against a real endpoint — and verify the output shape, not just exit 0. Same discipline as "lint is not a runtime test", applied to single commands.

## jq defaults

- **`jq`'s `//` operator triggers on null AND false, not just null** — for boolean defaults that must distinguish explicit `false` from absent, `.features.enabled // true` returns `true` when the value is explicitly `false`, silently defeating the gate. Use `if . == null then DEFAULT else . end` instead. `// false` happens to work because both null and false yield the default; `// true` is broken.

## Path expansion gotchas

- **The Glob tool's `pattern` does NOT expand `~`** — silent zero-match failure. `Glob({pattern: "~/foo/*"})` returns nothing even when files exist. For tilde-relative checks, use Bash (which does expand `~`) or pass an absolute path.

## `set -e` traps

- **`set -e` does not reliably catch `git merge --ff-only` failures in chained Bash tool calls** — the merge prints `fatal: Not possible to fast-forward, aborting.` but the script continues to subsequent commands. Either explicitly check the exit code (`git merge --ff-only origin/main || exit 1`) or use `git rebase origin/main` which fails loudly. The unchecked path corrupts squashes silently — keep a backup branch.

## macOS `/bin/bash` 3.2

- **`${array[-1]}` is unsupported** in bash 3.2 — silently expands to empty string with `bad array subscript` to stderr. Bash 4.2+ supports negative indexing, but the system bash on macOS is 3.2 forever. Use a `for d in glob/*/; do last="$d"; done` loop pattern instead. Affects any code that runs through a snapshot-replayed shell or system `bash`.
- **`${var:offset:length}` is byte-based on bash 3.2** (macOS `/bin/bash`) but character-based on bash 5.x (Linux / CI). Multi-byte characters (em-dash = 3 bytes) produce different output. Use `perl -CSD -ne 'print substr($_, 0, N)'` for portable character-based truncation.

## BSD vs GNU coreutils

- **macOS `base64` requires `-i <file>`, not a bare positional argument** — GNU `base64` (Linux) accepts a filename as a trailing positional arg; BSD `base64` (macOS) does not, and silently reads stdin instead, so a bare `base64 <file>` encodes empty stdin rather than the file. Use `base64 -i <file>` to encode and `base64 -d -i <file>` to decode in any cross-platform script.
- **A base64 decode error is usually a symptom of the call that produced the input** — piping a non-base64 body (a 404 JSON response from a failed `gh api` / `curl`) into `base64 -d` produces a generic "error decoding base64 input stream". Check the raw input before assuming the decoder is at fault.

## zsh reserved variable names

- **zsh reserves several short lowercase names as special variables** — `status`, `path` and `history` among them. Assigning one as an ordinary script-local (`local status=…` in a polling loop) fails with `read-only variable: status`, a symptom that reads as unrelated to the script's actual logic. Avoid these names outright; prefix or rename (`bstatus`).

## AWS CLI pagination

- **`--starting-token` can collide with an implicit `--no-paginate`** — `aws cloudtrail lookup-events --starting-token <token>` has been observed failing with `Cannot specify --no-paginate along with pagination arguments: --starting-token` with no alias or env var to explain it. A loop's own error handling then swallows the failure and truncates a multi-page sweep to page one, while still reporting "N pages fetched" — every page past the first contributed zero rows. For anything beyond a single page, prefer the SDK's paginator (boto3 `client.get_paginator('lookup_events').paginate(...)`) over a hand-rolled `--starting-token` loop.

## CI-only redaction does not apply locally

- **`::add-mask::` only redacts inside an Actions runner — running the same script locally prints the raw secret.** `::add-mask::<value>` is a workflow command consumed by the runner's log processor; it has no effect on a plain stdout stream. A script written for CI that emits `::add-mask::` before logging a credential — trusting the runner to redact downstream — prints that credential in cleartext when invoked directly from an interactive shell for local testing or recovery, and in an agent session that cleartext lands in the transcript. Before running any script under `.github/actions/` or `.github/scripts/` locally, grep it for logging of sensitive values (`grep -n 'add-mask\|print.*\(secret\|token\|key\)' <script>`). If it logs any, either redirect stdout and stderr to a throwaway file and read back only the specific non-sensitive fields you need, deleting the file unread, or do not run it locally at all. The seductive part is that calling `add_mask()` makes the script *look* safe to run anywhere.

## Claude Code shell snapshot

- **Single-underscore shell functions get filtered out of Claude Code's shell snapshot** — the snapshot tool treats `_*` as zsh autoload completion helpers. Wrappers that depend on a single-underscore helper (e.g., lazy-load shims like `_load_nvm`) break in the harness shell because the wrapper survives but the helper disappears. Use no leading underscore or two leading underscores (`__helper`) for helpers that need to survive snapshotting. Symptom: `<wrapper>:1: command not found: _<helper>` error or `FUNCNEST` infinite recursion.

## Slash command interactions

- **Slash commands with `disable-model-invocation: true` cannot be invoked by skills.** Skills must call the underlying companion script or binary directly. Don't write `Skill(plugin:command)` from another skill if `disable-model-invocation: true` is set on the target — it won't fire.
