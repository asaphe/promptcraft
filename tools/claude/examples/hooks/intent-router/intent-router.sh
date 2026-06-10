#!/usr/bin/env bash
# UserPromptSubmit hook — routes short free-text prompts ("merged", "status?", "comments?") to the matching skill or follow-up action by injecting context. Never invokes a skill itself — only injects; the assistant decides. Skill names map to skills shipped alongside this repo (pr-check, pr-review, pr-finalize) — swap for your own. Full rationale and registration JSON: README.md.

INPUT=$(cat)
PROMPT=$(printf '%s\n' "$INPUT" | jq -r '.prompt // empty')

# Skip if empty, long (free-form work, not a trigger phrase), or a slash command.
[ -z "$PROMPT" ] && exit 0
[ "${#PROMPT}" -gt 200 ] && exit 0
case "$PROMPT" in /*) exit 0 ;; esac

# Normalize: lowercase, collapse whitespace.
NORM=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')

CTX=""

# Intent 1: user reports a merge happened outside the assistant's tool surface.
if printf '%s\n' "$NORM" | grep -qE '^(i merged|merged|pr merged|merged all|merged the|merged [0-9]+)( |\.|$)'; then
  CTX="${CTX}INTENT — USER-INITIATED MERGE DETECTED. Required before any other response:
  1. Cite the PR number + linked ticket (parse the branch name for a ticket ID if not stated).
  2. Update your tracker: move the linked ticket to done.
  3. Surface unresolved follow-ups from this session (open PRs, deferred items, pending CI).
  4. State the next item in the work queue, or ask explicitly if no queue exists.
  Do not lead with a new question — lead with state confirmation.
"
fi

# Intent 2: status probe — a prior turn promised proactive reporting and didn't deliver.
if printf '%s\n' "$NORM" | grep -qE '^(status\??|any (status|update)s?\??|update( me)?\??|how is it going|where are we|where we at|whats the status)( |$|\.)'; then
  CTX="${CTX}INTENT — STATUS PROBE. User is checking on prior in-flight work. Before answering:
  1. Enumerate ALL pending state: background shell IDs, dispatched agents, CI runs being watched, in-flight skills.
  2. For each: fetch current state (background shell output, gh run watch / gh pr checks, agent status).
  3. Report concrete state — not 'let me check', not 'I'll get back to you'. The user is asking BECAUSE you didn't surface proactively.
"
fi

# Intent 3: check / resolve PR comments → pr-check skill.
if printf '%s\n' "$NORM" | grep -qE '^((any |new )?comments?\??|check (for |the )?comments?( on (the )?prs?)?|(review|address|resolve) (comments?|threads?|feedback)( on (the )?prs?)?|whats on the pr|pr feedback)( |$|\.)'; then
  CTX="${CTX}INTENT — COMMENT/THREAD SWEEP (skill routing). REQUIRED: your next tool call MUST be Skill(skill='pr-check'), passing the PR number as args if the user named one. The skill encapsulates the codified comment-query discipline: per-comment multi-field projection, individual comment classification (never bulk-label-stale), reply-then-resolve via GraphQL resolveReviewThread. Doing this manually via raw 'gh api' calls is a skill-routing violation — the manual path misattributes bot/author comments. Exception: if the user's ask is materially narrower than the skill scope (e.g., 'how many comments?'), surface the mismatch in one line and act on the answer.
"
fi

# Intent 4: PR review request → pr-review skill.
if printf '%s\n' "$NORM" | grep -qE '^(review (the |this )?pr|run (the )?review|trigger (the )?review|adversarial review|reviewers?\??)( |$|\.)'; then
  CTX="${CTX}INTENT — PR REVIEW (skill routing). REQUIRED: your next tool call MUST be Skill(skill='pr-review'), passing the PR number as args if named. The skill routes the diff to specialized reviewers and enforces the verification gate before any finding is posted or dismissed. Doing review manually skips those gates. Exception: same as comment-sweep — if the user's ask is narrower (e.g., 'is the diff sane?'), surface and confirm.
"
fi

# Intent 5: finalize / ready-to-merge check → pr-finalize skill.
if printf '%s\n' "$NORM" | grep -qE '^(finalize|is (the )?pr ready|ready to merge|merge ready|wrap up (the )?pr|pre-merge|all (set|done|good) for merge)( |$|\.|\?)'; then
  CTX="${CTX}INTENT — FINALIZE PRE-MERGE GATE (skill routing). REQUIRED: your next tool call MUST be Skill(skill='pr-finalize'), passing PR number(s) as args if named. The skill runs the full pre-merge gate (CI status, thread sweep, body-vs-diff, commit history, tracker ticket, assignee) and explicitly never merges. Doing this manually misses one or more gates. Exception: same pattern — if the ask is narrower (e.g., 'just check CI'), surface and confirm.
"
fi

# Intent 6: session-queue / next-item check. No skill — session-wrap signal.
if printf '%s\n' "$NORM" | grep -qE '^(anything else( from this session)?\??|whats (left|next|still pending)|whats next( item)?|next( task| item| pr)?\??|whats remaining|are we done|done\??|is the session done)( |$|\.|\?)'; then
  CTX="${CTX}INTENT — SESSION QUEUE / NEXT ITEM. The user is asking what remains. Before answering:
  1. List all PRs touched this session — their state (open/merged/closed), CI status, open threads.
  2. List all tracker tickets touched — status, blockers.
  3. List deferred items the user explicitly named ('out of scope', 'follow-up', 'next session').
  4. Then propose the next concrete action or confirm the session can close.
  Do not answer 'yes' or 'no' without the enumeration above.
"
fi

# Intent 7: link request — the user asks for PR URL(s).
if printf '%s\n' "$NORM" | grep -qE '^(links?( to (the )?(pr|prs))?\??|link to (the )?pr|where.{0,15}pr|url|share the link|give me the link)( |$|\.|\?)'; then
  CTX="${CTX}INTENT — PR URL REQUEST. User wants the URL(s) of the PR(s) under work. Fetch via 'gh pr view --json url,number,title' for the current branch and any other PRs opened in this session. Surface as a list with PR number + title + URL. Do not summarize — just give links.
"
fi

[ -z "$CTX" ] && exit 0

jq -n --arg ctx "$CTX" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
