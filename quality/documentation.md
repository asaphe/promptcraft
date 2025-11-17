# Documentation Standards

## Documentation Requirements

### Project-Specific Standards

- Use single '#' for top-level Markdown headers in projects
- Provide context and reasoning for technical decisions
- Include recovery/rollback information when relevant
- Use markdown format for summaries (easy copy/paste)
- Keep technical summaries dry, concise, human-readable
- Avoid hyperbole ("Revolutionary", "Amazing", etc.)

### Markdown Formatting Standards

- Markdown code blocks should always have the language or type specified
- Use appropriate language identifiers: `python`, `bash`, `yaml`, `json`, `terraform`, `dockerfile`, etc.
- Use `text` for plain text content or `raw` for unformatted content when no specific language applies
- Never use empty code fences without language specification (avoid ```)
- Never add `---` separator when writing markdown files
- When writing markdown files (or any language), consult the official best-practice and linters to make sure you are correct when writing code

### Version Documentation

- Always pin versions in workflows and specify why
- Pin ALL actions including standard actions like checkout
- Include version comments inline: `uses: action@hash # v4.2.2`
- Justify version choices when deviating from latest
- Specify exact versions being used with short description about WHY

### Technical Context

- Document working directory relationships and path logic
- Explain reasoning behind technical decisions
- State assumptions explicitly for user validation
- Include both what was done AND why it was chosen
- Provide alternative approaches considered when relevant

## Communication Standards

### Before Implementation

- Present solutions and get agreement before writing code
- Discuss approach and options first
- Get explicit approval: "Should I implement this?"
- Never assume user wants immediate implementation

### During Development

- Show validation steps taken
- Provide evidence that solutions work (commands, outputs, testing results)
- Document any assumptions made during development
- Explain trade-offs and decisions made

### After Completion

- Summarize what was implemented and why
- Provide recovery information if applicable
- Document any follow-up actions needed
- Include references to sources used

## Quality Assurance

### Verification Protocol

- Verify everything exists before referencing it
- Test all commands and paths before suggesting them
- Validate all information against current sources
- Provide proof of correctness for all technical suggestions

### User Experience

- Focus on solutions that work immediately for the user
- Minimize debugging burden on the user
- Prioritize user's time and productivity
- Remember: user frustration comes from having to debug assistant mistakes

## Documentation Types

### Code Documentation

- Use clear, concise comments where necessary
- Document complex algorithms and business logic
- Include examples for public APIs
- Use appropriate documentation generation tools

### Project Documentation

- Include comprehensive README files
- ALWAYS write concise, human-readable, step-by-step README files WHEN you write README files
- Document setup and installation procedures
- Provide usage examples and common patterns
- Include troubleshooting guides
- Markdown files which are plan, summaries or anything other than a README that you generate to show how something is going to work should be under the root path and you should create OR choose a directory for them - `documentation`

### Architecture Documentation

- Document system architecture and design decisions
- Include diagrams where helpful
- Explain integration points and dependencies
- Document security considerations and trade-offs

**Core Principle**: Accurate, well-researched, clearly documented solutions that work the first time and require minimal user debugging.
