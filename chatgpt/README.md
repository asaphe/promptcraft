# ChatGPT Instructions Implementation

## Overview

ChatGPT has character limits (~1500 chars per field) for custom instructions, requiring condensed versions of our comprehensive rules. This directory provides optimized ChatGPT instruction sets.

## Structure

```text
chatgpt/
├── global/
│   ├── general-instructions.md     # Universal development rules (condensed)
│   └── professional-instructions.md # DevOps-focused rules (condensed)
├── projects/
│   ├── infrastructure-project.md   # For DevOps/infrastructure work
│   ├── development-project.md      # For coding projects
│   └── mixed-project.md           # Full-stack projects
└── implementation-guide.md         # How to use these in ChatGPT
```

## Usage Strategy

### Global Custom Instructions

Use for your primary work focus - choose ONE:

- `global/general-instructions.md` - For mixed development work
- `global/professional-instructions.md` - For DevOps/infrastructure focus

### Project Instructions

Use ChatGPT Projects feature for specific contexts:

- Create projects with relevant project instruction files
- Switch between projects based on work context

## Character Limit Management

Each instruction file is designed to:

- Stay within ChatGPT's ~1500 character limits
- Reference the full rule repository for context
- Focus on the most critical rules for that context
- Use abbreviated but clear language

## Implementation Guide

1. **Copy relevant instruction content** from files below
2. **Paste into ChatGPT Settings > Custom Instructions** (for global)
3. **Create ChatGPT Projects** with project-specific instructions
4. **Reference this repository** when you need detailed guidance beyond the condensed instructions
