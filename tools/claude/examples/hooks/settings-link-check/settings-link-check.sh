#!/usr/bin/env bash
# SessionStart: warn when the live settings.json stops being a symlink to the tracked dotfiles copy, because tracked edits then never reach the live file. Registration JSON: README.md.

set -uo pipefail

LIVE="${SETTINGS_LINK_LIVE:-$HOME/.claude/settings.json}"
TRACKED="${SETTINGS_LINK_TRACKED:-$HOME/dotfiles/claude/settings.json}"

[ -L "$LIVE" ] && [ -f "$TRACKED" ] && [ "$LIVE" -ef "$TRACKED" ] && exit 0

tilde() { case "$1" in "$HOME"/*) printf '%s' "~${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
L=$(tilde "$LIVE")
D=$(tilde "$TRACKED")
if [ ! -e "$TRACKED" ]; then
  STATE="the dotfiles copy $D is missing"
elif [ ! -e "$LIVE" ] && [ ! -L "$LIVE" ]; then
  STATE="$L is missing"
elif [ -L "$LIVE" ]; then
  STATE="$L points to $(readlink "$LIVE") instead of $D"
else
  WHEN=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$LIVE" 2>/dev/null || stat -c '%y' "$LIVE" 2>/dev/null | cut -c1-16)
  STATE="$L is a regular file, last written ${WHEN:-at an unknown time}, not a symlink to $D"
fi

DIFF=$(python3 - "$LIVE" "$TRACKED" 2>&1 <<'EOF'
import json, os, sys
live, tracked = sys.argv[1], sys.argv[2]
if not (os.path.isfile(live) and os.path.isfile(tracked)):
    sys.exit(0)
try:
    a, b = json.load(open(live)), json.load(open(tracked))
except ValueError as exc:
    print(f"could not compare the two files: {exc}")
    sys.exit(0)
def groups(s):
    return {(ev, json.dumps(g, sort_keys=True)) for ev, gs in (s.get("hooks") or {}).items() for g in gs}
def name(item):
    ev, g = item
    cmds = [os.path.basename(h.get("command", "?").split()[0]) for h in json.loads(g).get("hooks", [])]
    return f"{ev}:{'+'.join(cmds)}"
parts = []
for label, x, y in (("only in the live file", a, b), ("only in the dotfiles copy", b, a)):
    hooks = sorted(name(i) for i in groups(x) - groups(y))
    keys = sorted(k for k in x if k != "hooks" and x.get(k) != y.get(k))
    if hooks or keys:
        bits = ([f"{len(hooks)} hook group(s): {', '.join(hooks[:6])}{' …' if len(hooks) > 6 else ''}"] if hooks else []) \
            + ([f"setting(s): {', '.join(keys[:6])}"] if keys else [])
        parts.append(f"{label}: " + "; ".join(bits))
print(". ".join(parts) if parts else "contents are identical")
EOF
)

MSG="settings.json is no longer linked to dotfiles — ${STATE}. Edits to ${D} are not live until it is re-linked.${DIFF:+ Difference: ${DIFF}.} To fix: back up ${L}, copy its live-only entries into ${D}, then run: ln -sfn ${D} ${L}"
CTX="${MSG} Raise this with the user before changing any Claude Code setting, and do not treat either copy as the live one until it is resolved."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg m "$MSG" --arg c "$CTX" '{systemMessage:$m, hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$c}}'
else
  printf '%s\n' "$CTX"
fi
exit 0
