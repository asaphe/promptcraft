#!/usr/bin/env bash
# SessionStart hook — sets iTerm2 tab color and title when a Claude Code session starts.
#
# Color is derived from repo+branch via cksum → position on color wheel.
# Same repo+branch always produces the same color, with no hardcoded map.
# Works for any repo and any user.
#
# Writes to /dev/tty to bypass Claude Code's stdout capture.

CWD="$PWD"
BRANCH=$(git -C "$CWD" --no-optional-locks branch --show-current 2>/dev/null || true)
REPO=$(git -C "$CWD" remote get-url origin 2>/dev/null | sed 's|.*/||; s|\.git$||')
[ -z "$REPO" ] && REPO=$(basename "$CWD")

# Deterministic color: hash repo:branch → hue → saturated RGB
SEED="${REPO}:${BRANCH:-main}"
HASH=$(printf '%s' "$SEED" | cksum | awk '{print $1}')
HUE=$(( HASH % 360 ))
SECTOR=$(( HUE / 60 ))
FRAC=$(( (HUE % 60) * 255 / 60 ))
case $SECTOR in
  0) R=255;             G=$FRAC;            B=0    ;;
  1) R=$(( 255-FRAC )); G=255;              B=0    ;;
  2) R=0;               G=255;              B=$FRAC ;;
  3) R=0;               G=$(( 255-FRAC ));  B=255  ;;
  4) R=$FRAC;           G=0;               B=255   ;;
  5) R=255;             G=0;               B=$(( 255-FRAC )) ;;
  *) R=128;             G=128;             B=128   ;;
esac

# Title: [repo] branch on feature branches, [repo] ~/path on main
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  TITLE="[$REPO] $BRANCH"
else
  SHORT_CWD=$(printf '%s' "$CWD" | sed "s|^$HOME|~|")
  TITLE="[$REPO] $SHORT_CWD"
fi

{
  printf '\033]6;1;bg;red;brightness;%d\a'   "$R"
  printf '\033]6;1;bg;green;brightness;%d\a' "$G"
  printf '\033]6;1;bg;blue;brightness;%d\a'  "$B"
  printf '\033]1;%s\007' "$TITLE"
} > /dev/tty 2>/dev/null

exit 0
