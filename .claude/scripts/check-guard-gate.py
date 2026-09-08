#!/usr/bin/env python3
"""Fail if destructive-guard's fast-path gate does not cover every rule.

The gate exits 0 early when the command names none of GUARD_TOOLS. That is a
fail-OPEN if a rule ever keys on a binary the gate omits: the rule silently
stops firing, and nothing in the eval suite notices unless a case happens to
cover it. So the token set is not trusted as written — it is re-derived from
the rule patterns and compared.

Run: python3 .claude/scripts/check-guard-gate.py
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".claude/hooks/destructive-guard.sh"
CASES = ROOT / ".claude/evals/destructive-guard/cases.json"

# Words that open a shell construct rather than name a binary. A rule keyed on one of these still
# requires a real binary later in the same pattern, which the leading-token scan below picks up.
SHELL_WORDS = {"for", "while", "cd", "do", "done", "if", "then"}


def normalise(cmd: str) -> str:
    """Mirror the hook's pre-gate normalisation.

    The gate runs on CMD_MATCH, which has already unquoted whitespace-free quoted tokens and
    flattened tabs. Testing the raw command instead would report a false failure on `"gh" pr
    merge` -- and, worse, could hide a real one behind a difference this checker invented.
    """
    cmd = cmd.replace("\\\n", " ").replace("\t", " ")
    cmd = re.sub(r"\"([^\"'\s]+)\"", r"\1", cmd)
    return re.sub(r"'([^\"'\s]+)'", r"\1", cmd)


def gate_tokens(src: str) -> set[str]:
    m = re.search(r"^GUARD_TOOLS='([^']+)'", src, re.M)
    if not m:
        sys.exit("FAIL: GUARD_TOOLS not found in the hook")
    return set(m.group(1).split("|"))


def rule_tokens(src: str) -> set[str]:
    """Leading binary of every `grep -qE` rule pattern in the hook."""
    found: set[str] = set()
    for pat in re.findall(r"grep -qE\s+[\"']([^\"']+)", src):
        # Patterns interpolate a prefix var (${TF_CHDIR}, ${PUSH_SEG}); resolve those first.
        for var, repl in re.findall(r"^(\w+)='([^']+)'", src, re.M):
            pat = pat.replace("${" + var + "}", repl)
        lead = re.match(r"\(?\^?\(?([a-z][a-z0-9-]*)", pat.lstrip("^("))
        if lead:
            tok = lead.group(1)
            if tok not in SHELL_WORDS:
                found.add(tok)
    return found


def main() -> None:
    src = HOOK.read_text()
    gate, rules = gate_tokens(src), rule_tokens(src)

    missing = sorted(rules - gate)
    if missing:
        sys.exit(
            "FAIL: rules key on binaries the fast-path gate does not list, so those rules "
            f"never run: {missing}\n  gate = {sorted(gate)}\n  Add them to GUARD_TOOLS."
        )

    # Second, independent check: every case the suite expects to be acted on must survive the gate.
    acted_on = [
        c for c in json.loads(CASES.read_text())
        if c.get("expected_exit") == 2 or any(
            k in c for k in ("expected_output", "expected_stdout", "expected_stderr")
        )
    ]
    gate_re = re.compile(rf"(^|[^A-Za-z0-9_.-])({'|'.join(sorted(gate))})(\s|$)")
    blocked_by_gate = [
        c["label"] for c in acted_on if not gate_re.search(normalise(c["command"]))
    ]
    if blocked_by_gate:
        sys.exit(
            "FAIL: the fast-path gate would drop commands the suite expects to be acted on:\n  "
            + "\n  ".join(blocked_by_gate)
        )

    # Control: the checker must be able to fail. A token the gate cannot contain must be reported.
    if not (rule_tokens(src) & gate):
        sys.exit("FAIL: derived zero rule tokens — the scan is broken, not the gate")

    print(f"OK: gate {sorted(gate)} covers all {len(rules)} rule binaries "
          f"and all {len(acted_on)} acted-on cases")


if __name__ == "__main__":
    main()
