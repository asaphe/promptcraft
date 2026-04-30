# SCP Deny statements must cover both creation and mutation actions

## Rule

When an SCP restricts a service API parameter (e.g., `sagemaker:AppNetworkAccessType`), the
`Action` list must include **every API that accepts that parameter** — not just the creation call.
Blocking `CreateDomain` without `UpdateDomain` allows any principal to reconfigure an existing
domain and bypass the constraint.

## SageMaker network access (confirmed pattern)

```json
"Action": ["sagemaker:CreateDomain", "sagemaker:UpdateDomain"]
```

`UpdateDomain` accepts `AppNetworkAccessType` just like `CreateDomain`. An SCP that omits it is
silently incomplete — AWS will not error; the update simply succeeds.

## General checklist before publishing a new Deny SCP

1. List every API that accepts the restricted parameter (check AWS docs at authoring time).
2. Include creation, update/modify, and restore/import variants where they exist.
3. Test with `aws iam simulate-custom-policy` against both create and update calls.
