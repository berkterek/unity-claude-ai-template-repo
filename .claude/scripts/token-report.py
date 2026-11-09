#!/usr/bin/env python3
"""Token usage report from Claude Code transcripts (main sessions + subagents).

Usage: token-report.py [project_dir] [--since YYYY-MM-DD]
  project_dir defaults to the current directory.

Why this exists: state/session-cost.jsonl only counted tool calls, never tokens.
Usage is summed from the transcripts' assistant `message.usage`, counted once
per message.id (one API response spans several transcript lines that repeat the
same usage). Subagent transcripts live in <session>/subagents/ with a
.meta.json carrying agentType and model.

Token counts only, no prices: rates change per model and the first-turn
context is the number to watch (it is what every spawn pays before any work).
"""
import collections
import glob
import json
import os
import re
import sys


def transcript_dir(project_dir):
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(project_dir))
    return os.path.expanduser(os.path.join("~/.claude/projects", slug))


def usage_of(path, since):
    seen = set()
    total = collections.Counter()
    turns = 0
    first_ctx = None
    for line in open(path, errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        m = d.get("message")
        if not isinstance(m, dict) or "usage" not in m:
            continue
        if since and (d.get("timestamp") or "")[:10] < since:
            continue
        mid = m.get("id")
        if mid in seen:
            continue
        seen.add(mid)
        u = m["usage"]
        cw = u.get("cache_creation_input_tokens", 0)
        cr = u.get("cache_read_input_tokens", 0)
        turns += 1
        if first_ctx is None:
            first_ctx = cw + cr + u.get("input_tokens", 0)
        total["cw"] += cw
        total["cr"] += cr
        total["out"] += u.get("output_tokens", 0)
    return total, turns, first_ctx or 0


def main():
    args = [a for a in sys.argv[1:]]
    since = None
    if "--since" in args:
        i = args.index("--since")
        since = args[i + 1]
        del args[i:i + 2]
    root = transcript_dir(args[0] if args else ".")
    if not os.path.isdir(root):
        sys.exit("no transcripts at " + root)

    main_tot = collections.Counter()
    main_turns = 0
    for f in glob.glob(os.path.join(root, "*.jsonl")):
        t, n, _ = usage_of(f, since)
        main_tot.update(t)
        main_turns += n

    agg = collections.defaultdict(collections.Counter)
    for mf in glob.glob(os.path.join(root, "*", "subagents", "*.meta.json")):
        tf = mf[: -len(".meta.json")] + ".jsonl"
        if not os.path.exists(tf):
            continue
        meta = json.load(open(mf))
        t, n, first = usage_of(tf, since)
        if n == 0:
            continue
        a = agg[(meta.get("agentType"), meta.get("model") or "inherit")]
        a["spawns"] += 1
        a["turns"] += n
        a["first"] += first
        a.update(t)

    sub_tot = collections.Counter()
    for a in agg.values():
        for k in ("cw", "cr", "out"):
            sub_tot[k] += a[k]

    def m(x):
        return "%.1f" % (x / 1e6)

    print("MAIN     turns=%d  cacheWrite=%sM  cacheRead=%sM  out=%sM"
          % (main_turns, m(main_tot["cw"]), m(main_tot["cr"]), m(main_tot["out"])))
    print("SUBAGENT spawns=%d  cacheWrite=%sM  cacheRead=%sM  out=%sM"
          % (sum(a["spawns"] for a in agg.values()),
             m(sub_tot["cw"]), m(sub_tot["cr"]), m(sub_tot["out"])))
    print()
    print("%-24s %-8s %6s %6s %8s %9s %9s %7s"
          % ("agent", "model", "spawns", "t/ag", "1stCtx", "cacheW M", "cacheR M", "out M"))
    order = sorted(agg.items(), key=lambda x: -(x[1]["cw"] * 1.25 + x[1]["cr"] * 0.1 + x[1]["out"] * 5))
    for (typ, model), a in order:
        n = a["spawns"]
        print("%-24s %-8s %6d %6.1f %8d %9s %9s %7s"
              % (typ, model, n, a["turns"] / n, a["first"] / n,
                 m(a["cw"]), m(a["cr"]), m(a["out"])))


if __name__ == "__main__":
    main()
