# Terraform Apply Safety Rules

- **Manual apply picks up ALL code changes** — A terraform apply runs the current module code, not just your intended change. Before any manual apply, compare the current values against what terraform will generate. If there are unrelated changes beyond your intended diff, stop and flag them.

- **Always resolve the running image tag before apply** — Modules may default `image_tag` to `main`. Before any manual apply: (1) check the running image: `kubectl get pods -o jsonpath='{.spec.containers[*].image}'`, (2) pass it explicitly: `-var='image_tag=<actual-tag>'`. Never rely on the module default.

- **state rm vs destroy — know the intent** — If the goal is to delete a cloud resource, use `terraform destroy -target`. If the goal is to remove tracking of a resource that should continue to exist (moved, imported elsewhere), use `terraform state rm`. Always state which you're using and why, and confirm with the user.

- **Workspaces — always list before creating** — Run `terraform workspace list` AND check the state bucket before any workspace operation. Never create without presenting the proposed name and getting approval.
