# Intent Router — retired from this repo

This hook is no longer maintained as an example here. It ships as a Claude Code plugin:
**[claude-intent-router](https://github.com/asaphe/claude-intent-router)**.

```text
/plugin marketplace add asaphe/claude-intent-router
/plugin install intent-router@claude-intent-router
```

## What the plugin does that this example did not

The example hardcoded the skill names it routed to, so adopting it meant editing the script.
The plugin reads `~/.claude/intent-router.config.json` for project-specific skill names and
vocabulary, and falls back to generic text when no config is present. It also routes intents
this example never covered — planning triggers, design-document authoring and review,
explicit imperatives, and `pause` — and ships the `skeptic` agent that the review intent
defers to.

The design rules the example taught still hold and are documented in the plugin's README:
high precision over recall, a short-prompt length gate, injection via
`hookSpecificOutput.additionalContext` rather than invoking a skill directly, and no
per-session stamp.
