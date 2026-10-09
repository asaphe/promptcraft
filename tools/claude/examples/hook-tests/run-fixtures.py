#!/usr/bin/env python3
r"""Assert a hook produces the expected OUTCOME for each fixture command.

Usage: run-fixtures.py <hook-name> [--hooks-dir DIR] [--cwd PATH] [--timeout S] [--fail-fast] [--jobs N]

Fixtures live in fixtures/<hook-name>.tsv as `expected <TAB> command`, with `#`
comments. Exits non-zero if any case mismatches, so it works as a pre-commit gate.

Outcome, not exit code. Exit 0 carrying an `ask` or `deny` decision on stdout is a
different result from a bare exit 0, and only exit 2 blocks. Comparing exit codes
alone scores an ask-emitting hook identically to one that allows silently, which is
how a whole tier of guards can pass their tests while delivering nothing.

Recognised outcomes:

    allow   exit 0, clean stderr, nothing on stdout the harness understands
    ctx     exit 0 carrying hookSpecificOutput.additionalContext
    defer   exit 0 carrying permissionDecision "defer"
    ask     exit 0 carrying permissionDecision "ask"
    deny    exit 0 carrying permissionDecision "deny"
    soft    exit 1  (NOT a block — Claude Code prints a notice and runs the tool)
    hard    exit 2  (the only blocking code)
    block   exit 0 carrying top-level {"decision": "block"} — a Stop hook refusing
    halt    exit 0 carrying top-level {"continue": false} — stops the whole turn
    error   exit 0 with stderr, malformed structured output, or an invalid decision
    raw     for a rewrite hook: ran, but emitted no updatedInput
    =<cmd>  for a rewrite hook: emitted exactly this rewritten command

`0`, `1` and `2` are accepted as aliases for allow / soft / hard.

`error` is the outcome that keeps the rest honest. Claude Code discards stderr at
exit 0, so a hook that fails to load — a missing helper, an unbound variable — still
exits 0 and prints its bash errors to a stream nobody reads. Without `error` that
scores `allow`; and since most cases in any guard suite are allow-cases, a hook that
never ran at all passes almost its whole suite. An unrecognised `permissionDecision`
lands here too: a renamed or typo'd verdict is a defect, never a considered allow.

`ctx` exists because a reminder-only hook emits no permissionDecision: without its
own outcome, a fired reminder and a silent pass both score `allow`, and no fixture
can tell them apart. `block` exists for the same reason on the Stop event.

File directives, each on its own line:

    #!event <name>     PreToolUse (default), PostToolUse, UserPromptSubmit, Stop
    #!tool <name>      Bash (default), Write, Edit, MultiEdit, AskUserQuestion (question, then the answer picked)
    #!escapes          column 2 honours \n, \t and \xHH
    #!setup <name>     build live state from fixture_env.py before the cases run

`#!tool` matters more than it looks: each tool carries its new content under a
different key — `content` for Write, `new_string` for Edit, `edits[].new_string`
for MultiEdit. A hook reading the wrong key sees an empty string and every fixture
passes vacuously.

`#!escapes` is opt-in per file rather than universal, because a literal backslash-n
is itself valid shell text — a perl string, a commit message — and unescaping those
would rewrite the input a case was written to assert. `\xHH` is there so a fixture
for a secret detector can contain the thing the detector detects: spelling the first
byte as hex keeps the file clean to every scanner while the harness reconstructs the
literal in memory. A fixture that dodged this by weakening its trigger would pass
while testing nothing.

`#!setup` covers hooks that resolve their verdict from something the command string
does not carry — staged git content, an `origin/main` ref, a branch. Without it they
either flap against whatever happens to be in `--cwd` that day, or return at their
first bail and pass every case without reaching a branch.

Column 2 of `<absent>` omits the tool_input field entirely. That is the third control
every guard fixture owes — block-case, allow-case, and input-unavailable — because a
guard reads its subject through one extraction, and an empty result is
indistinguishable from "nothing to guard". The fixture does not assert a universal
verdict there; it pins whichever way the hook resolves it, so a later edit cannot
flip a considered fail-open into an unconsidered one in silence.
"""

import argparse
import concurrent.futures
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fixture_env  # noqa: E402

NUMERIC_ALIAS = {"0": "allow", "1": "soft", "2": "hard"}
OUTCOMES = ("allow", "ask", "deny", "defer", "soft", "hard", "ctx", "block", "halt", "error", "TIMEOUT")
PERMISSION_DECISIONS = ("allow", "ask", "deny", "defer")
# An unsubstituted token runs the case against the harness cwd, which is what #!setup exists to prevent.
TOKEN_RE = re.compile(r"\{[a-z_][a-z0-9_]*\}")
# Each tool carries new content under a different key; a hook reads exactly one.
TOOL_INPUT = {
    "Bash": lambda path, body, prev="": {"command": path},
    "Write": lambda path, body, prev="": {"file_path": path, "content": body},
    "Edit": lambda path, body, prev="": {
        "file_path": path,
        "new_string": body,
        **({"old_string": prev} if prev else {}),
    },
    "MultiEdit": lambda path, body, prev="": {"file_path": path, "edits": [{"new_string": body}]},
    "AskUserQuestion": lambda question, answer, prev="": {"questions": [{"question": question}]},
}
# A rewrite hook emits allow either way, so outcome alone cannot see a bad rewrite.
REWRITE = "="
ABSENT = "<absent>"


def substitute(text, tokens):
    """Expand `{name}` for known tokens only — a jq filter's braces are not ours."""
    for name, value in tokens.items():
        text = text.replace("{%s}" % name, value)
    return text


def parse_expected(token, raw):
    token = token.strip()
    if token in NUMERIC_ALIAS:
        return NUMERIC_ALIAS[token]
    if token in OUTCOMES:
        return token
    if token == "raw" or token.startswith(REWRITE):
        return token
    sys.exit("unknown expected outcome %r in fixture line: %r" % (token, raw))


def unescape(field):
    return field.replace("\\t", "\t").replace("\\n", "\n").replace("\\\\", "\\")


def unescape_cmd(field):
    """`unescape` plus `\\xHH`, in one pass so an escaped backslash cannot be re-read."""
    simple = {"n": "\n", "t": "\t", "\\": "\\"}
    out, i = [], 0
    while i < len(field):
        if field[i] == "\\" and i + 1 < len(field):
            nxt = field[i + 1]
            if (nxt == "x" and i + 3 < len(field)
                    and all(c in "0123456789abcdefABCDEF" for c in field[i + 2:i + 4])):
                out.append(chr(int(field[i + 2:i + 4], 16)))
                i += 4
                continue
            if nxt in simple:
                out.append(simple[nxt])
                i += 2
                continue
        out.append(field[i])
        i += 1
    return "".join(out)


def rewritten(rc, stdout, stderr="", event="PreToolUse"):
    if rc != 0:
        return "exit%d" % rc
    if classify(rc, stdout, stderr, event) == "error":
        return "error"
    try:
        command = json.loads(stdout)["hookSpecificOutput"]["updatedInput"]["command"]
        return REWRITE + command if isinstance(command, str) else "error"
    except (ValueError, TypeError, KeyError):
        return "raw"


def classify(rc, stdout, stderr="", event=None):
    """Outcome of one run. `stderr` is load-bearing — see the `error` case below."""
    if rc == 2:
        return "hard"
    if rc == 1:
        return "soft"
    if rc < 0:
        return "signal%d" % -rc
    if rc != 0:
        return "exit%d" % rc
    # Exit 0 with stderr is a hook that broke, not one that passed. see: README.md § Why three
    if stderr.strip():
        return "error"
    if not stdout.strip():
        return "allow"
    try:
        parsed = json.loads(stdout)
    except ValueError:
        return "error"
    if not isinstance(parsed, dict):
        return "error"
    if "continue" in parsed and not isinstance(parsed["continue"], bool):
        return "error"
    if "hookSpecificOutput" in parsed and not isinstance(parsed["hookSpecificOutput"], dict):
        return "error"
    out = parsed.get("hookSpecificOutput", {})
    if "hookSpecificOutput" in parsed and not isinstance(out.get("hookEventName"), str):
        return "error"
    if event is None:
        event = out.get("hookEventName", "PreToolUse")
    if "hookEventName" in out and out["hookEventName"] != event:
        return "error"
    if "permissionDecision" in out:
        decision = out["permissionDecision"]
        if event != "PreToolUse" or decision not in PERMISSION_DECISIONS:
            return "error"
    if "additionalContext" in out and not isinstance(out["additionalContext"], str):
        return "error"
    if "updatedInput" in out and (event != "PreToolUse" or not isinstance(out["updatedInput"], dict)):
        return "error"
    if "decision" in parsed:
        valid = ("approve", "block") if event == "PreToolUse" else ("block",)
        if event not in ("PreToolUse", "PostToolUse", "Stop", "SubagentStop", "UserPromptSubmit") or parsed["decision"] not in valid:
            return "error"
    if parsed.get("continue") is False:
        return "halt"
    if "permissionDecision" in out:
        return out["permissionDecision"]
    if parsed.get("decision") == "block":
        return "deny" if event == "PreToolUse" else "block"
    if out.get("additionalContext"):
        return "ctx"
    return "allow"


def resolve_hook(hooks_dir, name):
    """Flat `<dir>/<name>.sh` is the installed layout; nested is this repo's examples."""
    for candidate in (hooks_dir / ("%s.sh" % name), hooks_dir / name / ("%s.sh" % name)):
        if candidate.is_file():
            return candidate
    sys.exit("no hook %r under %s (tried both flat and <name>/<name>.sh)" % (name, hooks_dir))


def parse_fixture(path):
    cases = []
    event, tool, escapes, setup_name = "PreToolUse", "Bash", False, ""
    for raw in path.read_text().splitlines():
        if raw.startswith("#!escapes"):
            escapes = True
            continue
        if raw.startswith("#!setup "):
            setup_name = raw[len("#!setup "):].strip()
            continue
        if raw.startswith("#!event "):
            event = raw[len("#!event "):].strip()
            continue
        if raw.startswith("#!tool "):
            tool = raw[len("#!tool "):].strip()
            if tool not in TOOL_INPUT:
                sys.exit("unknown #!tool %r; known: %s" % (tool, ", ".join(TOOL_INPUT)))
            continue
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        expected, _, rest = raw.partition("\t")
        if not rest:
            sys.exit("malformed fixture line (needs a TAB): %r" % raw)
        cmd, _, tail = rest.partition("\t")
        output, _, flags = tail.partition("\t")
        # A doubled tab empties column 2, and an empty command passes while testing nothing.
        if cmd != ABSENT and not cmd.strip():
            sys.exit("empty command in fixture line (a stray extra TAB?): %r" % raw)
        if escapes and cmd != ABSENT:
            cmd = unescape_cmd(cmd)
        # Bound per case: a mid-file directive must not apply to earlier cases too.
        cases.append((parse_expected(expected, raw), cmd, unescape(output), flags, tool, event))
    return cases, setup_name


def build_payload(cmd, output, flags, tool, event, cwd, tmp, index=0):
    payload = {
        "session_id": "fixture",
        "cwd": cwd,
        "hook_event_name": event,
        "tool_name": tool,
        "tool_input": {} if cmd == ABSENT else TOOL_INPUT[tool](
            cmd, output, unescape(flags) if event == "PreToolUse" else ""),
    }
    if event == "UserPromptSubmit" and cmd != ABSENT:
        # These hooks read .prompt and never tool_input, so without it none can fire.
        payload["prompt"] = cmd
        if output:
            payload["transcript_path"] = output
    if event == "Stop":
        # Stop hooks read a transcript, never tool_input, so one has to be materialised.
        # One file per case: under --jobs, cases sharing a name would read each other's transcript.
        transcript = os.path.join(tmp, "fixture-stop-transcript-%d.jsonl" % index)
        with open(transcript, "w", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "type": "assistant",
                "message": {"content": [{"type": "text", "text": cmd}]},
            }) + "\n")
        payload["transcript_path"] = transcript
        payload["stop_hook_active"] = output.strip().lower() == "true"
    if event == "PostToolUse" and tool == "AskUserQuestion":
        # A menu result maps each question to the label picked, so column 3 is the answer.
        payload["tool_response"] = {"answers": {} if cmd == ABSENT else {cmd: output}}
    elif event == "PostToolUse":
        flagset = {f.strip() for f in flags.split(",") if f.strip()}
        # tool_response, not tool_result: a hook reading the latter gets "" for every command.
        payload["tool_response"] = {
            "stdout": output,
            "stderr": "",
            "interrupted": False,
            "noOutputExpected": "noOutputExpected" in flagset,
        }
        if "background" in flagset:
            payload["tool_response"]["backgroundTaskId"] = "bg_fixture"
    return payload


def substitute_case(case, tokens):
    """Expands tokens in one case, exiting on an unknown one before any case has run."""
    expected, cmd, output, flags, tool, event = case
    if cmd != ABSENT:
        cmd = substitute(cmd, tokens)
    output = substitute(output, tokens)
    if tokens:
        left = TOKEN_RE.findall(cmd) + TOKEN_RE.findall(output)
        if left:
            sys.exit("unknown token(s) %s in %r\n  known: %s"
                     % (", ".join(sorted(set(left))), cmd, ", ".join(sorted(tokens))))
    return expected, cmd, output, flags, tool, event


def run_case(index, case, cwd, env, args, hook_path, tmp):
    """Runs one case in its own hook process; returns (expected, got, cmd, stderr)."""
    expected, cmd, output, flags, tool, event = case
    payload = build_payload(cmd, output, flags, tool, event, cwd, tmp, index)
    try:
        proc = subprocess.run(
            ["bash", str(hook_path)],
            input=json.dumps(payload),
            capture_output=True, text=True, cwd=cwd,
            timeout=args.timeout, env=env,
        )
    except subprocess.TimeoutExpired:
        return expected, "TIMEOUT", cmd, ""
    if expected == "raw" or expected.startswith(REWRITE):
        got = rewritten(proc.returncode, proc.stdout, proc.stderr, event)
    else:
        got = classify(proc.returncode, proc.stdout, proc.stderr, event)
    return expected, got, cmd, proc.stderr


def run_cases(cases, tokens, cwd, env, args, hook_path, failures, tmp):
    """Returns how many cases ran: --fail-fast stops at the first mismatch that is not a TIMEOUT."""
    cases = [substitute_case(case, tokens) for case in cases]
    # Results are read in file order, so output and the fail-fast stop match a serial run.
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs)
    try:
        futures = [pool.submit(run_case, i, case, cwd, env, args, hook_path, tmp)
                   for i, case in enumerate(cases)]
        for ran, future in enumerate(futures, 1):
            expected, got, cmd, stderr = future.result()
            if got != expected:
                failures.append((expected, got, cmd))
            print("%s want=%-7s got=%-7s %s"
                  % ("ok  " if got == expected else "FAIL", expected, got, cmd[:78]))
            if got == "error" and expected != "error":
                print("       stderr: %s" % " ".join(stderr.split())[:150])
            if args.fail_fast and got != expected and got != "TIMEOUT":
                return ran
        return len(cases)
    finally:
        pool.shutdown(wait=True, cancel_futures=True)


def main():
    here = pathlib.Path(__file__).resolve().parent
    ap = argparse.ArgumentParser()
    ap.add_argument("hook")
    ap.add_argument("--hooks-dir", default=str(here.parent),
                    help="where the hooks live (default: this directory's parent)")
    ap.add_argument("--cwd", default=os.getcwd())
    ap.add_argument("--timeout", type=float, default=10.0)
    # A timeout says the host was slow, not that the hook is wrong, so it never stops the run.
    ap.add_argument("--fail-fast", action="store_true",
                    help="stop at the first mismatch that is not a TIMEOUT (mutation runs)")
    # Each case is its own hook process, so N can run at once; a hook whose verdict reads state an earlier case left must stay at 1.
    ap.add_argument("--jobs", type=int, default=1,
                    help="cases to run at once (default 1); results still print in file order")
    args = ap.parse_args()
    if args.jobs < 1:
        sys.exit("--jobs must be 1 or more: %d" % args.jobs)

    hook_path = resolve_hook(pathlib.Path(args.hooks_dir).expanduser().resolve(), args.hook)
    fixture_path = here / "fixtures" / ("%s.tsv" % args.hook)
    if not fixture_path.is_file():
        sys.exit("missing fixture: %s" % fixture_path)

    cases, setup_name = parse_fixture(fixture_path)

    # Redirected, or fixture runs land in the live corpus and inflate its counts.
    tmp = tempfile.mkdtemp(prefix="fixture-diag-")
    env = dict(
        os.environ,
        HOOK_DIAG_LOG=os.path.join(tmp, "blocks.log"),
        HOOK_DIAG_ALLOW_LOG=os.path.join(tmp, "allows.log"),
        HOOK_DIAG_ASK_LOG=os.path.join(tmp, "asks.log"),
        CLAUDE_HOOK_FIXTURE_RUN="1",
    )

    tokens, cwd = {}, args.cwd
    if setup_name:
        if setup_name not in fixture_env.SETUPS:
            shutil.rmtree(tmp, ignore_errors=True)
            sys.exit("unknown #!setup %r; known: %s"
                     % (setup_name, ", ".join(sorted(fixture_env.SETUPS))))
        state = fixture_env.SETUPS[setup_name](tmp)
        tokens = state.get("tokens", {})
        env.update(state.get("env", {}))
        cwd = state.get("cwd", cwd)

    failures = []
    try:
        ran = run_cases(cases, tokens, cwd, env, args, hook_path, failures, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if ran < len(cases):
        print("\nstopped at the first failure (--fail-fast): %d of %d cases run" % (ran, len(cases)))
    print("\n%d/%d passed" % (ran - len(failures), ran))
    if failures:
        print("\n%d FAILURES:" % len(failures))
        for expected, got, cmd in failures:
            # Tab-separated: a rewrite outcome is a command with spaces, which a space-delimited row cannot carry.
            print("  want=%s\tgot=%s\t%s" % (expected, got, cmd))
        sys.exit(1)


if __name__ == "__main__":
    main()
