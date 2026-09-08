# CLI Gotchas

Non-obvious CLI behavior that has caused failures. Each entry shows the wrong invocation, the correct one, and the underlying mechanism.

## `kubectl auth can-i --as-group` requires `--as` too

```bash
# WRONG — errors with "requesting uid, groups or user-extra without impersonating a user"
kubectl auth can-i get nodes --as-group=read-only

# CORRECT
kubectl auth can-i get nodes --as=test-user --as-group=read-only
```

Kubernetes API rejects group-only impersonation; a user identity must also be provided. The `--as` value can be any non-empty string for RBAC testing purposes.

## `gh api -F in_reply_to=<id>` sends string, not integer — use `--input`

```bash
# WRONG — 422: "For 'properties/in_reply_to', \"3145702701\" is not a number."
gh api repos/{owner}/{repo}/pulls/{n}/comments \
  -F in_reply_to=3145702701 \
  -f body="..."

# CORRECT — write JSON to file and use --input
cat > /tmp/reply.json <<EOF
{"body": "...", "in_reply_to": 3145702701}
EOF
gh api repos/{owner}/{repo}/pulls/{n}/comments --input /tmp/reply.json
```

`-F` and `-f` flags always send strings. The PR comment reply endpoint requires `in_reply_to` as a JSON integer. Use `--input` with a file containing valid JSON for any endpoint that requires non-string types.

## `gh api -f k=v` is a body field, never a query parameter

```bash
# WRONG — 404, because role= is sent as a POST-style body field on a GET
gh api "orgs/{org}/members" -f role=admin

# CORRECT — query parameters belong in the URL
gh api "orgs/{org}/members?role=admin&per_page=100" --paginate
```

The failure mode is what makes this worth writing down: the 404 yields an *empty collection*, which then reads as a legitimate "no results" in whatever consumes it. A `comm`/`diff`/set comparison built on that empty side returns a confident, wrong answer with no error anywhere. Verify the request shape before trusting an empty result — or make the query return a known-non-empty control first.

## Code-scanning alert dismissal is a separate API from PR thread resolution

When a code-scanning tool posts security alerts as PR review comments, resolving the GitHub PR thread (`resolveReviewThread` GraphQL mutation) does NOT dismiss the underlying alert — it remains open in the Security tab and re-renders on every CI run.

To fully clear an alert that is a false positive:

```bash
gh api -X PATCH "/repos/{owner}/{repo}/code-scanning/alerts/{n}" \
  -f state="dismissed" \
  -f dismissed_reason="false positive" \
  -f dismissed_comment="..."  # 280 char max
```

Valid `dismissed_reason`: `"false positive"`, `"won't fix"`, `"used in tests"`. Do BOTH thread-resolve (for PR-review hygiene) and alert-dismiss (for security-tab hygiene).

**GitHub's advisories API fails to empty, not to error** — `gh api /advisories/GHSA-xxxx-xxxx-xxxx` returns 404 for an advisory that exists, and the query form `gh api '/advisories?ecosystem=actions&affects={repo}'` returns zero bytes: no error, no rows, exit 0. Both read as "this advisory does not exist", which is a null with a plausible cover story, and the natural next move is to conclude the GHSA ID you were carrying is wrong and go looking for a different one. Verify an Actions advisory against the upstream repository's own release notes instead (`gh api repos/{owner}/{repo}/releases`), and print a byte count beside any advisories query so an empty body is visibly empty rather than a confident negative.

**Inline `# codeql[<query-id>]` suppression comments are NOT honoured** unless alert-suppression is explicitly enabled for the org — it is off by default, so verify before relying on it. Observed with the default setting: adding the directive above the flagged line produced a fresh scan with the alert simply re-reported one line lower, at the cost of a commit and a full CI cycle. The PATCH above is the only working route. Corollary worth generalising past code scanning: a suppression directive is a request, not a result — verify the alert actually cleared rather than treating the comment as the fix, and never leave a non-functional directive in the source, since it asserts a suppression that is not in effect.
