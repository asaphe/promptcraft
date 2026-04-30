# GHA shell parameter expansion silently succeeds when prefix is absent — validate first

## Symptom

A workflow step strips a prefix with `${INPUT_WORKSPACE#prod_}` and produces a value that looks valid but is actually the full original string. Downstream `terraform workspace select` picks the wrong workspace with no error.

## Mechanism

POSIX parameter expansion `${VAR#prefix}` returns the full value unchanged when `prefix` is absent — it does not fail or produce an empty string. There is no signal that the expected prefix was missing.

## Rule

**Always validate the prefix exists before stripping it.** Use a POSIX `case` guard (not `[[ ]]` — shellcheck flags it in POSIX-mode scripts):

```bash
case "$INPUT_WORKSPACE" in
  prod_*) ;;
  *) echo "::error::INPUT_WORKSPACE must start with prod_ (got: $INPUT_WORKSPACE)" && exit 1 ;;
esac
WORKSPACE="${INPUT_WORKSPACE#prod_}"
```

## Counter-indications

Does not apply when the prefix is optional by design — only when the prefix is required for correctness (e.g., workspace naming conventions, environment routing).
