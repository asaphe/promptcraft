# Kubernetes Deployment & Update Patterns

- **kubectl set-image skips init containers** — When patching a deployment with init containers using `kubectl set image deployment/X container=image`, only the named container is updated; init containers are NOT touched. Must separately patch with `kubectl set image deployment/X init-container-name=image` for each init container. Failure to do this causes deployments to run with stale init container images, often surfacing as migration or startup failures.

- **Verify pod idle status from logs, not SQS metrics** — Before running `kubectl set-image` or other disruptive operations, confirm pods are not actively processing. SQS `ApproximateNumberOfMessagesNotVisible` does NOT guarantee idle state — visibility timeouts may have expired while a pod is still working. Instead, check pod logs (`kubectl logs -n {ns} -l app={app} --tail=50`) for recent activity. Stale log timestamps confirm the pod is actually idle.
