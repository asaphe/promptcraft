# AI Assistant Rules & Prompts

A comprehensive collection of rules, standards, and prompts designed to enhance AI assistant interactions for software development, DevOps, and infrastructure management.

## Overview

This repository contains carefully curated rules and standards that can be used with various AI assistants (ChatGPT, Claude, GitHub Copilot, Cursor, etc.) to ensure consistent, high-quality, and professional responses across different technical domains.

## Repository Structure

```raw
.
├── core/                           # Fundamental principles and protocols
│   ├── tone-and-style.md          # Communication style, formatting, XML structuring
│   ├── development-principles.md   # Core development protocols and quality standards
│   ├── tool-safety.md             # Investigation, tool validation, verify-before-asserting
│   ├── agent-design-patterns.md   # AI agent design, splitting, cross-agent deferral
│   ├── operational-safety-patterns.md  # Session safety, approval interpretation, privacy scanning
│   └── prompting-examples.md      # Multishot examples, XML structuring, prompt chaining demos
├── languages/                      # Language-specific development standards
│   ├── general-standards.md       # Cross-language principles and conventions
│   ├── typescript-javascript.md   # TypeScript/JavaScript specific guidelines
│   ├── python.md                  # Python development standards
│   ├── bash.md                    # Bash scripting best practices
│   └── java-go.md                 # Java and Go development guidelines
├── infrastructure/                 # Infrastructure and DevOps practices
│   ├── terraform.md               # Terraform standards, state management, migration patterns
│   ├── kubernetes-helm.md         # Kubernetes and Helm guidelines
│   ├── docker.md                  # Docker and containerization standards
│   ├── aws.md                     # AWS cloud services guidelines
│   └── ansible.md                 # Ansible automation standards
├── workflows/                      # CI/CD and automation workflows
│   ├── github-actions.md          # GitHub Actions development protocol
│   └── ci-cd-patterns.md         # CI/CD patterns and deployment strategies
├── project/                        # Project-specific preferences and environment settings
│   └── environment-preferences.md # Environment setup and project-specific preferences
├── claude/                         # Claude Code documentation, agents, skills, and protocols
│   ├── agents/                    # Subagent design guides and templates
│   │   ├── agent-design-guide.md  # How to design Claude Code subagents
│   │   ├── agent-template.md      # Ready-to-use agent template
│   │   └── review-agent-trio.md   # Specialized reviewer agents for PR review
│   ├── rules/                     # Operational rules system
│   │   └── operational-rules-guide.md  # How to design and maintain auto-loaded rules
│   ├── skills/                    # Skill (slash command) design
│   │   ├── skill-design-guide.md  # How to design Claude Code skills
│   │   └── skill-template.md      # Ready-to-use skill template
│   ├── scaffolding/               # Complete example .claude/ directory (copy & customize)
│   │   ├── .claude/               # Agents, rules, skills, docs, specs examples
│   │   ├── global-claude-md-example.md  # Example ~/.claude/CLAUDE.md
│   │   └── README.md             # Scaffolding usage instructions
│   ├── project-templates/         # Repository documentation templates
│   │   ├── codebase-guide-template.md
│   │   ├── devops-infrastructure-guide.md
│   │   ├── github-actions-guide.md
│   │   └── navigation-hub.md
│   ├── specs/                     # RFC-style specifications
│   │   └── ci-cd-specification.md
│   ├── claude-best-practices.md   # End-to-end best practices, prompt chaining, workflow
│   ├── hooks-guide.md             # Hook design patterns (PreToolUse, PostToolUse, Stop)
│   ├── settings-json-guide.md     # Permissions, env vars, layering, wildcards
│   ├── github-actions-integration.md  # Claude Code in CI/CD via claude-code-action
│   ├── learning-system-guide.md   # Automated learning capture with hooks and plugins
│   ├── global-claude-md-guide.md  # How to design personal ~/.claude/CLAUDE.md
│   ├── portability-guide.md       # Dotfiles, symlinks, backups, Desktop vs Code config
│   ├── mcp-management-guide.md    # MCP server lifecycle: add, remove, team connectors, cloud MCP hygiene
│   ├── session-analytics-guide.md # Mining session history for tool call waste patterns
│   ├── pr-review-protocol.md      # Structured PR review routing and posting
│   ├── CLAUDE.md                  # Example project CLAUDE.md
│   └── README.md                 # Claude section overview
├── chatgpt/                        # ChatGPT-specific optimized instructions
│   ├── global/                    # Global custom instructions (choose one)
│   │   ├── general-instructions.md      # For general development work
│   │   └── professional-instructions.md # For DevOps/infrastructure focus
│   ├── projects/                  # Project-specific instructions for ChatGPT Projects
│   │   ├── infrastructure-project.md    # Infrastructure/DevOps projects
│   │   ├── development-project.md       # Software development projects
│   │   └── mixed-project.md             # Full-stack/mixed projects
│   ├── implementation-guide.md    # How to use ChatGPT instructions effectively
│   └── README.md                  # ChatGPT instruction system overview
├── cursor/                         # Cursor IDE configurations and rules
│   ├── mcp/                       # MCP configurations for Cursor
│   │   ├── configuration.json     # Main MCP config template
│   │   ├── setup-guide.md        # Step-by-step setup instructions
│   │   ├── README.md             # MCP overview
│   │   ├── tools/                 # Individual MCP tool documentation
│   │   │   ├── terraform-tools.md
│   │   │   ├── github-tools.md
│   │   │   └── filesystem-tools.md
│   │   └── security/              # Security and credential management
│   │       └── 1password-integration.md
│   ├── mdc-rules/                 # MDC format rules for Cursor IDE
│   │   ├── documentation/        # Documentation rules
│   │   ├── formatting/           # Code formatting rules
│   │   ├── kubernetes/           # Kubernetes/Helm rules
│   │   ├── language-specific/    # Language-specific rules
│   │   ├── naming/               # Naming convention rules
│   │   ├── structure/            # Project structure rules
│   │   ├── terraform/            # Terraform rules
│   │   └── README.md
│   ├── user-rules/                # User rules for Cursor
│   ├── multi-tool-coexistence.md  # Running multiple AI tools together
│   └── README.md                  # Cursor section overview
├── cursor-recovery/                # Cursor data recovery tools
│   └── sync_conversations_to_workspace.py
├── examples/                       # Runnable examples (hooks, workflows, configs)
├── quality/                        # Quality assurance and standards
│   ├── code-quality.md            # Code quality and linting requirements
│   ├── documentation.md           # Documentation standards and practices
│   └── research-standards.md      # Research and information validation
├── .github/                        # GitHub templates and CI
│   ├── workflows/lint.yml         # Markdownlint CI
│   ├── ISSUE_TEMPLATE/            # Bug report and feature request templates
│   └── PULL_REQUEST_TEMPLATE.md   # PR template
├── CONTRIBUTING.md                 # How to contribute
└── LICENSE                         # CC BY 4.0
```

## Important Usage Notes

### AI Assistant Capabilities

⚠️ **Capability Disclaimer**: Some rules assume capabilities (file system access, command execution, testing tools) that may not be available to all AI assistants. When these capabilities are limited:

- Assistants should explain the intended process rather than simulate results
- Provide step-by-step instructions for users to execute
- Offer alternative approaches within available capabilities
- Be transparent about limitations

### Rule Application Context

- **Universal Rules** (core/, quality/): Apply in all interactions
- **Language-Specific Rules** (languages/): Apply when working with specific technologies
- **Project-Specific Rules** (project/): Apply only when explicitly indicated by user context
- **Infrastructure Rules**: Apply when working with DevOps/infrastructure tasks

If uncertain about which context applies, ask for clarification rather than assume.

## Quick Start

### ⭐ Fastest path: production-ready global CLAUDE.md

If you use **Claude Code** and work in DevOps or infrastructure, the single highest-leverage thing in this repo is [`examples/config/global-CLAUDE.md`](examples/config/global-CLAUDE.md).

It's a ~250-line `~/.claude/CLAUDE.md` derived from a production DevOps setup — covering behavioral guardrails, operational safety protocols, review quality standards, AWS/K8s rules, git discipline, and CI/CD gotchas. It loads into every Claude Code session across all your projects.

**To use it:**

```bash
cp examples/config/global-CLAUDE.md ~/.claude/CLAUDE.md
```

Remove sections that don't apply to your stack. The behavioral sections (Agent Behavioral Constraints, Safety, Review Quality, Bash Command Patterns) need no customization and are universally useful.

---

### For AI Assistant Configuration

1. **Choose relevant sections** based on your work focus:
   - Use `core/` for fundamental principles that apply to all interactions
   - Select from `languages/` based on your programming languages
   - Include `infrastructure/` if you work with cloud/DevOps
   - Add `workflows/` for CI/CD and automation work
   - Include `quality/` for comprehensive quality standards

2. **Combine rules** by copying content from multiple files into your AI assistant's custom instructions or system prompts

3. **Customize as needed** - these are templates that can be adapted to your specific needs and preferences

### Example Usage Patterns

**For Full-Stack Development:**

- `core/` (all files)
- `languages/typescript-javascript.md`
- `languages/python.md`
- `quality/code-quality.md`
- `quality/documentation.md`

**For DevOps/Infrastructure:**

- `core/` (all files)
- `infrastructure/` (relevant files)
- `workflows/` (all files)
- `quality/` (all files)

**For General Development:**

- `core/tone-and-style.md`
- `core/development-principles.md`
- `languages/general-standards.md`
- `quality/code-quality.md`

**For Project-Specific Workflows:**

- `core/` (selected files)
- `project/environment-preferences.md`
- Relevant sections from `infrastructure/` and `workflows/`

**For ChatGPT Specifically:**

- Use `chatgpt/global/` for custom instructions (character-optimized)
- Use `chatgpt/projects/` for ChatGPT Projects feature
- Follow `chatgpt/implementation-guide.md` for setup

**For Claude Code:**

- **Global config (DevOps/infra):** `examples/config/global-CLAUDE.md` → `~/.claude/CLAUDE.md` ⭐
- End-to-end workflow guide: `claude/claude-best-practices.md`
- Runtime configuration: `claude/hooks-guide.md` and `claude/settings-json-guide.md`
- CI/CD automation: `claude/github-actions-integration.md`
- Starter project template: `claude/scaffolding/`

**For Cursor with MCP:**

- Use `cursor/mcp/configuration.json` as template for MCP setup
- Follow `cursor/mcp/setup-guide.md` for complete installation
- Review `cursor/mcp/tools/` for specific tool configurations
- Implement `cursor/mcp/security/1password-integration.md` for secure credential management

## Key Features

### Technical Excellence

- **Quality-First Approach**: All code must pass appropriate linting and follow best practices
- **Evidence-Based Solutions**: Emphasis on tested, verified solutions rather than assumptions
- **Current Information**: Focus on up-to-date tools, versions, and practices

### Professional Communication

- **Clear, Direct Style**: Concise, actionable guidance without unnecessary verbosity
- **Senior-Level Technical Depth**: Comprehensive coverage appropriate for experienced professionals
- **Thought-Provoking Analysis**: Deep-dive answers suitable for DevOps Tech Lead / Head of DevOps level
- **Alternative Solutions**: Multiple approaches with trade-offs analysis, including edge cases
- **User-Focused**: Solutions designed to work immediately with minimal debugging

### Comprehensive Coverage

- **Multi-Language Support**: Standards for Python, TypeScript/JavaScript, Bash, Java, Go
- **Infrastructure Focus**: Detailed guidelines for Terraform, Kubernetes, Docker, AWS
- **DevOps Integration**: CI/CD patterns, automation, and workflow optimization
- **AI Tool Integration**: Optimized instructions for ChatGPT, MCP configurations for Cursor
- **Security Patterns**: Secure credential management and development workflows

## Customization Guidelines

### Adapting to Your Environment

- Replace generic examples with your specific tool versions
- Adjust naming conventions to match your organization's standards
- Add or remove sections based on your technology stack

### Maintaining Currency

- Regularly update version references and best practices
- Verify that linked resources and documentation remain current
- Adapt standards as new tools and practices emerge

## Usage Tips

### For Maximum Effectiveness

1. **Start Small**: Begin with core principles, then add specialized sections
2. **Be Specific**: Include exact versions and tool requirements when relevant
3. **Iterate**: Refine rules based on actual usage and results
4. **Combine Intelligently**: Some sections may conflict - choose what fits your context

### Integration with AI Tools

- **ChatGPT**: Use the optimized instructions in `chatgpt/` directory - see `chatgpt/implementation-guide.md` for setup
- **Claude Code**: Use `claude/` directory for comprehensive guides — see `claude/claude-best-practices.md` for the starting point
- **Cursor**: Add to workspace rules or project-specific configurations, plus MCP integration via `mcp/cursor/` for advanced tool access
- **GitHub Copilot**: Include as comments in your codebase or IDE settings

## Contributing

This repository represents battle-tested standards from real-world software development and DevOps work. While these rules are specific to particular workflows and preferences, they can serve as a starting point for your own customized rule sets.

### Best Practices for Your Own Rules

- Document the reasoning behind each standard
- Include examples where helpful
- Test rules with actual AI interactions
- Keep rules current with evolving tools and practices
- Balance comprehensiveness with usability

## License

This repository is licensed under [CC BY 4.0](LICENSE). You are free to share and adapt the content for any purpose, including commercially, with attribution.

## Acknowledgments

These rules represent the distillation of experience across multiple technology stacks, development methodologies, and organizational contexts. They emphasize practical solutions, technical rigor, and professional communication standards that enhance AI assistant interactions for technical work.
