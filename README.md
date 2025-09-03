# AI Assistant Rules & Prompts

A comprehensive collection of rules, standards, and prompts designed to enhance AI assistant interactions for software development, DevOps, and infrastructure management.

## Overview

This repository contains carefully curated rules and standards that can be used with various AI assistants (ChatGPT, Claude, GitHub Copilot, Cursor, etc.) to ensure consistent, high-quality, and professional responses across different technical domains.

## Repository Structure

```raw
.
├── core/                          # Fundamental principles and protocols
│   ├── tone-and-style.md         # Communication style and formatting
│   ├── development-principles.md  # Core development protocols and quality standards
│   └── tool-safety.md            # Investigation and tool validation protocols
├── languages/                     # Language-specific development standards
│   ├── general-standards.md      # Cross-language principles and conventions
│   ├── typescript-javascript.md  # TypeScript/JavaScript specific guidelines
│   ├── python.md                 # Python development standards
│   ├── bash.md                   # Bash scripting best practices
│   └── java-go.md               # Java and Go development guidelines
├── infrastructure/               # Infrastructure and DevOps practices
│   ├── terraform.md             # Terraform standards and best practices
│   ├── kubernetes-helm.md       # Kubernetes and Helm guidelines
│   ├── docker.md               # Docker and containerization standards
│   ├── aws.md                  # AWS cloud services guidelines
│   └── ansible.md              # Ansible automation standards
├── workflows/                   # CI/CD and automation workflows
│   ├── github-actions.md       # GitHub Actions development protocol
│   └── ci-cd-patterns.md       # CI/CD patterns and deployment strategies
├── project/                     # Project-specific preferences and environment settings
│   └── environment-preferences.md # Environment setup and project-specific preferences
├── chatgpt/                     # ChatGPT-specific optimized instructions
│   ├── global/                  # Global custom instructions (choose one)
│   │   ├── general-instructions.md      # For general development work
│   │   └── professional-instructions.md # For DevOps/infrastructure focus
│   ├── projects/                # Project-specific instructions for ChatGPT Projects
│   │   ├── infrastructure-project.md    # Infrastructure/DevOps projects
│   │   ├── development-project.md       # Software development projects
│   │   └── mixed-project.md            # Full-stack/mixed projects
│   ├── implementation-guide.md  # How to use ChatGPT instructions effectively
│   └── README.md               # ChatGPT instruction system overview
├── mcp/                        # Model Context Protocol (MCP) configurations
│   ├── cursor/                 # Cursor-specific MCP configurations
│   │   ├── configuration.json  # Main MCP config template
│   │   └── setup-guide.md      # Step-by-step setup instructions
│   ├── tools/                  # Individual MCP tool documentation
│   │   ├── terraform-tools.md  # Terraform/HCP integration
│   │   ├── github-tools.md     # GitHub integration
│   │   └── filesystem-tools.md # Filesystem access tools
│   ├── security/               # Security and credential management
│   │   └── 1password-integration.md # 1Password CLI integration
│   └── README.md              # MCP overview and setup guide
└── quality/                    # Quality assurance and standards
    ├── code-quality.md         # Code quality and linting requirements
    ├── documentation.md        # Documentation standards and practices
    └── research-standards.md   # Research and information validation
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

**For Cursor with MCP:**

- Use `mcp/cursor/configuration.json` as template for MCP setup
- Follow `mcp/cursor/setup-guide.md` for complete installation
- Review `mcp/tools/` for specific tool configurations
- Implement `mcp/security/1password-integration.md` for secure credential management

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
- **Claude**: Include in system prompts or conversation context
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

This repository is intended for public use and learning. Feel free to adapt, modify, and extend these rules for your own needs.

## Acknowledgments

These rules represent the distillation of experience across multiple technology stacks, development methodologies, and organizational contexts. They emphasize practical solutions, technical rigor, and professional communication standards that enhance AI assistant interactions for technical work.
