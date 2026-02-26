# CLAUDE.md - Navigation Hub Template

> **This file is auto-loaded into every conversation.** Keep it minimal — rules and pointers only.
> Move reference material (build commands, architecture, tech stack) to `.claude/docs/`.

## On-Demand Reference

For build commands and local dev setup, read `.claude/docs/codebase.md`.
For architecture and directory structure, read `.claude/docs/infrastructure.md`.
For CI/CD standards, read `.claude/specs/ci-cd-spec.md`.

## Directory-Specific Guides

- `.github/CLAUDE.md` — GitHub Actions workflow standards
- `devops/CLAUDE.md` — Infrastructure, Terraform, Kubernetes

## Code Standards

### Quality

- Do not leave obvious comments in code
- Follow 12-Factor App design principles where applicable

### Type Safety

- Never use `Any` type — always be explicit
- Use `| None` instead of `Optional` in Python
- All API models use Pydantic; strict TypeScript

### Patterns

- FastAPI for APIs (async), Celery workers (synchronous)
- Repository pattern, Pydantic models, official SDKs over raw HTTP
- Functional components, React hooks, TailwindCSS + Shadcn UI
- Group imports: external/internal, alphabetized

### Naming Conventions

**CRITICAL:** Use only safe, portable identifiers:

- Valid: `a-zA-Z0-9_` (alphanumeric + underscore)
- Invalid: hyphens, dots, special characters in identifiers
- Exception: File names can use kebab-case

### Commits

Conventional commits: `feat:`, `fix:`, `refac:`, etc.
Branch naming: `dev-###-short-description`

## Security

- Never hardcode secrets — use cloud-native secret managers + External Secrets Operator
- Pin versions for reproducibility (actions, base images, providers)

## Testing & Validation

- Test ALL workflow changes with `act` before implementation
- Validate ALL paths before use — never assume directory structure
- Run appropriate linters and fix all issues before completion

---

**Template Version**: 2.0
**Last Updated**: 2026-02-18
