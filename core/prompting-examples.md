# Prompting Examples

Concrete input/output examples demonstrating effective prompting patterns. These are "multishot" examples — showing Claude what good looks like is more effective than describing it.

## Why Examples Matter

Claude responds better to demonstrated patterns than to abstract rules. Three concrete examples teach more than a page of instructions. When designing prompts, lead with examples of the desired output format and quality level.

## XML Structuring for Complex Prompts

Use XML tags to create clear boundaries between different parts of a prompt. Claude is trained to recognize XML structure and uses it to parse context reliably.

### Basic Structure

```xml
<context>
You are reviewing a pull request in a Python monorepo with FastAPI services.
The team uses conventional commits and requires type annotations on all public functions.
</context>

<instructions>
Review the diff below. Flag:
1. Missing type annotations on public functions
2. Security issues (SQL injection, unvalidated input, secrets in code)
3. Breaking API changes without a migration path

Do NOT flag: style preferences, import ordering, docstring format.
</instructions>

<diff>
{paste diff here}
</diff>
```

### When to Use XML Tags

| Situation | Use XML? | Example |
|-----------|----------|---------|
| Separating context from instructions | Yes | `<context>`, `<instructions>` |
| Providing examples | Yes | `<example>`, `<good-example>`, `<bad-example>` |
| Passing structured data | Yes | `<diff>`, `<error-log>`, `<config>` |
| Simple single-purpose prompts | No | "Fix the typo in line 42" |

### Nesting for Multi-Section Prompts

```xml
<task>
  <role>You are a Terraform module reviewer.</role>

  <standards>
    - All resources must have tags: Name, Environment, ManagedBy
    - Use `for_each` over `count` for named resources
    - Pin provider versions with `~>` constraints
  </standards>

  <examples>
    <good-example>
    resource "aws_s3_bucket" "data" {
      for_each = var.buckets
      bucket   = "${var.env}-${each.key}"
      tags = {
        Name        = each.key
        Environment = var.env
        ManagedBy   = "terraform"
      }
    }
    </good-example>

    <bad-example>
    resource "aws_s3_bucket" "data" {
      count  = length(var.bucket_names)
      bucket = var.bucket_names[count.index]
    }
    </bad-example>
  </examples>

  <review-target>
    {paste module code here}
  </review-target>
</task>
```

## Multishot Prompting Patterns

### Pattern 1: Input/Output Pairs

Show 2-3 examples of the transformation you want, then provide the real input:

```text
Convert these error messages to user-friendly notifications.

Input: "ConnectionRefusedError: [Errno 111] Connection refused"
Output: "Unable to reach the server. Please check your connection and try again."

Input: "KeyError: 'user_id'"
Output: "Something went wrong processing your request. Please try again or contact support."

Input: "PermissionError: [Errno 13] Permission denied: '/var/log/app.log'"
Output:
```

Claude will follow the established pattern for the final input.

### Pattern 2: Before/After Code Examples

Show the transformation pattern, then provide the target:

```text
Refactor these functions to use early returns instead of nested conditionals.

Before:
def process_order(order):
    if order is not None:
        if order.status == "pending":
            if order.items:
                return fulfill(order)
            else:
                return Error("No items")
        else:
            return Error("Not pending")
    else:
        return Error("No order")

After:
def process_order(order):
    if order is None:
        return Error("No order")
    if order.status != "pending":
        return Error("Not pending")
    if not order.items:
        return Error("No items")
    return fulfill(order)

Now refactor this function:
def validate_user(user):
    if user is not None:
        if user.email:
            if "@" in user.email:
                if user.age >= 18:
                    return True
                else:
                    return False
            else:
                return False
        else:
            return False
    else:
        return False
```

### Pattern 3: Classification with Examples

Teach a classification scheme by example:

```text
Classify these git commits by type.

Commit: "add retry logic to S3 upload handler"
Type: feat

Commit: "correct off-by-one in pagination offset"
Type: fix

Commit: "extract database config to separate module"
Type: refactor

Commit: "update API reference for /users endpoint"
Type: docs

Commit: "bump fastapi from 0.109 to 0.115"
Type: chore

Now classify:
Commit: "handle timeout in webhook delivery"
Type:
```

## Prompt Chaining

Break complex tasks into sequential prompts where each step's output feeds the next. This produces better results than one massive prompt.

### The Pattern

```text
Step 1 (Explore):  "Read the auth module. List every public function, its
                    parameters, and return type. Do NOT suggest changes yet."

Step 2 (Analyze):  "Given this inventory, identify functions that: (a) lack
                    input validation, (b) don't handle the unauthenticated
                    case, (c) have inconsistent error return types."

Step 3 (Plan):     "For each finding, propose a fix. Show the function
                    signature before and after. Do NOT write implementation."

Step 4 (Implement): "Implement the fixes from the approved plan, one function
                     at a time. Run tests after each change."
```

### Why Chaining Works

| Single Prompt | Chained Prompts |
|---------------|-----------------|
| Claude must hold the entire task in working memory | Each step has focused context |
| Errors compound — a wrong assumption in step 1 derails step 4 | You can correct course between steps |
| Hard to review intermediate reasoning | Each step produces reviewable output |
| Context fills up on large codebases | Each step can start with clean context |

### Common Chains

**Bug Investigation:**

1. "Reproduce the bug — find the failing test or write one"
2. "Trace the execution path from the failing assertion back to the root cause"
3. "Propose a fix and explain why it addresses the root cause"
4. "Implement and verify the fix passes"

**Feature Implementation:**

1. "Explore the codebase to understand the existing patterns for similar features"
2. "Write a plan: data model, API endpoints, UI components, test cases"
3. "Implement the data model and backend (with tests)"
4. "Implement the frontend (with tests)"
5. "Integration test the full flow"

**Code Review:**

1. "Summarize what this PR changes and why (based on commits and diff)"
2. "Check for security issues, missing error handling, and breaking changes"
3. "Verify test coverage for the changed code paths"
4. "Write the review summary with findings ranked by severity"

## Combining Patterns

The strongest prompts combine XML structure, examples, and chaining:

```xml
<context>
We're migrating from REST to GraphQL. The codebase has 15 REST endpoints
in src/api/routes/. Each needs a corresponding GraphQL resolver.
</context>

<example>
REST endpoint: GET /api/users/:id
GraphQL resolver:
type Query {
  user(id: ID!): User
}

const resolvers = {
  Query: {
    user: (_, { id }) => userService.getById(id),
  },
}
</example>

<instructions>
Phase 1: List all REST endpoints in src/api/routes/ with their HTTP method,
path, and handler function. Output as a table. Do not write any code yet.
</instructions>
```

## Related Resources

- [Tone and Style](tone-and-style.md) — Communication standards that apply to all prompts
- [Claude Best Practices](../claude/claude-best-practices.md) — The Explore/Plan/Code/Commit workflow
- [Agent Design Guide](../claude/agents/agent-design-guide.md) — Prompt design for agent system prompts
