# General Language Standards

## Basic Principles

- Use English for all code, documentation, and comments
- Prioritize modular, reusable, and scalable code
- Avoid hard-coded values; use environment variables or configuration files
- Apply Infrastructure-as-Code (IaC) principles where possible
- Always consider the principle of least privilege in access and permissions

## Naming Conventions

- **camelCase**: for variables, functions, and method names
- **PascalCase**: for class names
- **snake_case**: for file names and directory structures
- **UPPER_CASE**: for environment variables

## Environment Awareness

### macOS/Unix Systems

- Default to zsh on macOS environments
- Use appropriate shebang lines (`#!/bin/bash` vs `#!/bin/zsh`)
- Test commands in actual shell environment when possible
- Consider cross-shell compatibility for scripts

### Code Execution Requirements

It is *EXTREMELY* important that generated code can be run immediately by the user:

1. Always group together edits to the same file in a single edit instead of multiple
2. If creating a codebase from scratch, create appropriate dependency management files with package versions and a helpful README
3. If building a web app from scratch, give it a beautiful and modern UI with best UX practices
4. NEVER generate extremely long hashes or non-textual code such as binary
5. Unless appending small edits to a file or creating new files, MUST read the contents before editing
6. If linter errors are introduced, fix them if clear how to (max 3 attempts per file)

## Error Handling Standards

- Best-practice error handling should be included in scripts by default
- Solutions should be robust and production-grade but not convoluted
- Code must be clean, efficient, and follow best practices for the given language
- Avoid inline comments directly in code; prefer explanations after code blocks using bullet points

## Testing & Validation

- Before providing any executable code, test it to confirm it works as expected
- If testing is not possible, provide clear steps for user testing with expected results and potential failure cases
- Do not assume something works—verify it first
- If uncertain about any part of a response, explicitly say so and explain why

## Code Quality Requirements

- Code complexity: Solutions should be robust and production-grade but not convoluted
- Code quality: Clean, efficient, following best practices for the given language
- Documentation: Avoid adding comments directly in code; use bullet point explanations after code blocks
