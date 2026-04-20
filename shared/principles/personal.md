# Personal Environment Preferences

> **Context:** These are the repo owner's personal conventions. They are not universal — apply them only if they match your setup, or adapt them to yours.

## Python Environment

- Project uses `pyenv` with a virtual environment (name specific to the project).
- Respect the existing `pyenv` configuration and virtualenv setup; don't create parallel envs.
- Ensure commands run inside the established virtualenv context (activate before invoking, or prefix with the venv's `python`/`pip`).

## Terminal and Shell

- Open terminal sessions that load custom dotfiles (aliases, functions, env). Avoid vanilla shells that miss configuration.
- Don't use `echo` in the terminal to display information that the assistant can just state directly.
- Reuse existing shell aliases and helper functions when they exist.

## Naming Conventions

- Prefer the `_resolved` suffix over `_final` for variables that have been computed or derived.
- Names should reflect the variable's lifecycle (`raw_`, `parsed_`, `resolved_`), not generic finality.
- Keep naming patterns consistent across modules and services.

## Project Integration

- Respect existing architecture and established patterns — don't refactor to a preferred style unasked.
- Use project-specific conventions for naming and file layout.
- Follow established workflows (branch naming, commit format, PR process) within the project.
- Honor project-specific constraints (compliance, tenant isolation, performance budgets) when shaping solutions.

## Using these on your own setup

If you're copying rules from this repo into your own assistant config, either skip this file or replace its contents with the equivalent conventions from your setup. The other files in `shared/principles/` are meant to be universal; this one is not.
