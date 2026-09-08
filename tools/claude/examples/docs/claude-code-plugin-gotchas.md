# Claude Code Plugin Gotchas — the Process Registry

The skill/agent registry is built **once, at process start**. Everything below follows from that one fact, and it is the thing that makes mid-session plugin development confusing: the on-disk state and the running session disagree, silently, with no error on either side.

Verified against Claude Code 2.1.263. Re-check the CLI surface before relying on the commands here — `claude plugin --help` is authoritative.

## Two failure modes, not one

**1. A newly-installed plugin is not resolvable at all until the process restarts.**

`Skill(skill='...')` returns `Unknown skill` and `Agent(subagent_type='...')` returns `Agent type not found`, even after the install succeeded and the on-disk cache is confirmed populated.

`/clear` does **not** count as a restart. It clears conversation history, not the process. Only killing and relaunching the `claude` CLI picks up a newly-installed plugin. The CLI says so itself — `claude plugin update --help` describes the command as *"Update a plugin to the latest version (restart required to apply)"*.

**2. An already-resolved plugin agent stays frozen at the content it had when the process started.**

This is the one that costs real time, because it produces no error. An agent dispatched via `Agent(subagent_type='<plugin>:<agent-name>')` in a still-running process can return output generated from the **pre-update** persona, after the on-disk cache has been refreshed, with no warning that anything is stale.

The only way to catch it is to check the agent's own output for content that could only exist post-update — a specific checklist item, a renamed section, a pattern count — and cross-reference against what the updated file actually contains. A plausible-looking result from a stale persona is indistinguishable from a correct one.

## Refreshing the cache

Two directories, and updating one does not update the other:

| Path | What it is | Refreshed by |
|---|---|---|
| `~/.claude/plugins/marketplaces/<marketplace>/` | The marketplace's own clone | `claude plugin marketplace update <marketplace>` |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | The installed-plugin snapshot Claude Code actually reads | `claude plugin update <plugin>` |

Note the cache path ordering — marketplace, then plugin, then version. Several versions of the same plugin can coexist under it.

`claude plugin install` on an already-installed plugin is a no-op (`already installed`); it does not re-sync anything. Use `claude plugin update` for an installed plugin, and reserve uninstall-then-install for the case where you need a specific version replaced outright.

## Verification recipe

Before trusting a live validation pass against a just-updated plugin, confirm the process genuinely postdates the update:

```bash
# Walk the process tree from the current shell to find the `claude` parent PID, then:
ps -o pid,lstart,command -p <claude_pid>
stat -f "%Sm %N" ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/agents/<agent>.md   # macOS
stat -c "%y %n" ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/agents/<agent>.md    # GNU
```

If the process start time predates the cache mtime, every dispatch of that plugin's agents in this session is running stale content regardless of what is on disk.

## Validating updated agent content without restarting

A named-agent dispatch is not evidence either way in the same process — it may silently run the pre-update persona. To test updated agent content before a restart, dispatch a **general-purpose** agent with the updated file's content pasted in as a literal prompt, so nothing depends on `subagent_type` resolution.

That is a workaround for the content, not for the packaging. A clean validation of the actual packaged plugin — its manifest, its component wiring, its declared name — needs a real process restart.

## Checklist

1. `claude plugin marketplace update <marketplace>` — refreshes the marketplace source clone only.
2. `claude plugin update <plugin>` — re-syncs the installed cache. Confirm with a cache-file mtime check and a `grep` for the new content.
3. Validate content in-session only via a literal-prompt dispatch; treat a `subagent_type` dispatch as unreliable until restart.
4. Restart the CLI for a genuine end-to-end test.
