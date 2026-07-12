# Consent-Gated Capabilities

High-cost or high-blast-radius capabilities fire only on an *enumerated* consent signal — never inferred from task shape.

Destructive operations already get approval gates (see [`operational-safety-patterns.md`](operational-safety-patterns.md)). This principle covers the other expensive axis: capabilities that are safe but *costly* — multi-agent fan-out, cloud execution, deep-research sweeps — where the failure mode isn't damage, it's a surprise bill and an agent that "helpfully" spent 50× the tokens the user expected.

## The rule

Define, per capability, a closed list of signals that count as consent. Everything outside the list is not consent. A typical list:

- A **specific keyword** the user includes in the prompt.
- A **session-level toggle** the user switched on (standing consent until switched off).
- The user's **own words** requesting the mechanism — "use a workflow", "fan out agents", "orchestrate this with subagents".
- A **skill or command the user invoked** whose documented behavior includes the capability.

Explicitly **not** consent:

- "This task would benefit from parallelism." Task shape is an argument for *proposing* the capability, never for invoking it.
- A task merely *fitting* the capability's profile (mixed-domain review, multi-part audit).
- Consent given in a previous, unrelated task. Opt-in scopes to the task or session that granted it.
- A timeout on a question you asked. Silence means still waiting, not yes.

## The default path without consent

When the expensive capability would fit but no signal is present, do one of:

1. **Use the cheap primitive** — a single subagent, an inline pass — and deliver.
2. **Propose, with a cost sketch** — describe what the expensive mechanism would do, roughly what it costs, and the exact phrase that triggers it next time. At most one unsolicited proposal per conversation.

Never route around the gate by decomposing the expensive action into small steps that individually pass ("I'll just spawn agents one at a time").

## Why an enumerated list beats judgment

"Invoke when appropriate" degrades under pressure: an agent optimizing for task success will always find the expensive path appropriate. A closed list is checkable — by the model, by a hook, and by the user reading the transcript. It converts a vibes call ("did they *want* the big version?") into a string match. The same structure generalizes to any powerful tool a setup adds later: define the consent list *when you add the capability*, not after the first surprise.

## Calibrate inside the consent, too

Consent to the mechanism is not consent to unlimited depth. "Find any bugs" with a workflow keyword still means a small pass; "thoroughly audit, be comprehensive" means the large one. Scale within the granted mechanism to the words actually used.
