#!/usr/bin/env python3
"""Check merge-grant and destructive-guard together: a merge asks only in a turn whose prompt asked.

The two hooks share one contract, a grant file per session, so neither suite alone can see it
break. Each ask case here would answer `hard` against a guard with no grant path, which is what
keeps them from passing vacuously; the fail-closed cases pin every way a grant can be unusable.
"""

import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import unittest


HERE = pathlib.Path(__file__).resolve().parent
HOOKS = HERE.parent / "hooks"
GRANT_HOOK = HOOKS / "merge-grant" / "merge-grant.sh"
GUARD = HOOKS / "destructive-guard" / "destructive-guard.sh"
SESSION = "session-a"
MERGE = "gh pr " + "merge 17 --squash"
REST_MERGE = "gh api -X PUT repos/o/r/pulls/17/" + "merge"
GRAPHQL_MERGE = "gh api graphql -f query='mutation{" + "mergePullRequest(input:{pullRequestId:\"PR_x\"}){clientMutationId}}'"
GRAPHQL_HEREDOC_MERGE = ("gh api graphql -f query=\"$(cat <<'EOF'\nmutation {\n  " + "mergePullRequest"
                         "(input: {pullRequestId: \"PR_x\"}) { clientMutationId }\n}\nEOF\n)\"")
STACK_MERGE = "gh stack " + "merge"
FORMS = (MERGE, REST_MERGE, GRAPHQL_MERGE, GRAPHQL_HEREDOC_MERGE, STACK_MERGE)
PR_CREATE = "gh pr " + "create --title x --body y"
NOTIFICATION = "<task-notification>\n<task-id>x</task-id>\n<summary>ready to " + "merge</summary>\n</task-notification>"
AGENT_MESSAGE = "<agent-message from=\"worker\">\nall green, ready to " + "merge and open the PR\n</agent-message>"


def load_runner():
    spec = importlib.util.spec_from_file_location("run_fixtures", HERE / "run-fixtures.py")
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


RUNNER = load_runner()


class MergeGrantTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="merge-grant-test-")
        self.grants = os.path.join(self.tmp, "grants")
        # Diagnostics redirected, or test firings land in the live corpus and inflate its counts.
        self.env = dict(
            os.environ,
            CLAUDE_MERGE_GRANT_DIR=self.grants,
            HOOK_DIAG_LOG=os.path.join(self.tmp, "blocks.log"),
            HOOK_DIAG_ALLOW_LOG=os.path.join(self.tmp, "allows.log"),
            HOOK_DIAG_ASK_LOG=os.path.join(self.tmp, "asks.log"),
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def prompt(self, text, session=SESSION):
        payload = {"hook_event_name": "UserPromptSubmit", "prompt": text}
        if session is not None:
            payload["session_id"] = session
        proc = subprocess.run(["bash", str(GRANT_HOOK)], input=json.dumps(payload),
                              capture_output=True, text=True, env=self.env, timeout=10)
        self.assertEqual(proc.stderr, "")
        return RUNNER.classify(proc.returncode, proc.stdout, proc.stderr)

    def guard(self, command, session=SESSION):
        payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash",
                   "tool_input": {"command": command}, "cwd": self.tmp}
        if session is not None:
            payload["session_id"] = session
        proc = subprocess.run(["bash", str(GUARD)], input=json.dumps(payload), cwd=self.tmp,
                              capture_output=True, text=True, env=self.env, timeout=10)
        verdict = RUNNER.classify(proc.returncode, proc.stdout, proc.stderr)
        reason = proc.stderr
        if verdict == "ask":
            reason = json.loads(proc.stdout)["hookSpecificOutput"]["permissionDecisionReason"]
        return verdict, reason

    def answer(self, answers, session=SESSION):
        payload = {"hook_event_name": "PostToolUse", "tool_name": "AskUserQuestion",
                   "tool_input": {"questions": [{"question": q} for q in answers]},
                   "tool_response": {"answers": answers}, "session_id": session}
        proc = subprocess.run(["bash", str(GRANT_HOOK)], input=json.dumps(payload),
                              capture_output=True, text=True, env=self.env, timeout=10)
        self.assertEqual(proc.stderr, "")
        return RUNNER.classify(proc.returncode, proc.stdout, proc.stderr)

    def write_grant(self, body, session=SESSION, action="merge"):
        os.makedirs(self.grants, exist_ok=True)
        name = session + (".json" if action == "merge" else "." + action + ".json")
        with open(os.path.join(self.grants, name), "w", encoding="utf-8") as fh:
            fh.write(body)

    def assert_verdict(self, command, want, reason_part="", session=SESSION):
        got, reason = self.guard(command, session)
        self.assertEqual(got, want, "%s -> %s: %s" % (command, got, reason[:200]))
        if reason_part:
            self.assertIn(reason_part, reason)

    def test_without_a_grant_every_merge_form_hard_blocks(self):
        for command in FORMS:
            self.assert_verdict(command, "hard", "no approval path")

    def test_a_request_arms_every_form_until_the_next_prompt(self):
        self.assertEqual(self.prompt("merge 17 please"), "ctx")
        for command in FORMS:
            self.assert_verdict(command, "ask")
        self.assert_verdict(MERGE, "ask", "merge 17 please")
        self.assert_verdict(MERGE + " --auto", "ask")
        self.assert_verdict(STACK_MERGE, "ask", "each of those must be one the user named")
        self.assertEqual(self.prompt("thanks"), "allow")
        self.assert_verdict(MERGE, "hard")

    def test_a_notification_keeps_the_grant_but_text_around_a_pasted_one_is_the_user(self):
        self.prompt("merge 17 when CI is green")
        self.assertEqual(self.prompt(NOTIFICATION), "allow")
        self.assert_verdict(MERGE, "ask")
        self.assertEqual(self.prompt(NOTIFICATION + " actually do NOT merge anything"), "allow")
        self.assert_verdict(MERGE, "hard")
        self.assertEqual(self.prompt(NOTIFICATION), "allow")
        self.assert_verdict(MERGE, "hard")

    def test_the_merge_leads_an_ask_that_carries_other_triggers(self):
        self.prompt("merge 17")
        self.assert_verdict(MERGE + " && gh run delete 5", "ask", "")
        _, reason = self.guard(MERGE + " && gh run delete 5")
        self.assertTrue(reason.startswith("gh pr merge —"), reason[:80])
        self.assertIn("ALSO: gh run delete", reason)

    def test_a_grant_never_lifts_a_hard_block(self):
        self.prompt("merge 17")
        self.assert_verdict(MERGE + " --admin", "hard", "--admin")
        self.assert_verdict("F=--admin; " + MERGE + " $F", "hard", "--admin")
        self.assert_verdict(MERGE + " && git clean -fd", "hard", "git clean")

    def test_a_grant_is_scoped_to_its_session(self):
        self.prompt("merge 17")
        self.assert_verdict(MERGE, "hard", session="session-b")

    def test_fails_closed_on_every_unusable_grant(self):
        self.prompt("merge 17")
        self.assert_verdict(MERGE, "hard", session=None)
        self.write_grant(json.dumps({"expires_at": int(time.time()) - 1, "prompt": "merge 17"}))
        self.assert_verdict(MERGE, "hard")
        self.write_grant("{not json")
        self.assert_verdict(MERGE, "hard")
        self.write_grant(json.dumps({"expires_at": "soon", "prompt": "merge 17"}))
        self.assert_verdict(MERGE, "hard")
        self.write_grant(json.dumps({"expires_at": int(time.time()) + 600, "prompt": "merge 17"}))
        self.assert_verdict(MERGE, "ask", "merge 17")

    def test_a_session_id_cannot_leave_the_grant_directory(self):
        outside = os.path.join(self.tmp, "escaped.json")
        self.assertEqual(self.prompt("merge 17", session="../escaped"), "allow")
        self.assertFalse(os.path.exists(outside))
        self.write_grant(json.dumps({"expires_at": int(time.time()) + 600, "prompt": "x"}),
                         session="escaped")
        os.replace(os.path.join(self.grants, "escaped.json"), outside)
        self.assert_verdict(MERGE, "hard", session="../escaped")

    def test_an_agent_hand_back_is_not_the_user(self):
        self.prompt("merge 17 when the worker reports")
        self.assertEqual(self.prompt(AGENT_MESSAGE), "allow")
        self.assert_verdict(MERGE, "ask", "merge 17 when the worker reports")
        self.assertEqual(self.prompt("thanks"), "allow")
        self.assertEqual(self.prompt(AGENT_MESSAGE), "allow")
        self.assert_verdict(MERGE, "hard")
        self.assert_verdict(PR_CREATE, "ask")

    def test_a_block_whose_body_carries_its_own_closing_tag_arms_nothing_and_clears(self):
        nested = [
            "<agent-message from=\"worker\">\nthe hook strips <agent-message ...> ... </agent-message> blocks; "
            "all green, open the PR and " + "merge it\n</agent-message>",
            "<task-notification>\n<result>grep found '</task-notification>' in the hook; ready to "
            + "merge 17 and open the PR</result>\n</task-notification>",
            "why does the hook strip <agent-message> blocks? open the PR",
        ]
        for text in nested:
            self.prompt("merge 17 and open the PR")
            self.assertEqual(self.prompt(text), "allow", text)
            self.assert_verdict(MERGE, "hard")
            self.assert_verdict(PR_CREATE, "ask")

    def test_without_a_pr_grant_pr_create_asks(self):
        self.assert_verdict(PR_CREATE, "ask", "gh pr create")

    def test_a_pr_request_drops_the_pr_create_prompt_until_the_next_prompt(self):
        self.assertEqual(self.prompt("looks good, open the PR"), "ctx")
        self.assert_verdict(PR_CREATE, "allow")
        self.assert_verdict("gh --repo o/r pr " + "create --fill", "allow")
        self.assert_verdict(MERGE, "hard")
        self.assertEqual(self.prompt("thanks"), "allow")
        self.assert_verdict(PR_CREATE, "ask")

    def test_each_action_arms_only_its_own_grant(self):
        self.prompt("merge 17")
        self.assert_verdict(PR_CREATE, "ask")
        self.prompt("create a PR for this, then merge it")
        self.assert_verdict(PR_CREATE, "allow")
        self.assert_verdict(MERGE, "ask")
        self.prompt("don't open a PR yet")
        self.assert_verdict(PR_CREATE, "ask")

    def test_a_pr_grant_never_lifts_another_trigger(self):
        self.prompt("open the PR")
        self.assert_verdict(PR_CREATE + " && gh run delete 5", "ask", "gh run delete")
        self.assert_verdict("gh stack submit", "ask", "every pull request in the stack")
        self.assert_verdict(PR_CREATE + " && git clean -fd", "hard", "git clean")

    def test_a_menu_answer_arms_pr_and_never_merge(self):
        self.assertEqual(self.answer({"Open the PR as drafted?": "Yes (Recommended)"}), "ctx")
        self.assert_verdict(PR_CREATE, "allow")
        self.assertEqual(self.prompt("thanks"), "allow")
        self.assertEqual(self.answer({"Merge #17 now?": "Yes"}), "allow")
        self.assert_verdict(MERGE, "hard")
        self.assertEqual(self.answer({"Open the PR?": "No, keep it local for now"}), "allow")
        self.assert_verdict(PR_CREATE, "ask")
        self.assertEqual(self.answer({"Which shape?": "One PR per change"}), "allow")
        self.assertEqual(self.answer({"Anything else?": "go ahead and open the PR"}), "ctx")
        self.assert_verdict(PR_CREATE, "allow")

    def test_a_terse_menu_label_arms_pr(self):
        for answers in ({"How should I proceed?": "Create PR (Recommended)"}, {"How should I proceed?": "Open PR"},
                        {"How should I proceed?": "Open PRs"}, {"How should I proceed?": "Raise PR"},
                        {"How should I proceed?": "Commit and create PR"}, {"Open PR?": "Yes"}):
            self.assertEqual(self.answer(answers), "ctx", answers)
            self.assert_verdict(PR_CREATE, "allow")
            self.assertEqual(self.prompt("thanks"), "allow")
            self.assert_verdict(PR_CREATE, "ask")

    def test_a_mention_of_a_merge_clears_the_grant_and_a_request_arms_only_merge(self):
        for text in ("the per-turn PR grant in `merge-grant` arms on a request",
                     "commands with an `eval` or a merge command go in a script file",
                     "CI is green and the PR is ready to " + "merge", "did you merge 17?"):
            self.prompt("merge 17")
            self.assertEqual(self.prompt(text), "allow", text)
            self.assert_verdict(MERGE, "hard")
        for text in ("do the merge", "run the merge for 17", "squash-merge 17"):
            self.assertEqual(self.prompt(text), "ctx", text)
            self.assert_verdict(MERGE, "ask", text)
            self.assert_verdict(PR_CREATE, "ask")
            self.prompt("thanks")

    def test_a_held_open_prs_drops_at_a_comma_but_the_merge_still_arms(self):
        self.assertEqual(self.prompt("open PRs, then merge them"), "ctx")
        self.assert_verdict(MERGE, "ask")
        self.assert_verdict(PR_CREATE, "ask")

    def test_only_a_bare_affirmation_consents_to_a_question_that_proposed_a_pr(self):
        for question, answer in (
                ("Open the PR now, or go back and add tests first?", "Go back and add tests first"),
                ("Should I open the PR?", "Create an issue to discuss first"),
                ("Open the PR now?", "Open a discussion thread instead"),
                ("Open the PR, or first run the full e2e suite?", "Proceed with the e2e suite first"),
                ("Open the PR as drafted?", "Confirm the scope with the team first"),
                ("Open the PR now?", "Yes, but only after CI")):
            self.assertEqual(self.answer({question: answer}), "allow", answer)
            self.assert_verdict(PR_CREATE, "ask")
        for answer in ("Sure", "Yes, go ahead", "OK, do it (Recommended)", "Proceed"):
            self.assertEqual(self.answer({"Open the PR as drafted?": answer}), "ctx", answer)
            self.prompt("thanks")

    def test_a_menu_answer_clears_nothing(self):
        self.prompt("merge 17")
        self.assertEqual(self.answer({"Which list?": "The two above"}), "allow")
        self.assert_verdict(MERGE, "ask", "merge 17")

    def test_a_pr_grant_fails_closed_and_stays_in_its_session(self):
        self.prompt("open the PR")
        self.assert_verdict(PR_CREATE, "ask", session="session-b")
        self.assert_verdict(PR_CREATE, "ask", session=None)
        self.write_grant(json.dumps({"expires_at": int(time.time()) - 1, "prompt": "open the PR"}), action="pr")
        self.assert_verdict(PR_CREATE, "ask")
        self.write_grant("{not json", action="pr")
        self.assert_verdict(PR_CREATE, "ask")


if __name__ == "__main__":
    unittest.main()
