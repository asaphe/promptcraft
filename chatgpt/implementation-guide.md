# ChatGPT Implementation Guide

## How to Use These Instructions

### Step 1: Choose Your Global Instructions

**Pick ONE based on your primary work:**

- **General Development**: Use `global/general-instructions.md` if you work across multiple technologies
- **DevOps/Infrastructure Focus**: Use `global/professional-instructions.md` if primarily doing infrastructure work

### Step 2: Set Up Global Custom Instructions

1. Go to **ChatGPT Settings > Custom instructions**
2. Copy the text from your chosen global instruction file:
   - First text block → "What would you like ChatGPT to know about you?"
   - Second text block → "How would you like ChatGPT to respond?"
3. Save the settings

### Step 3: Create Project-Specific Contexts

**For specific projects, use ChatGPT Projects:**

1. Create a **New Project** in ChatGPT
2. Copy content from relevant project instruction file:
   - `projects/infrastructure-project.md` - For DevOps/infrastructure work
   - `projects/development-project.md` - For coding projects
   - `projects/mixed-project.md` - For full-stack projects
3. Paste into the project's instructions field

### Step 4: Reference Full Rules When Needed

In conversations, you can say:
> "For detailed standards, reference the promptcraft repository rules"

This reminds ChatGPT to consider the comprehensive rules beyond the condensed instructions.

## Best Practices

### Character Limit Management

- **Global instructions**: ~1500 characters per field (these are optimized)
- **Project instructions**: Usually more flexible space
- **Monitor usage**: ChatGPT will warn if approaching limits

### Context Switching

- **Use Projects** for different types of work
- **Keep global instructions** for your most common work type
- **Switch projects** based on current context

### Iteration and Improvement

- **Test instructions** in real conversations
- **Adjust based** on ChatGPT's responses
- **Update when** your work focus changes

## Troubleshooting

### If Instructions Are Too Long

1. Remove less critical details
2. Use abbreviations (e.g., "TS/JS" instead of "TypeScript/JavaScript")
3. Focus on most impactful rules for your work

### If ChatGPT Doesn't Follow Instructions

1. Remind it about the instructions in conversation
2. Reference specific rules: "Following our code quality standards..."
3. Check if instructions are too vague or conflicting

### For Complex Projects

- Combine project instructions with conversation-specific reminders
- Reference the full rule repository for detailed guidance
- Use conversation memory to reinforce key requirements

## Example Usage Flow

```text
1. Set global instructions (one-time setup)
2. Create project for "Infrastructure Migration" using infrastructure-project.md
3. Start conversation: "I need to set up Terraform for AWS infrastructure"
4. ChatGPT applies both global + project context
5. For detailed guidance: "Reference our Terraform standards from promptcraft"
```

This approach maximizes ChatGPT's effectiveness within its instruction system constraints while maintaining connection to your comprehensive rule repository.
