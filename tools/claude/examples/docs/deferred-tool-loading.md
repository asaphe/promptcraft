# Deferred Tool-Schema Loading

Pay full schema-token cost only for the tools a session actually uses — the rest stay name-only until explicitly loaded.

A session wired to many MCP servers can carry 10,000–50,000 tokens of tool definitions it never calls (see [`mcp-management-guide.md`](../../guides/mcp-management-guide.md) for the per-server numbers). Disabling unused servers reclaims that, but loses the capability entirely. Deferred loading is the middle path: a small core toolset loads with full schemas at session start; every other tool is listed *by name only*, schema-less and uncallable, until an explicit "load these schemas" call fetches it. Standing cost per deferred tool drops to roughly one line.

## The pattern

- **Core set eagerly loaded** — file ops, shell, search: the tools every session touches.
- **Everything else deferred** — visible in a name index, so the agent knows the capability *exists*, just not its parameters.
- **Explicit load call** — a search/select tool that takes tool names or keywords and returns full schemas, after which the tools are callable normally.

## Batch the load — one call, not N

The single biggest implementation mistake is loading tools one at a time as the task trips over them. Two costs stack:

1. **Round trips** — each load call is a full model turn.
2. **Cache invalidation** — the tool manifest sits at the top of the prompt; every change to it invalidates the entire cached prefix, and the next call re-pays a cold context write. Five incremental loads mid-task = five cold re-reads of the whole conversation.

So: at the start of a task, predict every deferred tool the task will *plausibly* need — the browser set for a UI task, the messaging set for a notification flow — and fetch them in **one** call with a comma-separated select list. Only issue a second load if the task genuinely surprises you. Front-load; never toggle mid-task.

```text
load-tools "select:browser_navigate,browser_read_page,browser_screenshot,form_input"
```

## Don't declare a capability missing without searching first

With most of the tool surface deferred, the schemas in context are no longer the full capability inventory. Before telling the user "I don't have a tool for that", search the deferred index — the tool may be one load call away. This failure mode is silent and looks like a model limitation to the user; make the search a reflex.

## Relationship to disabling servers

| Approach | Standing cost | Capability |
|---|---|---|
| Server enabled, schemas eager | Full schema tokens every session | Immediate |
| Server enabled, schemas deferred | ~1 name line per tool | One load call away |
| Server disabled | Zero | Gone until re-enabled and restarted |

Disable what you genuinely never use; defer what you use rarely; eagerly load only what you use in most sessions.
