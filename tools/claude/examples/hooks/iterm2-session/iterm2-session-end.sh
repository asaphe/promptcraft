#!/usr/bin/env bash
# SessionEnd hook — resets iTerm2 tab color and title when Claude Code exits.
# Pair with iterm2-session-start.sh.

{
  printf '\033]6;1;bg;*;default\a'
  printf '\033]1;\007'
} > /dev/tty 2>/dev/null

exit 0
