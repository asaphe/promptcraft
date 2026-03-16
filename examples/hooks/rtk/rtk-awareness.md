# RTK (Rust Token Killer) Awareness

- **RTK hook is active** — A PreToolUse hook auto-rewrites Bash commands to use `rtk` prefixes for token savings. If a command fails after rewrite, check whether RTK filtering caused the issue — retry with `rtk proxy <cmd>` (passes through without filtering) or the raw command directly to confirm.

- **Monitor RTK filtering quality** — When command output looks unexpectedly truncated or missing expected content, RTK filtering may be too aggressive. Check `~/.local/share/rtk/tee/` for the original vs filtered output. Report false positives so the team can tune filters.

- **RTK meta commands are not rewritten** — `rtk gain`, `rtk discover`, `rtk proxy`, `rtk tee` are direct RTK commands, not proxied. Use these for diagnostics without the hook interfering.

- **Always use `rtk proxy` for enumeration/decision commands** — RTK truncation on list commands silently hides entries, leading to wrong conclusions (e.g., "resource doesn't exist" when it does). Use `rtk proxy` for: `aws s3 ls`, `terraform workspace list`, `aws secretsmanager list-secrets`, `aws ecr list-images`, and any command where a missing entry changes the decision.
