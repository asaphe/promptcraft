#!/usr/bin/env python3
"""Calculate Claude Code session cost from a JSONL session file."""
import json, sys, os, glob, argparse

# cache_creation is the 5m-TTL rate (1.25x input); the 1h TTL (2x input) is not modelled.
PRICING = {
    "claude-fable-5-1":   {"input": 10.00, "cache_creation": 12.50, "cache_read": 0.25, "output": 50.00},
    "claude-fable-5":     {"input": 10.00, "cache_creation": 12.50, "cache_read": 1.00, "output": 50.00},
    "claude-opus-5-5":    {"input": 4.00,  "cache_creation": 5.00,  "cache_read": 0.20, "output": 20.00},
    "claude-opus-5":      {"input": 5.00,  "cache_creation": 6.25,  "cache_read": 0.50, "output": 25.00},
    "claude-opus-4-8":    {"input": 5.00,  "cache_creation": 6.25,  "cache_read": 0.50, "output": 25.00},
    "claude-opus-4-7":    {"input": 5.00,  "cache_creation": 6.25,  "cache_read": 0.50, "output": 25.00},
    "claude-opus-4-6":    {"input": 5.00,  "cache_creation": 6.25,  "cache_read": 0.50, "output": 25.00},
    "claude-sonnet-5-5":  {"input": 2.00,  "cache_creation": 2.50,  "cache_read": 0.20, "output": 10.00},
    "claude-sonnet-5":    {"input": 2.00,  "cache_creation": 2.50,  "cache_read": 0.20, "output": 10.00},
    "claude-sonnet-4-6":  {"input": 3.00,  "cache_creation": 3.75,  "cache_read": 0.30, "output": 15.00},
    "claude-haiku-4-5":   {"input": 1.00,  "cache_creation": 1.25,  "cache_read": 0.10, "output": 5.00},
}
DEFAULT_PRICING = PRICING["claude-opus-5-5"]


def _find_usage(d):
    if isinstance(d, dict):
        if "output_tokens" in d and "input_tokens" in d:
            return d
        for v in d.values():
            r = _find_usage(v)
            if r:
                return r
    elif isinstance(d, list):
        for v in d:
            r = _find_usage(v)
            if r:
                return r


def calc_cost(jsonl_path):
    totals = {"input": 0, "cache_creation": 0, "cache_read": 0, "output": 0}
    model = None

    with open(jsonl_path) as f:
        for line in f:
            if '"output_tokens"' not in line:
                continue
            try:
                obj = json.loads(line)
                if not model:
                    m = (obj.get("message", {}) or {}).get("model", "") or obj.get("model", "")
                    if m:
                        model = m
                u = _find_usage(obj)
                if u:
                    totals["input"]          += u.get("input_tokens", 0)
                    totals["cache_creation"] += u.get("cache_creation_input_tokens", 0)
                    totals["cache_read"]     += u.get("cache_read_input_tokens", 0)
                    totals["output"]         += u.get("output_tokens", 0)
            except Exception:
                pass

    prices = DEFAULT_PRICING
    # longest key first: "claude-opus-5" is a substring of "claude-opus-5-5"
    for key, p in sorted(PRICING.items(), key=lambda kv: -len(kv[0])):
        if model and key in model:
            prices = p
            break

    M = 1_000_000
    costs = {k: totals[k] * prices[k] / M for k in prices}
    total = sum(costs.values())
    return totals, costs, total, model


def find_latest_jsonl(project_dir):
    files = [f for f in glob.glob(os.path.join(project_dir, "*.jsonl"))
             if not f.endswith("sessions-index.json")]
    return max(files, key=os.path.getmtime) if files else None


def cwd_to_project_dir(cwd):
    """Convert a filesystem path to Claude Code's project dir name."""
    slug = cwd.replace("/", "-").replace(".", "-")
    return os.path.join(os.path.expanduser("~/.claude/projects"), slug)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?", help="Session JSONL file or working directory (default: cwd)")
    ap.add_argument("--json", action="store_true", help="Emit JSON to stdout for machine parsing")
    args = ap.parse_args()

    path = args.path or os.getcwd()

    if os.path.isfile(path):
        jsonl = path
    else:
        proj_dir = cwd_to_project_dir(path)
        if not os.path.isdir(proj_dir):
            print(f"No Claude project found for: {path}", file=sys.stderr)
            sys.exit(1)
        jsonl = find_latest_jsonl(proj_dir)
        if not jsonl:
            print(f"No session files found in: {proj_dir}", file=sys.stderr)
            sys.exit(1)

    totals, costs, total, model = calc_cost(jsonl)

    model_str = f" ({model})" if model else ""
    print(f"Session cost{model_str}: \033[1m${total:.4f}\033[0m")
    print(f"  Input:        {totals['input']:>12,}  ${costs['input']:.4f}")
    print(f"  Cache write:  {totals['cache_creation']:>12,}  ${costs['cache_creation']:.4f}")
    print(f"  Cache read:   {totals['cache_read']:>12,}  ${costs['cache_read']:.4f}")
    print(f"  Output:       {totals['output']:>12,}  ${costs['output']:.4f}")

    if args.json:
        data = {
            "total_cost": round(total, 6),
            "input_tokens": totals["input"],
            "cache_creation_tokens": totals["cache_creation"],
            "cache_read_tokens": totals["cache_read"],
            "output_tokens": totals["output"],
            "model": model or "unknown",
        }
        print(json.dumps(data))


if __name__ == "__main__":
    main()
