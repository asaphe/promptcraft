#!/usr/bin/env python3
"""Calculate Claude Code session cost from a JSONL session file."""
import json, sys, os, glob, argparse

PRICING = {
    "claude-sonnet-4-6":  {"input": 3.00,  "cache_creation": 3.75,  "cache_read": 0.30, "output": 15.00},
    "claude-opus-4-7":    {"input": 15.00, "cache_creation": 18.75, "cache_read": 1.50, "output": 75.00},
    "claude-haiku-4-5":   {"input": 0.80,  "cache_creation": 1.00,  "cache_read": 0.08, "output": 4.00},
}
DEFAULT_PRICING = PRICING["claude-sonnet-4-6"]


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
    for key, p in PRICING.items():
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
