# Choose one Kyverno validation style and stick to it

## Rule

Within any Kyverno policy file, all rules that **block violations** should use the same validation sub-key. Mixing `validate.pattern` and `validate.deny` in the same file increases cognitive load during audit and creates inconsistency for reviewers.

The principle (consistency-within-a-file) is the load-bearing part. The specific choice of `validate.deny.conditions.all` vs `validate.pattern` is style — pick whichever your team finds clearer.

## Background

`validate.pattern` and `validate.deny` are both valid Kyverno constructs, but they signal different intents to readers:

- `validate.pattern` — resource must *match* the pattern (allow-list semantics)
- `validate.deny.conditions` — explicit condition-based deny (block-list semantics)

For security-posture policies (deny access, block misconfiguration), many teams find `validate.deny` more readable because the predicate maps directly onto the failure case. Other teams prefer `validate.pattern` for its declarative shape. Both work — the audit cost comes from **mixing** them in one file.

## Exception

`validate.pattern` is appropriate for mutation-companion validations or when a policy is intentionally enforcing a required field shape (e.g., all labels must be present), regardless of the rest of the file's style.
