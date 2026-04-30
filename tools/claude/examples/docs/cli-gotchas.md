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
