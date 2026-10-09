# Stateful operations

Use these rules for changes to external permissions, resources, or data in this project.

1. Identify the environment, resource, tenant, and acting identity before making a change; resolve ambiguity before proceeding.
2. Read the full live state of the affected objects and their consumers; cached state and repository configuration are not proof of current state.
3. Preserve a recoverable before-state, including all fields needed to restore the objects; protect any sensitive backup.
4. Review the exact proposed change, its impact, and recovery procedure. Obtain explicit consent for destructive, production, or shared-state changes.
5. Execute only the approved scope. Do not retry across environment or tenant boundaries or expand the target set without consent.
6. Re-read live state, compare it with the before-state, and test from the consumer's perspective. Report what is live separately from what repository changes codify, with remaining discrepancies and verification limits.
