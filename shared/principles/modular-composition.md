# Modular Composition (the Lego principle)

> **Scope:** Universal — applies to any AI coding assistant on any project. Adapt examples to your environment.

**Core thesis:** Build software as **separate parts that snap together cleanly** — never as one large blob with implicit couplings. Each part has a sharp, named boundary; what crosses the boundary is a typed contract; what stays inside is private. The system emerges from composition, not from sprawl.

This principle is stack-agnostic. It applies to Python services, internal libraries, agent personas, orchestrators, Terraform infrastructure, and any system humans and AI agents iterate on together.

---

## The principle (timeless)

A module is **Lego-shaped** when it satisfies all of:

1. **Single responsibility.** It exists to do one thing, named precisely. Not "utilities", not "core", not "common", not "shared" — those are blob-collectors.
2. **Public API contract.** A small, explicit set of inputs (typed variables / function signatures / message schemas) and outputs (returns / outputs / events). Everything else is private.
3. **Typed boundaries.** Inter-module communication is structured and typed — Pydantic models, Terraform `object()` types with descriptions and validation, dataclasses, protobuf, JSON Schema. **Never** stringly-typed `dict[str, Any]` passed across a seam.
4. **Self-contained tests.** A dedicated test suite verifies the module against its contract without reaching into siblings or requiring the rest of the system to be running. If you must boot the whole world to test one module, the boundary leaks.
5. **Replaceable.** You should be able to delete the module's implementation and rewrite it without changing any caller — because callers depend on the contract, not the internals.
6. **Composable, not centralized.** Higher-level systems are built by **composing** modules, not by adding `if-this-tenant-then` branches to a god module. New behavior = new module + new wiring, not new flags inside an existing one.
7. **Documented for the next maintainer.** A README (or module-header docstring) that explains the contract, extension points, and failure modes — written in the imperative ("To add X, edit Y"), not in storytelling.

**Module names matter.** A name that resists this principle is a smell — `helpers/`, `shared/`, `misc/`, `lib/`, `extras/`, `core/`. If you cannot name the module by what it *does*, the boundary is wrong.

---

## Module boundaries are agent task boundaries (the teeth)

The Lego principle is not just "good architecture" — in agent-driven development, **module boundaries are agent task boundaries**. One agent owns one module. This sharpens every constraint above:

- **The contract is the agent's input/output spec.** A well-defined module gives an agent a tight scope: "implement this, satisfy these inputs/outputs, pass this test suite." A blob gives the agent the whole repo to reason about, which it cannot do reliably.
- **The dedicated test suite is the agent's verification harness.** The agent runs the module's test suite and knows whether its work is correct *without touching other modules*. This is the only way to delegate work safely.
- **The README is written for an agent, not for a casual reader.** "To extend this module, edit `X`. To add a new `Y`, follow this pattern." Imperative, scannable, no narrative — agents extract the rule, not the story.
- **Typed boundaries prevent agent hallucinations.** A schema rejects a malformed inter-module call at the boundary. A dict-of-anything lets the agent silently ship a wrong shape and fails three modules downstream.
- **Replaceability is what makes agent rewrites safe.** When an agent rewrites a module's internals, no consumer breaks because no consumer depended on the internals. This is what allows an agent to operate without a senior engineer in the loop on every change.
- **A typed bus between major components is the same idea, scaled up.** If an orchestrator and a UI communicate over a SQLite schema (or a message queue, or a structured log file), either side can be rewritten without touching the other. The schema is the contract — frozen, typed, observable, replayable.

**Heuristic:** if you cannot describe a module's task to an agent in 5 sentences with a link to its tests and its README, the module is not Lego-shaped yet.

This is also the foundation of the [specialist-agent-roster pattern](agent-design-patterns.md): one agent per bounded domain, sibling deferral tables, structured handoff. The agent layer is just another instance of modular composition — the same constraints (sharp boundary, typed handoff, replaceability) apply to agent personas as to code modules.

---

## Concrete shape across stacks

### Terraform

- **Modules are the units.** Each has typed `variables.tf` (with `description` and `validation`), `outputs.tf`, a clear `main.tf`, optional `locals.tf` / `data.tf` / domain-named files (`security_groups.tf`, `iam_data.tf`), and pinned source (commit SHA, Git tag, or registry version — never a branch reference).
- **Single-purpose modules, composed.** A monolithic `aws-eks` module that bundles every concern is the wrong shape; the right shape is to split into `cluster` + `node_groups` + `addons` + `access_entries` and let the consumer compose only what they need. HashiCorp's published style guide nudges in this direction (it advises grouping "logically related resources" into modules) but stops short of opposing flag-gated mega-modules. The Lego principle goes further: prefer a clean composition seam over `count = var.enable_*` switches inside one module. The flag accretion is the smell.
- **Config drives composition.** Per-environment, per-tenant, per-region values live in `*.tfvars` or `*.json`; `.tf` files are structural. New environments and tenants are config edits, not code edits.
- **Workspaces or directory layout encode the composition boundary.** Each workspace is one composition of modules with its own state.
- **Cross-cutting concerns get their own module.** A `tags` module called from every other module beats duplicating tag logic. A `naming` module beats `lower(replace(...))` calls scattered across resources.
- **Minimal variables.** HashiCorp's style guide cautions against over-parameterizing modules — every variable adds a degree of freedom the consumer has to understand and the maintainer has to support. Expose what genuinely varies between consumers; hide what doesn't.

### Python and other application code

- **One concern per package.** Vertical slices by domain (`auth/`, `billing/`, `audit_log/`), not horizontal slices by layer (`models/`, `views/`, `controllers/` at the system level). Layering is fine *inside* a module; at the system level, modules are vertical.
- **Typed models at every API boundary.** Request schema, response schema, event schema — Pydantic, dataclasses, attrs, protobuf. No untyped dicts crossing process boundaries.
- **Each package has `tests/` parallel to `src/`** runnable in isolation. Integration tests live separately and compose multiple modules deliberately.
- **Public API = `__init__.py` + a `README.md`** that lists exported names and what they're for. Anything imported from a deep internal path is *not* part of the contract.

### Agent personas

- **One persona per file.** Sharp scope: `devops-reviewer`, `security-reviewer`, `agent-config-reviewer`. No "general-helper" personas — those are the agent-layer equivalent of `utils/`.
- **Agent input is a typed prompt; agent output is a structured report.** Free-form blob output is a contract failure.
- **Inter-agent state goes through a typed bus** — a schema-backed file, a database table, a ticket-system comment, a message queue. Never via shared in-memory state or implicit context inheritance. Subagents that don't inherit parent context are safer for the same reason a Python module that doesn't import globals is safer.

---

## Anti-patterns to reject on sight

- **The blob module** — `core/`, `utils/`, `helpers/`, `shared/`, `common/`, `misc/` accumulating unrelated functions. Split by concern; rename by what it does.
- **Stringly-typed boundaries** — passing `dict[str, Any]` between modules, parsing magic strings on the consumer side, JSON blobs without a schema, environment variables read from anywhere.
- **Implicit globals as the bus** — module-level singletons, "just import the thing from there", mutable shared state. If a module reaches across the boundary, the boundary is fake.
- **Test suites that require booting the whole system** — if the module's tests can't run without a database, queue, secret store, and three sibling services, the module isn't isolated. Integration tests are valuable, but they don't replace per-module tests.
- **Flag-flag-flag accretion** — `if env == 'prod' and tenant == 'X' and feature_y_enabled`. A new behavior nested behind three flags is a new module that wasn't extracted. In Terraform, the equivalent is `count = var.enable_X ? 1 : 0` gating a sub-resource inside a module — that's a child module asking to be extracted.
- **Documentation as narrative** — "Once upon a time we needed X so we built Y" READMEs. The next reader (human or agent) needs the contract, not the history; history goes to git, PR bodies, or ADRs.
- **Module names that describe layers, not concerns** — `models/`, `views/`, `controllers/` at the *system* level. Layering is fine inside a module; at the system level, modules are vertical (by concern), not horizontal (by layer).
- **Cross-module imports of internals** — if `module_a` imports from `module_b/_internal/foo.py`, the boundary is leaking. The internals should not be reachable.

---

## Review checklist

When designing a new module or reviewing a change that adds one:

1. **Name the module by what it does.** If you can't, the boundary is wrong.
2. **Sketch the public API first.** Inputs, outputs, error shape. Write the contract before the implementation.
3. **Write the tests against the contract, not the implementation.** Tests should survive a full rewrite.
4. **Verify nothing crosses the boundary except typed values.** Grep for `dict[str, Any]`, `**kwargs`, untyped JSON at the seams. Replace with models.
5. **Verify the module can be deleted and rewritten without consumer changes.** If `git grep` for the module's internal symbols hits other modules, the boundary leaks.
6. **Document for the next maintainer.** README in imperative voice, listing extension points and failure modes.

When extending an existing module:

- If the new behavior **fits within the module's single responsibility**, add it inside.
- If it **stretches** the responsibility, **split** — extract a new module and compose.
- If you find yourself adding a flag to gate the new behavior, that flag is a sign the new behavior wants its own module.

---

## See also

- [`agent-design-patterns.md`](agent-design-patterns.md) — the specialist-agent-roster pattern is the agent-layer expression of this principle.
- [`../infrastructure/terraform.md`](../infrastructure/terraform.md) — single-purpose Terraform modules and the canonical `aws-eks` split.
