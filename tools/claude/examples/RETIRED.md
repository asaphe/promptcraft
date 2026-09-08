# Retired examples

Examples that used to live here and no longer do. Each one moved into a maintained Claude
Code plugin, or was withdrawn. If you copied one of these into your own `.claude/`, this
table says what to replace it with.

Nothing in `tools/claude/examples/` is versioned or installable — that is the point of the
move. A plugin gets a manifest, a release, and a place for bugs to be filed against it; a
markdown example in a reference repo gets none of those, and drifts silently from the thing
it was distilled from.

## Moved to a plugin

| Retired path | Replacement | Plugin |
|---|---|---|
| `hooks/intent-router/` | `hooks/intent-router.sh` | [claude-intent-router](https://github.com/asaphe/claude-intent-router) |
| `agents/review/skeptic.md` | `agents/skeptic.md` | [claude-intent-router](https://github.com/asaphe/claude-intent-router) |
| `hooks/learning-capture/` | `/learning-loop:wrap-up`, `:eval`, `:learn` | [claude-learning-loop](https://github.com/asaphe/claude-learning-loop) |
| `agents/learning-classifier.md` | `/learning-loop:eval` | [claude-learning-loop](https://github.com/asaphe/claude-learning-loop) |
| `skills/scan-history.md` | `/learning-loop:learn-scan` | [claude-learning-loop](https://github.com/asaphe/claude-learning-loop) |
| `skills/graduate-learnings.md` | `/learning-loop:learn` | [claude-learning-loop](https://github.com/asaphe/claude-learning-loop) |
| `skills/wrap-up.md` | `/learning-loop:wrap-up` | [claude-learning-loop](https://github.com/asaphe/claude-learning-loop) |
| `hooks/op-read-guard/` | `scripts/op-read-guard.sh` | [claude-secret-guard](https://github.com/asaphe/claude-secret-guard) |
| `hooks/op-cache-cleanup/` | `scripts/op-cache-cleanup.sh` | [claude-secret-guard](https://github.com/asaphe/claude-secret-guard) |
| `scripts/op-cache.sh` | `scripts/op-cache.sh` (masked by default) | [claude-secret-guard](https://github.com/asaphe/claude-secret-guard) |
| `skills/pr-review.md` | `/reviewkit:review` | [claude-reviewkit](https://github.com/asaphe/claude-reviewkit) |
| `skills/pr-finalize.md` | `/reviewkit:finalize` | [claude-reviewkit](https://github.com/asaphe/claude-reviewkit) |

Install commands are in each plugin's README, and in the stub README left at each retired
hook directory.

## Withdrawn, with nothing to install

| Retired path | Why |
|---|---|
| `hooks/secretsmanager-proxy/` | It rewrote `aws secretsmanager get-secret-value` to bypass output filtering, which put the full plaintext secret in the transcript on every call. Use `sm-cache.sh` from [claude-secret-guard](https://github.com/asaphe/claude-secret-guard), which caches at mode 600 and prints a masked confirmation. Remove this hook if you installed it. |
| `hooks/pre-claim-guard/` | Dropped from the config it was distilled from, and it never worked as shipped: it wrote its checklist to stderr on exit 0, which Claude Code discards. The rule it was reaching for — verify a cloud-state claim against the live API before asserting it in a review — belongs in a rules file, not a hook. |

## Why the stub READMEs stay

Each retired hook directory keeps its `README.md` as a pointer rather than being deleted
outright, so an existing link to `examples/hooks/<name>/` still lands somewhere that says
where the thing went. The leaf files above have no stub; this table is their pointer.
