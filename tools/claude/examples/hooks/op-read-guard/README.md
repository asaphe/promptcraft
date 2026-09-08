# 1Password Read Guard — retired from this repo

This hook is no longer maintained as an example here. It ships as
`scripts/op-read-guard.sh` in a Claude Code plugin:
**[claude-secret-guard](https://github.com/asaphe/claude-secret-guard)**.

```text
/plugin marketplace add asaphe/claude-secret-guard
/plugin install secret-guard@claude-secret-guard
```

## What the plugin does that this example did not

The example deduplicated `op read` to save biometric prompts. The plugin treats the same
commands as a secret-exposure problem first: `op read`, `op item get --reveal`/`--otp`, and
`op run --no-masking` are blocked outright and redirected to a masked cache wrapper, so the
value never reaches the transcript. Deduplication is a side effect of the cache, not the goal.

It also closes fail-opens the example had: no wrapper-path exemption (a `# see op-cache.sh`
comment used to turn a real fetch into a pass), per-segment evaluation so
`op item get X && op-cache.sh --reveal <uri>` is judged on the segment that owns the flag,
and a symlink defense plus `umask 077` on the session track file.
