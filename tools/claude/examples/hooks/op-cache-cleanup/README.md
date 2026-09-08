# op-cache-cleanup — retired from this repo

This hook and its companion cache script are no longer maintained as examples here. Both
ship in a Claude Code plugin: **[claude-secret-guard](https://github.com/asaphe/claude-secret-guard)**,
as `scripts/op-cache-cleanup.sh` and `scripts/op-cache.sh`.

```text
/plugin marketplace add asaphe/claude-secret-guard
/plugin install secret-guard@claude-secret-guard
```

## What the plugin does that this example did not

The plugin's cleanup hook purges both cache directories — 1Password and AWS Secrets
Manager — and the caches it purges are masked by default: `op-cache.sh` and `sm-cache.sh`
print a confirmation and the mode-600 cache path rather than the secret value, so the value
never enters the transcript in the first place. This example's cache printed the value and
relied on cleanup alone.

Cache paths key on the Claude Code session id, with a fallback that no longer uses a bare
parent PID — PIDs recycle, and two unrelated shells could land on one cache path where a
stale hit serves the wrong value.
