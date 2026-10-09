#!/usr/bin/env bash
# Destructive operation guard — two-tier blocking system.
#
# HARD BLOCK (stderr + exit 2): Irreversible data loss or forbidden shared-state
#   actions. Cannot be overridden by Bash(*) permissions. User must run the
#   command themselves.
#   Examples: AWS resource deletion, push/force-push to main, gh pr close, and a
#   merge the user did not ask for this turn (see ../merge-grant/).
#
# SOFT BLOCK (JSON permissionDecision "ask" + exit 0): Visible/risky actions
#   that need confirmation. Emits hookSpecificOutput JSON on stdout so Claude
#   Code prompts the user, who can approve in the permission prompt.
#   Examples: PR create (outside a turn whose prompt asked for one), force-push
#   to a feature branch, terraform destroy, kubectl delete, git reset --hard.
#
# Install: add to settings.json under hooks.PreToolUse[].hooks[]
#   { "type": "command", "command": "/path/to/destructive-guard.sh" }
#
# Requires: jq, perl

INPUT=$(cat)
# shellcheck disable=SC2034  # read by the sourced hook-diag.sh
HOOK_DIAG_NAME="destructive-guard"
# Fail CLOSED on a missing dependency: without jq or perl this guard matches nothing and passes everything.
for _dep in jq perl; do
  if ! command -v "$_dep" >/dev/null 2>&1; then
    echo "destructive-guard: '$_dep' not on PATH — refusing to run rather than passing every command unchecked. This blocks every Bash call until it is resolved: install '$_dep', or unregister this hook in settings.json (hooks.PreToolUse)." >&2
    exit 2
  fi
done
source "$(dirname "$0")/../_lib/hook-diag.sh"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Both views must start from the original syntax so data stripping cannot hide nested code.
QUOTE_PARSER="$(dirname "$0")/../_lib/strip-quoted-args.pl"
if ! CMD_STRIPPED=$(printf '%s' "$CMD" | perl "$QUOTE_PARSER" --values) \
   || ! CMD_MATCH=$(printf '%s' "$CMD" | perl "$QUOTE_PARSER"); then
  echo "destructive-guard: command preprocessing failed; refusing to run unchecked." >&2
  exit 2
fi

# Extraction patterns exclude spaces and separators, not quotes, so `cd "path" &&` keeps its quotes.
unquote() {
  local p="$1"
  p="${p%\"}"; p="${p#\"}"
  p="${p%\'}"; p="${p#\'}"
  printf '%s' "$p"
}

# A path extracted from command TEXT is never shell-expanded, so `~/repo` stays literal.
# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — an unexpanded path fails OPEN, not closed
expand_path() {
  local p="$1"
  [ "$p" = "~" ] && { printf '%s' "$HOME"; return; }
  p="${p/#\~\//$HOME/}"
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME/$HOME}"
  printf '%s' "$p"
}

# Redirections go with their targets, so `push>/dev/null`, `2>&1 -f` and `&>/dev/null +main` read as the push they are.
strip_redirs() {
  printf '%s' "$1" | perl -pe 's/(?:(?<=[\s;&|(])|^)\d+(?=[<>])//g; s/(?:&>>?|>\||>>?&?|<<<|<>|<&?)\s*[^\s;&|<>()]*/ /g'
}

# git's global options, so `git stash push` and `git -C <dir> grep checkout` are not read as a push or a switch.
GIT_VAL_RE='("[^"]*"|'\''[^'\'']*'\''|\$\([^()]*\)|[^[:space:]"'\''\\]|\\.)+'
# One list for the regex and the token walk, so the two cannot disagree on which word is the subcommand.
GIT_VAL_OPTS='-C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--attr-source|--shallow-file'
GIT_SUB_RE='git([[:space:]]+('"$GIT_VAL_OPTS"')[[:space:]]+'"$GIT_VAL_RE"'|[[:space:]]+-[^[:space:]]+)*[[:space:]]+'

# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — token walk, and why separators are isolated first
git_sub_args() { # text, subcommand pattern, "keep" to print the subcommand first
  strip_redirs "$1" | sed 's/[;&|]/ & /g' | awk -v want="$2" -v keep="${3:-}" -v vals="$GIT_VAL_OPTS" '
    function open_word(v,   s) { s = v; gsub(/\\./, "", s); return (gsub(/"/, "", s) % 2) || (gsub(/\047/, "", s) % 2) || v ~ /\\$/ }
    {
    out = ""; state = 0
    for (i = 1; i <= NF; i++) {
      w = $i
      if (state == 2) { if (w ~ /^[;&|]$/) break; out = out (out == "" ? "" : " ") w; continue }
      if (state == 0) { if (w ~ /(^|[\/"\047])git$/) state = 1; continue }
      if (w ~ /^[;&|]$/) { state = 0; continue }
      if (w ~ ("^(" vals ")$")) {
        i++; v = $i
        while (i < NF && open_word(v)) { i++; v = v " " $i }
        continue
      }
      if (w ~ /^-/) continue
      if (w ~ ("^(" want ")[\"\047]?$")) {
        # A subcommand that closes its shell string has no arguments: the words after it are the shell positional parameters.
        if (w ~ /["\047]$/) { if (keep) print substr(w, 1, length(w) - 1); else print ""; exit }
        state = 2; if (keep) out = w; continue
      }
      state = 0
    }
    print out
  }'
}

push_args() { git_sub_args "$1" push; }

# A path joined onto the directory it is relative to: "" is the session cwd, "?" a directory the text cannot name.
TOPLEVEL_MARK=$'\001TOPLEVEL'
join_dir() { # base, path
  local p top
  # `"$(…)"/sub` closes its quote before the rest of the word; a multi-word chunk is already QUOTED_ARG, so no quote is data.
  case "$2" in '"'"$TOPLEVEL_MARK"*) set -- "$1" "${2//\"/}" ;; esac
  p=$(expand_path "$(unquote "$2")")
  # A word starting with `$(git rev-parse --show-toplevel)` is that checkout's top plus the rest of the word.
  case "$p" in "$TOPLEVEL_MARK"|"$TOPLEVEL_MARK"/*)
    p=${p#"$TOPLEVEL_MARK"}
    case "$1$p" in *'?'*|*QUOTED_ARG*|*SUBSTITUTION*|*TOPLEVEL*|*'$'*|*'`'*|*'\'*) printf '?'; return ;; esac
    top=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] || { printf '?'; return; }
    printf '%s' "$top$p"
    return ;;
  esac
  case "$p" in
    -|*QUOTED_ARG*|*SUBSTITUTION*|*TOPLEVEL*|*'$'*|*'`'*|*'\'*) printf '?' ;;
    /*) printf '%s' "$p" ;;
    *) case "$1" in '?') printf '?' ;; '') printf '%s' "$p" ;; *) printf '%s/%s' "$1" "$p" ;; esac ;;
  esac
}

# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — the directory each segment runs in
_SEG_DIRS=()
_SEG_TEXT=()
_SEG_GITENV=()
# A segment's `&&` chain (a move counts as done only for a push in its chain) and the loop bodies it repeats in.
_SEG_CHAIN=()
_SEG_LOOP=()
CASE_ARM_RE='^[(]?[^[:space:]()]+[[:space:]]*[)]'
GITDIR_EXPORT_RE='^(export|(declare|typeset|local) +-[a-zA-Z]*x[a-zA-Z]*)( +[^ ]+)* +GIT_DIR(=[^ ]*)?( |$)'
BRANCH_MOVE_VERBS='checkout|switch|branch|worktree|symbolic-ref|rebase'
BRANCH_MOVE_RE="${GIT_SUB_RE}(${BRANCH_MOVE_VERBS})([[:space:]]|\$)"
# Branch moves earlier in the command, so a bare push reads the branch it will run on: segment index, checkout, branch.
_BR_AT=()
_BR_KEY=()
_BR_NAME=()
GITDIR_ASSIGN_RE='^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*GIT_DIR=[^ ]*( +[A-Za-z_][A-Za-z0-9_]*=[^ ]*)*$'
GITDIR_UNSET_RE='^unset( +[^ ]+)* +GIT_DIR( |$)'
resolve_segment_dirs() {
  local i seg bare op cwd="" stack=() envstack=() case_depth=() pops opens closes arm gitenv=""
  local last_op="" op_before chain=0 loops="" loop_n=0 piped cond="" held="" opstack=() saved neg grp_chain="" grp_exit=""
  _SEG_DIRS=()
  _SEG_TEXT=()
  _SEG_GITENV=()
  _SEG_CHAIN=()
  _SEG_LOOP=()
  _BR_AT=()
  _BR_KEY=()
  _BR_NAME=()
  for ((i = 0; i < ${#_SCOPED_TYPES[@]}; i++)); do
    _SEG_DIRS[i]="$cwd"
    _SEG_TEXT[i]=""
    _SEG_GITENV[i]="$gitenv"
    case "${_SCOPED_TYPES[$i]}" in
      O) last_op="${_SCOPED_VALUES[$i]}"; continue ;;
      # A subshell gets a copy of the directory and the exported GIT_DIR, and the parent's come back at its end.
      E) stack[${#stack[@]}]="$cwd"; envstack[${#envstack[@]}]="$gitenv"
         # A substitution runs inside the command around it, so it must not move that command's chain.
         opstack[${#opstack[@]}]="$last_op|$chain|$held|$cond"; continue ;;
      X) cwd="${stack[${#stack[@]}-1]}"; unset 'stack[${#stack[@]}-1]'
         gitenv="${envstack[${#envstack[@]}-1]}"; unset 'envstack[${#envstack[@]}-1]'
         saved=${opstack[${#opstack[@]}-1]}; unset 'opstack[${#opstack[@]}-1]'
         last_op=${saved%%|*}; saved=${saved#*|}; chain=${saved%%|*}; saved=${saved#*|}; held=${saved%%|*}; cond=${saved#*|}
         continue ;;
    esac
    seg="${_SCOPED_VALUES[$i]}"
    # `then` and `do` run only after their condition succeeded, like `&&`; a top-level `a || exit; b` runs b only after a succeeded.
    case "$last_op:$seg" in '||:exit'|'||:exit '*) [ "${#stack[@]}" -gt 0 ] || held=1 ;; '||:{'*) grp_chain=$chain; grp_exit="" ;; esac
    case "$last_op:$cond:$seg" in
      '&&:'*|*:1:'then '*|*:1:then|*:1:'do '*|*:1:do) ;;
      '||:'*:exit|'||:'*:'exit '*) [ -n "$held" ] || chain=$((chain + 1)) ;;
      ';:'*|$'\n:'*) [ -n "$held" ] || chain=$((chain + 1)); held="" ;;
      *) chain=$((chain + 1)); held="" ;;
    esac
    # `a || { …; exit 1; }; b` reaches b only after a succeeded, so the group's close returns to a's chain.
    if [ -n "$grp_chain" ]; then
      case "$seg" in
        exit|'exit '*) grp_exit=1 ;;
        '}'|'} '*) [ -z "$grp_exit" ] || { chain=$grp_chain; held=1; }; grp_chain="" ;;
        *) grp_exit="" ;;
      esac
    fi
    # A negated condition is caught below: its `! ` ends the chain of the move it negates.
    cond=""
    case "$seg" in 'if '*|'elif '*|'while '*|'for '*) cond=1 ;; esac
    op_before=$last_op
    last_op=""
    case "$seg" in 'do '*|do) loop_n=$((loop_n + 1)); loops="$loops:$loop_n" ;; esac
    _SEG_CHAIN[i]=$chain
    _SEG_LOOP[i]="$loops:"
    # A reserved word, a builtin prefix or a case pattern leaves the command after it in charge: `if cd <dir>` still moves.
    arm=""
    neg=""
    while :; do
      # A pattern starts an arm only at the subshell depth its `case` opened at, so `true)` and `esac)` still close one.
      if [ "${#case_depth[@]}" -gt 0 ] && [ -z "$arm" ] && [ "${#stack[@]}" -eq "${case_depth[${#case_depth[@]}-1]}" ] \
         && [[ $seg =~ $CASE_ARM_RE ]] && [[ $seg != 'esac)'* ]]; then
        arm=1; seg="${seg#*')'}"; continue
      fi
      case "$seg" in
        '('*) stack[${#stack[@]}]="$cwd"; envstack[${#envstack[@]}]="$gitenv"; seg="${seg#?}" ;;
        ' '*|'{'*) seg="${seg#?}" ;;
        'case '*' in'|'case '*' in '*) case_depth[${#case_depth[@]}]=${#stack[@]}; arm=""; seg="${seg#* in}" ;;
        '! '*) neg=1; seg="${seg#* }" ;;
        'if '*|'then '*|'else '*|'elif '*|'do '*|'while '*|'until '*|'time '*|'builtin '*|'command '*) seg="${seg#* }" ;;
        *) break ;;
      esac
    done
    case "$seg" in 'esac'|'esac '*|'esac)'*|'esac}'*) [ "${#case_depth[@]}" -eq 0 ] || unset 'case_depth[${#case_depth[@]}-1]' ;; esac
    # A pipeline component or a background job runs in a subshell, so its cd and export reach no later segment; a `|` before a case arm is its pattern's.
    piped=""
    case "$op_before" in '|'|'|&') [ -n "$arm" ] || piped=1 ;; esac
    case "${_SCOPED_TYPES[i+1]:-}:${_SCOPED_VALUES[i+1]:-}" in 'O:|'|'O:|&'|'O:&') piped=1 ;; esac
    # Only an unbalanced, unescaped `)` closes a subshell; the pair in `$((1+1))` and `echo \(` close nothing.
    bare=${seg//\\?/}
    case "$bare" in *[\"\']*) bare=$(printf '%s' "$bare" | perl -pe 's/"[^"]*"|\x27[^\x27]*\x27//g') ;; esac
    opens=${bare//[!(]/}
    closes=${bare//[!)]/}
    pops=$((${#closes} - ${#opens}))
    [ "$pops" -gt 0 ] || pops=0
    for ((arm = 0; arm < pops; arm++)); do seg="${seg%')'*}${seg##*')'}"; done
    while :; do
      case "$seg" in
        # A group's closing brace is a word of its own; a glued one is data, as in `xargs -I{}`.
        *' '|*' }'|'}') seg="${seg%?}" ;;
        *) break ;;
      esac
    done
    _SEG_DIRS[i]="$cwd"
    _SEG_TEXT[i]="$seg"
    case "$seg" in done|'done '*|'done)'*|'done}'*) loops=${loops%:*} ;; esac
    # An exported GIT_DIR moves every later git command; a bare assignment reaches git only if it was exported earlier.
    if [ -n "$piped" ]; then :
    elif [[ $seg =~ $GITDIR_EXPORT_RE ]]; then
      gitenv=${seg##* GIT_DIR}
      case "$gitenv" in =*) gitenv=${gitenv#=}; gitenv=${gitenv%% *} ;; *) gitenv='?' ;; esac
      # The substitution runs at the export, so its directory is this one, not the later git's.
      case "$(unquote "$gitenv")" in "$TOPLEVEL_MARK"*) gitenv=$(join_dir "$cwd" "$gitenv") ;; esac
    elif [[ $seg =~ $GITDIR_ASSIGN_RE ]]; then gitenv='?'
    elif [[ $seg =~ $GITDIR_UNSET_RE ]]; then gitenv=""
    fi
    # eval runs its string in this shell, so a cd or GIT_DIR in it moves later segments somewhere the text cannot follow.
    case "$seg" in eval\ *) case "$seg" in *cd*|*pushd*|*popd*) cwd='?' ;; esac; case "$seg" in *GIT_DIR*) gitenv='?' ;; esac ;; esac
    if [[ $seg =~ $BRANCH_MOVE_RE ]]; then record_branch "$i" "$seg" "$cwd" "${_SEG_GITENV[i]}"; fi
    [ -z "$neg" ] || chain=$((chain + 1))
    [ -z "$piped" ] || seg=""
    case "$seg" in
      cd) cwd="$HOME" ;;
      pushd|popd|popd\ *|pushd\ [+-][0-9]*) cwd='?' ;;
      pushd\ -n|pushd\ -n\ *) ;;
      cd\ *|pushd\ *)
        op=$(printf '%s' "$seg" | awk '{ i = 2; while (i <= NF && $i ~ /^-[LPe@]+$/) i++; if ($i == "--") i++; print $i }')
        # With options and no operand, `cd` goes home and `pushd` rotates the stack.
        if [ -n "$op" ]; then cwd=$(join_dir "$cwd" "$op")
        elif [ "${seg%% *}" = cd ]; then cwd="$HOME"
        else cwd='?'; fi ;;
    esac
    while [ "$pops" -gt 0 ] && [ "${#stack[@]}" -gt 0 ]; do
      cwd="${stack[${#stack[@]}-1]}"
      unset 'stack[${#stack[@]}-1]'
      gitenv="${envstack[${#envstack[@]}-1]}"
      unset 'envstack[${#envstack[@]}-1]'
      pops=$((pops - 1))
    done
  done
}

# The directory a git segment acts on: each `-C` before the verb resolves against the one before it.
segment_git_dir() { # segment, directory it runs in, verb pattern, GIT_DIR exported before it
  local dir=$2 c head named=""
  head=$(printf '%s' "$1" | sed -E "s/[[:space:]]($3)([[:space:]].*)?\$//")
  while IFS= read -r c; do
    # A substitution runs in the shell's directory, not in the -C chain before it.
    case "$(unquote "$c")" in '') ;; "$TOPLEVEL_MARK"*) dir=$(join_dir "$2" "$c") ;; *) dir=$(join_dir "$dir" "$c") ;; esac
  done <<EOF
$(printf '%s' "$head" | grep -oE '(^|[[:space:]])-C +[^[:space:]]+' | sed -E 's/^[[:space:]]*-C +//')
EOF
  # --git-dir and GIT_DIR= name the repository itself, past any -C; --work-tree leaves it where it was.
  c=$(printf '%s' " $head" | grep -oE '[[:space:]](--git-dir|GIT_DIR)(=| +)[^[:space:]]+' | tail -1 | sed -E 's/^[[:space:]]*[^= ]+(=| +)//')
  # The segment's own toplevel substitution runs in the shell's directory, past any -C, like the -C values above.
  case "$(unquote "$c")" in "$TOPLEVEL_MARK"*) dir=$2 ;; esac
  # Without its own, an invocation takes the exported GIT_DIR, resolved where it runs as git resolves a relative one.
  [ -n "$c" ] || c=${4:-}
  case "$c" in '') ;; '?') dir='?' ;; *) dir=$(join_dir "$dir" "$c"); named=1 ;; esac
  # A linked worktree's .git is a file at its top; a named repository that is not there cannot be read.
  if [ -n "$named" ] && [ "$dir" != '?' ]; then
    if [ -f "$dir" ]; then dir=$(dirname "$dir"); elif [ ! -d "$dir" ]; then dir='?'; fi
  fi
  printf '%s' "$dir"
}

# git accepts any unique prefix of a long option, and an ambiguous one is an error, so the first option it prefixes is safe.
expand_push_option() { # --name[=value]
  local name=${1%%=*} rest="" o
  case "$1" in *=*) rest="=${1#*=}" ;; esac
  for o in all branches mirror tags delete force force-with-lease repo push-option receive-pack exec recurse-submodules; do
    [ "--$o" = "$name" ] && { printf '%s' "$1"; return; }
  done
  for o in all branches mirror tags delete force-with-lease force repo push-option receive-pack exec recurse-submodules; do
    case "--$o" in "$name"*) printf '%s' "--$o$rest"; return ;; esac
  done
  printf '%s' "$1"
}

# A worktree's own git dir, physical, so its work tree, its .git and a --git-dir spelling compare equal; a path not created yet is itself.
repo_key() {
  local top
  [ "$1" = '?' ] && { printf '?'; return; }
  if top=$(git -C "${1:-.}" rev-parse --absolute-git-dir 2>/dev/null) && [ -n "$top" ]; then
    (cd "$top" 2>/dev/null && pwd -P) || printf '%s' "$top"
  else
    printf '%s' "${1:-.}"
  fi
}

# The branch a checkout, switch, rename, symbolic-ref or rebase leaves checked out: a name, `?` when the text cannot tell, nothing when unchanged.
branch_after() { # directory, subcommand, its words...
  local dir=$1 sub=$2 w new="" move="" track="" pos=() ends=""
  shift 2
  while [ $# -gt 0 ]; do
    w=$(unquote "$1"); shift
    if [ -n "$ends" ]; then pos[${#pos[@]}]=$w; continue; fi
    # parse-options takes a short option's value glued and a long one's after `=`.
    case "$sub:$w" in checkout:-[!-bB]*[bB]|switch:-[!-cC]*[cC]) w=-${w#"${w%?}"} ;; esac
    case "$sub:$w" in
      checkout:-[bB]?*|switch:-[cC]?*) set -- "${w#-?}" "$@"; w=${w%"${w#-?}"} ;;
      switch:--create=*|switch:--force-create=*|checkout:--orphan=*|switch:--orphan=*) set -- "${w#*=}" "$@"; w=${w%%=*} ;;
    esac
    case "$sub:$w" in
      checkout:-b|checkout:-B|checkout:--orphan|switch:-c|switch:-C|switch:--create|switch:--force-create|switch:--orphan)
        new=$(unquote "${1:-?}"); [ $# -eq 0 ] || shift ;;
      checkout:--detach|switch:--detach|switch:-d|*:-) printf '?'; return ;;
      # Paths after `--`, from a file or picked by hand restore files and leave HEAD where it was.
      checkout:--) [ $# -eq 0 ] || return 0; break ;;
      checkout:--pathspec-from-file*|checkout:-p|checkout:--patch) return 0 ;;
      checkout:-t|checkout:--track|checkout:--track=*|switch:-t|switch:--track|switch:--track=*) track=1 ;;
      branch:-m|branch:-M|branch:--move) move=1 ;;
      rebase:--onto|rebase:-s|rebase:--strategy|rebase:-X|rebase:--strategy-option|rebase:-x|rebase:--exec) [ $# -eq 0 ] || shift ;;
      symbolic-ref:-m) [ $# -eq 0 ] || shift ;;
      *:--) ends=1 ;;
      *:-*) ;;
      *) pos[${#pos[@]}]=$w ;;
    esac
  done
  case "$sub" in
    branch)
      [ -n "$move" ] || return 0
      case "${#pos[@]}:${pos[1]:-}" in 1:) new=${pos[0]} ;; 2:main|2:master) new='?' ;; *) return 0 ;; esac ;;
    symbolic-ref)
      [ "${#pos[@]}" -eq 2 ] && [ "${pos[0]}" = HEAD ] || return 0
      new=${pos[1]#refs/heads/} ;;
    rebase)
      # `git rebase <upstream> <branch>` switches to <branch> first.
      [ "${#pos[@]}" -eq 2 ] || return 0
      new=${pos[1]} ;;
    *)
      if [ -z "$new" ]; then
        # A ref followed by paths, or a name that is no local branch (a file, a commit), leaves HEAD where it was.
        [ "${#pos[@]}" -eq 1 ] || return 0
        case "${pos[0]}" in
          # A target the text cannot read may name main.
          *SUBSTITUTION*|*TOPLEVEL*|*QUOTED_ARG*|*'$'*|*'`'*|'@{'*) printf '?'; return ;;
          main|master) new=${pos[0]} ;;
          # --track creates the branch named by the part after the remote.
          */*) [ -z "$track" ] || new=${pos[0]#*/} ;;
        esac
        if [ -z "$new" ]; then
          [ "$dir" != '?' ] && git -C "${dir:-.}" rev-parse --verify --quiet "refs/heads/${pos[0]}" >/dev/null 2>&1 \
            && new=${pos[0]}
          # A branch an earlier move in this command creates exists by the time this one runs.
          case " ${_BR_NAME[*]:-} " in *" ${pos[0]} "*) new=${pos[0]} ;; esac
        fi
      fi ;;
  esac
  case "$new" in *SUBSTITUTION*|*TOPLEVEL*|*QUOTED_ARG*|*'$'*|*'`'*) new='?' ;; esac
  printf '%s' "$new"
}

# A new worktree's path and branch: -b's name, a branch given as its commit-ish, or the path's last part when none is.
worktree_after() { # directory, words after `add`...
  local base=$1 w new="" detach="" pos=()
  shift
  while [ $# -gt 0 ]; do
    w=$(unquote "$1"); shift
    case "$w" in -[bB]?*) set -- "${w#-?}" "$@"; w=${w%"${w#-?}"} ;; esac
    case "$w" in
      -b|-B) new=$(unquote "${1:-?}"); [ $# -eq 0 ] || shift ;;
      --reason) [ $# -eq 0 ] || shift ;;
      --detach|-d) detach=1 ;;
      -*) ;;
      *) pos[${#pos[@]}]=$w ;;
    esac
  done
  [ "${#pos[@]}" -gt 0 ] || return 0
  if [ -n "$detach" ]; then new='?'
  elif [ -z "$new" ]; then
    case "${pos[1]:-}" in
      '') new=${pos[0]##*/} ;;
      main|master) new=${pos[1]} ;;
      *) new='?'
         [ "$base" != '?' ] && git -C "${base:-.}" rev-parse --verify --quiet "refs/heads/${pos[1]}" >/dev/null 2>&1 \
           && new=${pos[1]} ;;
    esac
  fi
  case "$new" in *SUBSTITUTION*|*TOPLEVEL*|*QUOTED_ARG*|*'$'*|*'`'*) new='?' ;; esac
  printf '%s\t%s' "$(join_dir "$base" "${pos[0]}")" "$new"
}

record_branch() { # segment index, its text, directory it runs in, GIT_DIR exported before it
  local words w=() dir key name rec
  words=$(git_sub_args "$2" "$BRANCH_MOVE_VERBS" keep)
  [ -n "$words" ] || return 0
  read -r -a w <<<"$words"
  dir=$(segment_git_dir "$2" "$3" "${w[0]}" "$4")
  if [ "${w[0]}" = worktree ]; then
    [ "${w[1]:-}" = add ] || return 0
    rec=$(worktree_after "$dir" "${w[@]:2}")
    [ -n "$rec" ] || return 0
    key=$(repo_key "${rec%%$'\t'*}")
    name=${rec#*$'\t'}
  else
    name=$(branch_after "$dir" "${w[@]}")
    key=$(repo_key "$dir")
  fi
  [ -n "$name" ] || return 0
  _BR_AT[${#_BR_AT[@]}]=$1
  _BR_KEY[${#_BR_KEY[@]}]=$key
  _BR_NAME[${#_BR_NAME[@]}]=$name
}

UNRESOLVED_PUSH="git push with no branch named, from a directory, repository or branch this guard cannot resolve (a variable, a substitution, a quoted or escaped path, an exported GIT_DIR, a shell string such as bash -c or eval, a checkout or worktree the command itself makes) — name it: git push origin <branch>."

# Prints why a push segment lands on main or master and succeeds; quiet and false for any other push.
push_hits_main() { # segment, directory it acts on, its segment index (none inside a shell string), xargs replace string
  local toks tok raw skip="" remote="" force="" tags="" refs=() ref dst branch k key cands=() id
  read -r -a toks <<<"$(push_args "$1")"
  for tok in "${toks[@]}"; do
    [ -z "$skip" ] || { skip=""; continue; }
    raw=$tok
    tok=$(unquote "$tok")
    case "$tok" in --?*) tok=$(expand_push_option "$tok") ;; esac
    case "$tok" in
      -o|--push-option|--repo|--receive-pack|--exec|--recurse-submodules) skip=1 ;;
      --all|--mirror|--branches)
        printf '%s' "git push $tok — pushes every local branch, main included. Push the branch you mean by name."
        return 0 ;;
      --tags) tags=1 ;;
      --force|--force=*|--force-with-lease|--force-with-lease=*) force=1 ;;
      --*) ;;
      # In a bundle, the first `o` takes the rest of the word as its value, or the next word when it comes last.
      -[!-]*o*) case "${tok#*o}" in '') skip=1 ;; esac; case "${tok%%o*}" in *f*) force=1 ;; esac ;;
      -*f*) force=1 ;;
      -*) ;;
      # An unquoted substitution can expand to no word at all, so the word after it may be the remote and the push bare.
      *) if [ -z "$remote" ]; then remote=$tok; [ "$raw" != SUBSTITUTION ] || refs[${#refs[@]}]=HEAD
         else refs[${#refs[@]}]="$tok"; fi ;;
    esac
  done
  # `--tags` alone pushes tags only, so no branch is defaulted in.
  [ "${#refs[@]}" -gt 0 ] || [ -n "$tags" ] || refs=(HEAD)
  for ref in "${refs[@]}"; do
    case "$ref" in :|+:) printf '%s' "git push $ref — the matching refspec pushes every branch that exists on both sides, main included. Push the branch you mean by name."; return 0 ;; esac
    case "$ref" in +*) force=1; ref=${ref#+} ;; esac
    dst=${ref##*:}
    # see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — an unreadable destination is the checked-out branch
    case "$dst" in *SUBSTITUTION*|*TOPLEVEL*|*QUOTED_ARG*|*'$'*|*'`'*) dst=HEAD ;; esac
    # xargs fills its replace string from stdin, so a destination built from it is as unreadable.
    case "${4:-}" in ?*) case "$dst" in *"$4"*) dst=HEAD ;; esac ;; esac
    cands=("$dst")
    if [ "$dst" = HEAD ] || [ "$dst" = @ ]; then
      [ "$2" != "?" ] || { printf '%s' "$UNRESOLVED_PUSH"; return 0; }
      # see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — the branches a bare push may send
      cands=()
      branch=""
      if [ "${#_BR_AT[@]}" -gt 0 ] && [ -n "${3:-}" ]; then
        key=$(repo_key "$2")
        for ((k = 0; k < ${#_BR_AT[@]}; k++)); do
          [ "${_BR_KEY[k]}" = "$key" ] || [ "${_BR_KEY[k]}" = '?' ] || continue
          for id in ${_SEG_LOOP[$3]//:/ }; do
            case "${_SEG_LOOP[${_BR_AT[k]}]}" in *":$id:"*) printf '%s' "$UNRESOLVED_PUSH"; return 0 ;; esac
          done
        done
        for ((k = ${#_BR_AT[@]} - 1; k >= 0; k--)); do
          [ "${_BR_AT[k]}" -lt "$3" ] || continue
          case "${_BR_KEY[k]}" in '?') printf '%s' "$UNRESOLVED_PUSH"; return 0 ;; "$key") ;; *) continue ;; esac
          cands[${#cands[@]}]=${_BR_NAME[k]}
          [ "${_SEG_CHAIN[${_BR_AT[k]}]}" != "${_SEG_CHAIN[$3]}" ] || { branch=found; break; }
        done
      fi
      if [ -z "$branch" ]; then
        # A missing directory was made by the command (a clone, a worktree), so what it checks out is unknown.
        if [ -n "$2" ]; then
          if git -C "$2" rev-parse --git-dir >/dev/null 2>&1; then
            branch=$(git -C "$2" branch --show-current 2>/dev/null)
          elif [ ! -e "$2" ]; then
            printf '%s' "$UNRESOLVED_PUSH"
            return 0
          fi
        fi
        [ -n "$branch" ] || branch=$(git branch --show-current 2>/dev/null)
        cands[${#cands[@]}]=$branch
      fi
    fi
    for dst in "${cands[@]}"; do
      [ "$dst" != "?" ] || { printf '%s' "$UNRESOLVED_PUSH"; return 0; }
      case "$dst" in *'*'*) dst=main ;; esac
      if printf '%s' "$dst" | grep -qE '(^|/)(main|master)$'; then
        if [ -n "$force" ]; then
          printf '%s' "git push --force to main — rewrites shared history on the default branch."
        else
          printf '%s' "git push on main — changes must go through a PR. Create a branch first."
        fi
        return 0
      fi
    done
  done
  return 1
}

# True only for `git [-C <dir>] push origin <branch> --force-with-lease=<branch>:<sha>` typed as one simple command,
# where every commit the lease replaces is the user's own and every open PR from the branch is theirs.
# see: tools/claude/examples/hooks/destructive-guard/README.md § Own-PR lease
own_pr_lease() {
  local toks tok lease="" pos=() ref sha dir=. base me authors url repo author self
  [ "${PR_AUTHOR_LOOKUP:-1}" = "1" ] || return 1
  # No separator, redirect, subshell, expansion, quote, escape or glob: nothing can carry a second push or refspec.
  case "$CMD" in *[\;\&\|\<\>\(\)\{\}\`\$\\\"\'\*\?\[\#]*|*$'\n'*) return 1 ;; esac
  printf '%s' "$CMD" | grep -qE '^git( -C [^ ]+)? push( |$)' || return 1
  case "$CMD" in "git -C "*) dir=$(expand_path "$(printf '%s' "$CMD" | awk '{ print $3 }')") ;; esac
  read -r -a toks <<<"${CMD#* push}"
  for tok in "${toks[@]}"; do
    case "$tok" in
      --force-with-lease=*:*) [ -z "$lease" ] || return 1; lease=${tok#--force-with-lease=} ;;
      -u|--set-upstream|--force-if-includes|-q|--quiet|-v|--verbose) ;;
      -*) return 1 ;;
      *) pos[${#pos[@]}]="$tok" ;;
    esac
  done
  [ "${#pos[@]}" -eq 2 ] && [ "${pos[0]}" = "origin" ] || return 1
  ref=${pos[1]}
  case "$ref" in ''|*:*|+*|main|master|HEAD|refs/*) return 1 ;; esac
  [ "${lease%%:*}" = "$ref" ] || return 1
  sha=${lease#*:}
  printf '%s' "$sha" | grep -qE '^[0-9a-f]{7,40}$' || return 1
  git -C "$dir" cat-file -e "${sha}^{commit}" 2>/dev/null || return 1
  base=$(git -C "$dir" merge-base "$sha" refs/remotes/origin/main 2>/dev/null \
         || git -C "$dir" merge-base "$sha" refs/remotes/origin/master 2>/dev/null)
  me=$(git -C "$dir" config user.email)
  [ -n "$base" ] && [ -n "$me" ] || return 1
  # The lease overwrites exactly $sha, so a commit on it past the default branch by anyone else is their work lost.
  authors=$(git -C "$dir" log --format='%ae' "${base}..${sha}" 2>/dev/null) || return 1
  ! printf '%s' "$authors" | grep -q -v -x -F "$me" || return 1
  # The push URL, not the fetch URL: a pushurl or pushInsteadOf sends the push to a repository get-url alone never names.
  url=$(git -C "$dir" remote get-url --push origin 2>/dev/null)
  repo=$(printf '%s' "$url" | sed -nE 's#^(https://|ssh://git@|git@)github\.com[:/]([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/?$#\2#p')
  repo=${repo%.git}
  printf '%s' "$repo" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  [ -r "$(dirname "$0")/../_lib/pr-author.sh" ] || return 1
  # shellcheck source=/dev/null  # gh_bounded and pr_self_login, cached; loaded only for this rare push shape
  source "$(dirname "$0")/../_lib/pr-author.sh"
  # A fork's PR from a same-named branch is not this branch's PR, so only same-repository PRs count.
  author=$(gh_bounded pr list --repo "$repo" --head "$ref" --state open --json author,isCrossRepository \
    --jq '[.[] | select(.isCrossRepository | not) | .author.login] | unique | if length == 1 then .[0] else empty end' 2>/dev/null)
  self=$(pr_self_login)
  [ -n "$author" ] && [ -n "$self" ] && [ "$author" = "$self" ]
}

# Newlines flattened: every pattern below is line-scoped, so a construct split across lines matched nothing.
CMD_FLAT=$(printf '%s' "$CMD_STRIPPED" | tr '\n' ';')
# The matching twin, so a loop or `cd` quoted inside an echo is prose rather than a construct.
CMD_FLAT_MATCH=$(printf '%s' "$CMD_MATCH" | tr '\n' ';')

SPLIT_SEGMENTS="$(dirname "$0")/../_lib/split-cmd-segments.pl"

# see: README.md § Parser hardening — loaded once into an array; three callers meant three perl forks
_SEGS_LOADED=""
_SEGS=()
load_segments() {
  [ -n "$_SEGS_LOADED" ] && return 0
  _SEGS_LOADED=1
  if [ -r "$SPLIT_SEGMENTS" ]; then
    local seg
    while IFS= read -r -d '' seg; do _SEGS[${#_SEGS[@]}]="$seg"; done \
      < <(printf '%s' "$CMD_MATCH" | perl "$SPLIT_SEGMENTS")
  else
    # Degrading to whole-command matching is correct, but silent degradation is not observable.
    _SEGS[0]="$CMD_MATCH"
    hook_diag_event SPLITTER_MISSING "$SPLIT_SEGMENTS"
  fi
}

_SCOPED_LOADED=""
_SCOPED_OK=""
_SCOPED_TYPES=()
_SCOPED_VALUES=()
load_scoped_segments() {
  if [ -n "$_SCOPED_LOADED" ]; then
    [ "$_SCOPED_OK" = 1 ]
    return
  fi
  _SCOPED_LOADED=1
  [ -r "$SPLIT_SEGMENTS" ] || return 1
  local type value ended="" invalid="" depth=0
  while IFS= read -r -d '' type; do
    [ -z "$ended" ] || { invalid=1; break; }
    case "$type" in
      S|O)
        IFS= read -r -d '' value || { invalid=1; break; }
        _SCOPED_TYPES[${#_SCOPED_TYPES[@]}]="$type"
        _SCOPED_VALUES[${#_SCOPED_VALUES[@]}]="$value"
        ;;
      E)
        depth=$((depth + 1))
        _SCOPED_TYPES[${#_SCOPED_TYPES[@]}]="E"
        _SCOPED_VALUES[${#_SCOPED_VALUES[@]}]=""
        ;;
      X)
        [ "$depth" -gt 0 ] || { invalid=1; break; }
        depth=$((depth - 1))
        _SCOPED_TYPES[${#_SCOPED_TYPES[@]}]="X"
        _SCOPED_VALUES[${#_SCOPED_VALUES[@]}]=""
        ;;
      Z) ended=1 ;;
      *) invalid=1; break ;;
    esac
  done < <(printf '%s' "$CMD_MATCH" | perl "$SPLIT_SEGMENTS" --scoped)
  [ -n "$ended" ] && [ -z "$invalid" ] && [ "$depth" -eq 0 ] || return 1
  _SCOPED_OK=1
}

# seg_matches <negative> <required>... — true when ONE segment matches every <required> and not <negative>.
# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — why a whole-command negative test is disarmable
seg_matches() {
  local negative="$1" seg pat ok
  shift
  load_segments
  for seg in "${_SEGS[@]}"; do
    ok=1
    for pat in "$@"; do
      printf '%s' "$seg" | grep -qE "$pat" || { ok=0; break; }
    done
    [ "$ok" = 1 ] || continue
    if [ -n "$negative" ] && printf '%s' "$seg" | grep -qE "$negative"; then
      continue
    fi
    return 0
  done
  return 1
}

# see: README.md § Cost per call — every rule keys on one of these; check-guard-gate.py fails CI if one is missing
GUARD_TOOLS='git|gh|aws|kubectl|helm|terraform|xargs'
if ! echo "$CMD_MATCH" | grep -qE "(^|[^[:alnum:]_.-])(${GUARD_TOOLS})([[:space:]]|$)"; then
  exit 0
fi

HARD_REASON=""
SOFT_REASON=""

# see: README.md § Reporting every trigger — last-writer-wins hid the graver of two soft triggers
add_soft() {
  case "$SOFT_REASON" in
    *"$1"*) return 0 ;;
  esac
  if [ -z "$SOFT_REASON" ]; then
    SOFT_REASON="$1"
  else
    SOFT_REASON="${SOFT_REASON}
ALSO: $1"
  fi
}

# =====================================================================
# HARD BLOCKS — irreversible data loss or forbidden shared-state ops, exit 2
# =====================================================================

# git push landing on main/master (bypass PR process). Plain pushes and force
# pushes are both checked: force-push to main/master hard-blocks with its own
# message; force-push to other refs falls through to the soft tier below.
# Pattern allows flags between `git` and `push` (e.g., `git -C dir push`).
PUSH_VIEW=$(strip_redirs "$CMD_MATCH" | sed 's/[;&|]/ & /g')
# A quote can end the verb and git still reads push: `bash -c 'git push"" origin main'`.
PUSH_GATE_RE="${GIT_SUB_RE}push([\"'[:space:]]|\$)"
# True when no push in the segment survives removing its quoted strings: it runs inside bash -c, eval or ssh.
push_in_shell_string() {
  ! printf '%s' "$1" | perl -pe 's/"(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27/ Q /g' | grep -qE "${GIT_SUB_RE}push([[:space:]]|\$)"
}
# The commands in each quoted string of a segment, one per line, one level of escapes decoded: bash -c and eval run them.
shell_string_cmds() {
  printf '%s' "$1" | perl -0777 -ne 'while (/"((?:[^"\\]|\\.)*)"|\x27([^\x27]*)\x27/gs) { my ($d, $s) = ($1, $2); $s = $d =~ s/\\(["\\\$`])/$1/gr if defined $d; $s =~ s/\\\n//g; print "$_\n" for split /&&|\|\||[;&|\n]/, $s }'
}
# A refspec read from stdin, or a refspec or mode set through config, decides what a bare push sends, so it must name its branch.
push_config_unreadable() { # segment
  local seg v
  seg=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$seg" in
    *xargs\ *git*|*' -c 'remote.*.push=*|*' -c 'remote.*.mirror=*|*--config-env*|*git_config_count=*|*git_config_parameters=*) return 0 ;;
  esac
  # Only these three modes push the current branch to itself; any other sends what the config says.
  for v in $(printf '%s' "$seg" | grep -oE ' -c push\.default=[^[:space:]]*' | sed 's/.*=//'); do
    case "$v" in simple|current|nothing) ;; *) return 0 ;; esac
  done
  return 1
}
# The replace string an xargs before git fills from stdin: -I/-J take one, -i and --replace default to {}.
xargs_replace() { # segment
  printf '%s' "$1" | awk '{
    for (i = 1; i <= NF && $i !~ /(^|\/)git$/; i++) {
      if ($i ~ /(^|\/)xargs$/) x = 1
      if (!x) continue
      if ($i == "-I" || $i == "-J") { print $(i + 1); exit }
      if ($i ~ /^-[IJ]./) { print substr($i, 3); exit }
      if ($i ~ /^-i./) { print substr($i, 3); exit }
      if ($i ~ /^--replace=/) { print substr($i, 11); exit }
      if ($i == "-i" || $i == "--replace") { print "{}"; exit }
    }
  }'
}
# Continuations joined first: `git \<newline> push` is one command to the shell that runs it.
if printf '%s' "$PUSH_VIEW" | perl -0777 -pe 's/\\\n//g' | grep -qE 'git[[:space:]]([^|;&]* )?push(["'"'"'\\[:space:];&|)]|$)'; then
  if ! load_scoped_segments; then
    HARD_REASON="destructive-guard: scoped command parser failed while checking a push."
  else
    # Per segment, in the directory that segment runs in: an earlier bare `push` — in an echo, a grep, a
    # message — must not capture the check, and a bare push's branch is the one where it runs.
    resolve_segment_dirs
    for ((PUSH_INDEX = 0; PUSH_INDEX < ${#_SCOPED_TYPES[@]}; PUSH_INDEX++)); do
      [ "${_SCOPED_TYPES[$PUSH_INDEX]}" = S ] || continue
      PUSH_SEGMENT=$(strip_redirs "${_SEG_TEXT[$PUSH_INDEX]}")
      # An escaped quote in a shell string hides its push from the raw gate, so a quoted segment goes to the pieces anyway.
      if echo "$PUSH_SEGMENT" | grep -qE "$PUSH_GATE_RE"; then
        PUSH_DIR=$(segment_git_dir "$PUSH_SEGMENT" "${_SEG_DIRS[$PUSH_INDEX]}" push "${_SEG_GITENV[$PUSH_INDEX]}")
        push_in_shell_string "$PUSH_SEGMENT" && PUSH_DIR='?'
        push_config_unreadable "$PUSH_SEGMENT" && PUSH_DIR='?'
        if PUSH_HIT=$(push_hits_main "$PUSH_SEGMENT" "$PUSH_DIR" "$PUSH_INDEX" "$(xargs_replace "$PUSH_SEGMENT")"); then
          HARD_REASON=$PUSH_HIT
          break
        fi
      fi
      # Every command in a shell string is checked, not only the first push, in a directory the text cannot name.
      case "$PUSH_SEGMENT" in *[\"\']*)
        while IFS= read -r PUSH_PIECE; do
          printf '%s' "$PUSH_PIECE" | grep -qE "$PUSH_GATE_RE" || continue
          if PUSH_HIT=$(push_hits_main "$PUSH_PIECE" '?' "" "$(xargs_replace "$PUSH_PIECE")"); then HARD_REASON=$PUSH_HIT; break; fi
        done < <(shell_string_cmds "$PUSH_SEGMENT")
        [ -z "$HARD_REASON" ] || break ;;
      esac
    done
  fi
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § Why `--dry-run` is not exempt — an exemption is satisfiable by an earlier segment
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?clean[^|;&]*[[:space:]](--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|=|$)'; then
  HARD_REASON="git clean -f/--force — permanently deletes untracked files."
fi

# git stash drop/clear (permanent loss of stashed work)
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?stash +(drop|clear)'; then
  HARD_REASON="git stash drop/clear — permanently discards stashed changes."
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § Bulk branch deletion — why blast radius, not the delete, makes these hard
BULK_BRANCH_MSG="bulk branch deletion is a hard block in BOTH the -d and -D forms — retrying with -d will not pass. Delete one branch at a time, confirming each with the user, or have the user run the bulk command themselves."
if echo "$CMD_FLAT_MATCH" | grep -qE 'xargs[^|;&]*git[[:space:]]([^|;&]* )?branch +-[Dd]'; then
  HARD_REASON="xargs git branch -d/-D — ${BULK_BRANCH_MSG}"
fi

# The body between `do` and `done` is extracted, not matched across: a multi-line body puts arbitrarily many separators in the way, and `done && git branch -d x` is not a bulk delete.
if echo "$CMD_FLAT_MATCH" | grep -qE '(for[[:space:]]|while[[:space:]])'; then
  # Non-greedy and repeated: a greedy match anchors on the LAST `do`, so a second loop disarmed this.
  LOOP_BODY=$(printf '%s' "$CMD_FLAT_MATCH" \
    | perl -0777 -ne 'while (/\sdo[\s;&]+(.*?)[\s;&]done/gs) { print "$1\n" }')
  if printf '%s' "$LOOP_BODY" | grep -qE 'git[[:space:]]([^|;&]* )?branch +-[Dd]'; then
    HARD_REASON="for/while loop with git branch -d/-D — ${BULK_BRANCH_MSG}"
  fi
fi

# `(-- +)?` because `git branch -D -- a b` is the same bulk delete with an end-of-options marker.
if echo "$CMD_FLAT_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?branch +-[Dd] +(-- +)?[^ |;&<>-][^ |;&<>]* +[^ |;&<>-][^ |;&<>]*([[:space:]]|;|$)'; then
  HARD_REASON="git branch -d/-D with multiple branches in one command — ${BULK_BRANCH_MSG}"
fi

# AWS resource deletion. Pattern allows flags between `aws` and the service
# (e.g., `aws --profile prod s3 rm`).
if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?sqs +purge-queue([[:space:]]|$)'; then
  HARD_REASON="aws sqs purge-queue — permanently deletes all messages."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?sqs +delete-(queue|message)([[:space:]]|$)'; then
  HARD_REASON="aws sqs delete — permanently removes queue or messages."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?s3 +r(m|b)([[:space:]]|$)'; then
  HARD_REASON="aws s3 rm/rb — permanently deletes S3 objects or buckets."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?secretsmanager +delete-secret([[:space:]]|$)'; then
  HARD_REASON="aws secretsmanager delete-secret — permanently removes a secret."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?sns +delete-topic([[:space:]]|$)'; then
  HARD_REASON="aws sns delete-topic — permanently removes an SNS topic and all subscriptions."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?ecr +batch-delete-image([[:space:]]|$)'; then
  HARD_REASON="aws ecr batch-delete-image — permanently removes container images."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?rds +delete-db'; then
  HARD_REASON="aws rds delete — permanently removes a database instance or cluster."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?ec2 +terminate-instances([[:space:]]|$)'; then
  HARD_REASON="aws ec2 terminate-instances — permanently destroys EC2 instances."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?lambda +delete-function([[:space:]]|$)'; then
  HARD_REASON="aws lambda delete-function — permanently removes a Lambda function."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?iam +delete-(role|policy|user|group)([[:space:]]|$)'; then
  HARD_REASON="aws iam delete — permanently removes IAM resources."
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § AWS coverage — why this list is short and the soft catch-all does the rest
AWS_CATASTROPHIC='dynamodb +delete-(table|backup)'\
'|kms +schedule-key-deletion'\
'|s3api +delete-(object|objects|bucket)'\
'|eks +delete-(cluster|nodegroup|fargate-profile)'\
'|cloudformation +delete-stack'\
'|logs +delete-log-(group|stream)'\
'|ec2 +delete-(volume|snapshot)'\
'|efs +delete-file-system'\
'|elasticache +delete-(cache-cluster|replication-group)'\
'|redshift +delete-cluster'\
'|backup +delete-(recovery-point|backup-vault)'
if echo "$CMD_MATCH" | grep -qE "aws[[:space:]]([^|;&]* )?(${AWS_CATASTROPHIC})([[:space:]]|\$)"; then
  HARD_REASON="aws — irreversible destruction of stored data, its backups, or the KMS key that decrypts it. No approval path: confirm profile, account and exact resource, then run it yourself."
fi

# GitHub PR close/merge — shared PR state; deliberately hard so an allow-list
# cannot auto-approve them. Pattern allows flags between `gh` and the subcommand.
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +close([[:space:]]|$)'; then
  HARD_REASON="gh pr close — STOP. Cannot close PRs without explicit user instruction. Verify: (1) Read the PR fully, (2) Check for open review threads, (3) Confirm reason with user, (4) Verify no unmerged work will be lost."
fi

# see: tools/claude/examples/hooks/merge-grant/README.md — the user's own words this turn are the only approval path
MERGE_FORMS="All four merge forms share one gate: 'gh pr merge', 'gh api .../pulls/N/merge', 'gh api graphql' mergePullRequest, 'gh stack merge'."

# Prints the prompt that armed this session's grant for one action; fails on anything short of a live grant.
grant_prompt() { # merge | pr
  local session file expires
  session=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  case "$session" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
  file="${CLAUDE_MERGE_GRANT_DIR:-$HOME/.claude/merge-grants}/${session}.json"
  [ "$1" = merge ] || file="${file%.json}.$1.json"
  [ -f "$file" ] || return 1
  expires=$(jq -r '.expires_at // 0' "$file" 2>/dev/null) || return 1
  case "$expires" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -lt "$expires" ] || return 1
  jq -r '.prompt // ""' "$file" 2>/dev/null
}

merge_gate() { # trigger, what this form lands
  local asked
  if asked=$(grant_prompt merge); then
    add_soft "$1 — the user asked for a merge this turn (\"${asked}\"). $2 Approve only if it is a PR that message names."
  else
    HARD_REASON="$1 — STOP. A merge needs the user's own words in their current message, and this turn has none, so there is no approval path. $2 Hand over the PR link instead. ${MERGE_FORMS}"
  fi
}

if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +merge([[:space:]]|$)'; then
  merge_gate "gh pr merge" "This lands one PR."
fi

# A grant never covers a merge past branch protection; the values view also sees `F=--admin; gh pr merge 1 $F`.
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +merge([[:space:]]|$)' \
   && printf '%s' "$CMD_FLAT" | grep -qE '(^|[^[:alnum:]_-])--admin([^[:alnum:]_-]|$)'; then
  HARD_REASON="gh pr merge --admin — bypasses branch protection and required checks. No approval path, grant or not: fix what blocks the merge, or the user merges it themselves."
fi

# The REST route reaches the same merge; an explicit GET is the read-only merged-status check, and the ref segment accepts a variable.
if seg_matches '(-X|--method)[[:space:]]+GET([[:space:]]|$)' \
   'gh[[:space:]]([^|;&]* )?api[^|;&]*/pulls/[^/[:space:]]+/merge(-async)?/?([^[:alnum:]/-]|$)'; then
  merge_gate "gh api .../pulls/N/merge" "The REST form of gh pr merge, async variant included."
fi

# The GraphQL route reaches the same merge; its mutation is quoted data or a heredoc body, so it is read from the raw command.
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?api[^|;&]*[[:space:]]graphql([[:space:]]|$)' \
   && printf '%s' "$CMD" | grep -qE '(^|[^[:alnum:]])(mergePullRequest|enablePullRequestAutoMerge)([^[:alnum:]]|$)'; then
  merge_gate "gh api graphql mergePullRequest" "The GraphQL form of gh pr merge, auto-merge included."
fi

# Wider than the other two: it lands the target layer plus every unmerged layer beneath it.
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?stack +merge([[:space:]]|$)'; then
  merge_gate "gh stack merge" "It lands the target layer plus EVERY unmerged layer beneath it in one operation, so each of those must be one the user named."
fi

# Branch switching outside session directory — disrupts other sessions.
# Any git checkout/switch that changes branches in a repo other than the
# session's working directory must use worktrees instead.
# see: README.md § Parser hardening — nested substitutions restore their parent's directory scope
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?(checkout|switch)([[:space:]]|$)'; then
if ! load_scoped_segments; then
  HARD_REASON="destructive-guard: scoped command parser failed while checking a branch switch."
else
resolve_segment_dirs
for ((CO_INDEX=0; CO_INDEX<${#_SCOPED_TYPES[@]}; CO_INDEX++)); do
  [ "${_SCOPED_TYPES[$CO_INDEX]}" = S ] || continue
  CO_SEG="${_SEG_TEXT[$CO_INDEX]}"
  echo "$CO_SEG" | grep -qE "${GIT_SUB_RE}(checkout|switch)([[:space:]]|\$)" || continue
  echo "$CO_SEG" | grep -qE 'git[[:space:]]([^|;&]* )?checkout +(-- |--$)' && continue

  # The -C belonging to THIS invocation, resolved against the directory its segment runs in.
  CMD_TARGET=$(segment_git_dir "$CO_SEG" "${_SEG_DIRS[$CO_INDEX]}" 'checkout|switch' "${_SEG_GITENV[$CO_INDEX]}")
  if [ -n "$CMD_TARGET" ]; then
    CMD_TARGET_ABS=$(cd "$CMD_TARGET" 2>/dev/null && pwd || echo "$CMD_TARGET")
    SESSION_CWD=$(pwd)
    # Use --git-common-dir to identify the repo — worktrees of the same repo
    # share a common git dir, so this correctly allows worktree checkouts
    SESSION_GIT=$(git -C "$SESSION_CWD" rev-parse --git-common-dir 2>/dev/null || echo "$SESSION_CWD")
    TARGET_GIT=$(git -C "$CMD_TARGET_ABS" rev-parse --git-common-dir 2>/dev/null || echo "$CMD_TARGET_ABS")
    # Physical paths: through a symlinked parent (macOS /var is /private/var) one repository read as two.
    SESSION_GIT=$(cd "$SESSION_CWD" 2>/dev/null && cd "$SESSION_GIT" 2>/dev/null && pwd -P || echo "$SESSION_GIT")
    TARGET_GIT=$(cd "$CMD_TARGET_ABS" 2>/dev/null && cd "$TARGET_GIT" 2>/dev/null && pwd -P || echo "$TARGET_GIT")
    # A non-repo target never compares equal, so without this every `cd <non-repo> && git checkout` blocked.
    if [ "$SESSION_GIT" != "$TARGET_GIT" ] && git -C "$CMD_TARGET_ABS" rev-parse --git-dir >/dev/null 2>&1; then
      SESSION_REPO=$(git -C "$SESSION_CWD" rev-parse --show-toplevel 2>/dev/null || echo "$SESSION_CWD")
      TARGET_REPO=$(git -C "$CMD_TARGET_ABS" rev-parse --show-toplevel 2>/dev/null || echo "$CMD_TARGET_ABS")
      HARD_REASON="Branch switch in ${TARGET_REPO} from a session in ${SESSION_REPO}. Use 'git -C <repo> worktree add /tmp/<name> -b <branch> main' instead — pass -C explicitly, since a preceding cd that fails silently targets the session's repo."
      break
    fi
  fi
done
fi
fi

# =====================================================================
# SOFT BLOCKS — risky but approvable, JSON permissionDecision ask + exit 0
# =====================================================================

# GitHub CLI — visible shared actions. Pattern allows flags between `gh` and
# the subcommand (e.g., `gh --repo X pr create`).
# see: tools/claude/examples/hooks/merge-grant/README.md § The pr grant — the user's words this turn are the approval this prompt would ask for again
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +create([[:space:]]|$)' \
   && ! grant_prompt pr >/dev/null; then
  add_soft "gh pr create — creating a PR is a visible shared action. Confirm with the user first."
fi

# A wider `pr create`: it creates or re-links EVERY layer of the stack in one visible action.
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?stack +(submit|link)([[:space:]]|$)'; then
  add_soft "gh stack submit/link — creates or re-links every pull request in the stack, not one PR. Confirm with the user first, and check each layer's branch name against your branch-protection rules before pushing: auto-generated layer names are often rejected."
fi

if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?stack +unstack([[:space:]]|$)'; then
  add_soft "gh stack unstack — removes the stack on GitHub, retargeting PRs other people may be reviewing. Pass --local to unlink only the local tracking."
fi

if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?run +delete([[:space:]]|$)'; then
  add_soft "gh run delete — permanently removes CI run history."
fi

# Git — history rewriting (reversible via reflog)
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?reset +--hard'; then
  add_soft "git reset --hard — discards uncommitted changes (recoverable via reflog)."
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — `[^|;&]*` confines each test to the segment its push owns
PUSH_SEG="${GIT_SUB_RE}push[^|;&]*[[:space:]]"
# The commands inside a shell string too, decoded, since `\"my dir\"` hides the push from the subcommand pattern.
PUSH_SOFT_VIEW=$PUSH_VIEW
case "$CMD_MATCH" in *push*[\"\']*|*[\"\']*push*)
  PUSH_SOFT_VIEW=$(printf '%s\n' "$PUSH_VIEW"; shell_string_cmds "$CMD_MATCH" | while IFS= read -r PUSH_PIECE; do strip_redirs "$PUSH_PIECE"; echo; done) ;;
esac

# Both spellings of one act: matching only the colon refspec left `push --delete origin br` unguarded.
# git takes a unique prefix of a long option and bundled short flags, so `--del` and `-qd` delete too.
if echo "$PUSH_SOFT_VIEW" | grep -qE "${PUSH_SEG}\\+?:" \
   || echo "$PUSH_SOFT_VIEW" | grep -qE "${PUSH_SEG}(--de(l(e(te?)?)?)?|-[a-zA-Z46]*d[a-zA-Z46]*)([[:space:])]|\$)"; then
  add_soft "git push origin :branch — deletes a remote branch, which auto-closes any PR using it. Covers both spellings: the colon refspec and --delete/-d."
fi

# `-f`, a bundled `-uf` and a `+refspec` are force-pushes too; matching only `--force` left them unguarded.
if echo "$PUSH_SOFT_VIEW" | grep -qE "${PUSH_SEG}(--force(-w[a-z-]*)?(=[^[:space:]]*)?|-[a-zA-Z46]*f[a-zA-Z46]*|\+[^[:space:]]+)([[:space:])]|\$)"; then
  own_pr_lease || add_soft "git push --force — rewrites remote history (also matches -f and +refspec). Confirm with the user first. On your own open PR, \`git push origin <branch> --force-with-lease=<branch>:<sha>\` over only your own commits runs without this prompt when it is the whole command: use \`git -C <dir> push …\`, not \`cd <dir> && git push …\`."
fi

if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?branch +-D'; then
  add_soft "git branch -D — force-deletes a branch that may have unmerged work."
fi

if seg_matches '' 'git[[:space:]]([^|;&]* )?checkout +--([[:space:]]|$)'; then
  add_soft "git checkout -- — discards uncommitted file changes."
fi

if seg_matches 'git[[:space:]]([^|;&]* )?restore +--staged' 'git[[:space:]]([^|;&]* )?restore +'; then
  add_soft "git restore — discards uncommitted file changes."
fi

# `-chdir=` sits between binary and verb, so `terraform -chdir=infra destroy` read as unrecognised.
TF_CHDIR='terraform +(-chdir=[^ ]+ +)*'
if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}destroy"; then
  add_soft "terraform destroy — destroys all resources in the workspace."
fi

# `apply -destroy` is the same operation under a different verb, and the verb is what most rules key on.
if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}apply[^|;&]*[[:space:]]-destroy([[:space:]]|$)"; then
  add_soft "terraform apply -destroy — the same whole-workspace destroy, spelled as an apply."
fi

if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}state +rm"; then
  add_soft "terraform state rm — removes resources from state, orphaning them."
fi

if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}force-unlock"; then
  add_soft "terraform force-unlock — breaks state locks that may protect concurrent operations."
fi

if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}workspace +delete"; then
  add_soft "terraform workspace delete — permanently removes a workspace and its state."
fi

# Kubectl — pattern allows flags between `kubectl` and the verb. Token group
# excludes command separators (|;&) so a downstream pipe like
# `kubectl get | grep delete` does not false-positive.
if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?delete([[:space:]]|$)'; then
  add_soft "kubectl delete — permanently removes Kubernetes resources."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?drain([[:space:]]|$)'; then
  add_soft "kubectl drain — evicts all pods from a node."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?cordon([[:space:]]|$)'; then
  add_soft "kubectl cordon — prevents new pods from scheduling on a node."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?scale([[:space:]]|$)'; then
  add_soft "kubectl scale — changes replica count, affecting live traffic."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?rollout +undo([[:space:]]|$)'; then
  add_soft "kubectl rollout undo — reverts a deployment to a previous revision."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?patch([[:space:]]|$)'; then
  add_soft "kubectl patch — mutates live Kubernetes resources."
fi

# Helm — same pattern shape as kubectl
if echo "$CMD_MATCH" | grep -qE 'helm[[:space:]]([^|;&]* )?uninstall([[:space:]]|$)'; then
  add_soft "helm uninstall — removes a Helm release and all its resources."
fi

if echo "$CMD_MATCH" | grep -qE 'helm[[:space:]]([^|;&]* )?rollback([[:space:]]|$)'; then
  add_soft "helm rollback — reverts a release to a previous revision."
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § AWS coverage — membership in the destructive-verb family, not in a hand-kept list
if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?[a-z][a-z0-9-]*[[:space:]]+(delete|remove|terminate|purge|deregister|destroy)-[a-z0-9-]+'; then
  add_soft "aws destructive verb (delete-/remove-/terminate-/purge-/deregister-/destroy-). Confirm the profile, account and exact resource before approving."
fi

# Read-only verbs are the allowlist, so a verb a future gh release adds asks instead of passing silently.
if seg_matches 'gh[[:space:]]([^|;&]* )?issue[[:space:]]+(list|view|status)([[:space:]]|$)' \
   'gh[[:space:]]([^|;&]* )?issue[[:space:]]+[a-z][a-z-]*([[:space:]]|$)'; then
  add_soft "gh issue <mutating verb> — create/comment/edit/close/reopen/delete/transfer/pin/lock all file or alter an external artifact under your GitHub identity. Only run when the user asked for it by name; producing the content is not authorisation to publish it. Read-only list/view/status are unaffected."
fi

# The REST form of the same mutation; a plain GET on /issues stays allowed, including the search endpoint.
if seg_matches '(-X|--method)[[:space:]]+GET([[:space:]]|$)|[[:space:]]search/issues' \
   'gh[[:space:]]([^|;&]* )?api[^|;&]*/issues' \
   '(-X|--method)[[:space:]]+(POST|PATCH|PUT|DELETE)|[[:space:]](-f|-F|--field|--raw-field|--input)[[:space:]]'; then
  add_soft "gh api .../issues with a mutating method or field — the REST form of gh issue create/comment/edit, subject to the same rule: only when the user asked for it by name. A read-only GET on /issues is unaffected."
fi

# =====================================================================
# Apply blocks — hard wins over soft
# =====================================================================

if [ -n "$HARD_REASON" ]; then
  echo "$HARD_REASON" >&2
  exit 2
fi

if [ -n "$SOFT_REASON" ]; then
  # Label with the trigger (the text before the em-dash) so ask volume is tunable per trigger.
  # shellcheck disable=SC2034  # read by the sourced hook-diag.sh
  HOOK_DIAG_DECISION="ask:$(printf '%s' "${SOFT_REASON%% —*}" | tr -d '\n' | cut -c1-40)"
  jq -n \
    --arg reason "$SOFT_REASON" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": $reason
      }
    }'
  exit 0
fi

exit 0
