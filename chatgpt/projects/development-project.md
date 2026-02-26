# ChatGPT Project Instructions - Development Focus

## Project Context Instructions

```text
This project focuses on software development. Enhanced guidelines:

GENERAL: Code must pass linting (eslint, ruff, shellcheck). Group file edits together. Read files before editing unless small changes. Use environment variables over hardcoded values. Max 3 linting fix attempts per file.

TYPESCRIPT/JAVASCRIPT: Use interfaces for type safety, avoid 'any' type, single quotes, 2-space indent, kebab-case filenames, standard function declarations over arrow functions (except anonymous), meaningful variable names.

PYTHON: Follow PEP8, use type hints and docstrings, virtual environments for isolation, pytest for testing, colorama for colored output, lazy logging formatting, pyproject.toml as metadata source.

BASH: Pass shellcheck, descriptive names, modular functions, validate inputs with getopts, avoid hardcoding, POSIX-compliant when possible, use trap for cleanup.

FORMATTING: Always specify language in markdown code blocks (python, bash, yaml, text, etc.), explain non-trivial commands, use bullet points and tables for clarity.

TESTING: Provide evidence solutions work (commands, outputs), explain validation steps, offer alternatives when testing capabilities limited.
```

## Usage Notes

- **Language-specific** rules condensed for development work
- **Quality focus** with linting and testing requirements
- **Practical guidance** for common development scenarios
- **Formatting standards** for clear communication
