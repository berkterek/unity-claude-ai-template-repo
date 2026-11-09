#!/usr/bin/env python3
"""graph-usage-report.py — how a session (and its subagents) read code, and whether the graph was used.

Answers the T11 question in docs/PLAN_graph_complete_map.md: did the full-file / grep share drop when the
graph and the nudge hook were on? One row per agent, so runs can be compared side by side.

Usage: python3 -I .claude/scripts/graph-usage-report.py <project-dir> [since-ISO-date] [nudge-log]
  <project-dir>  ~/.claude/projects/<mangled-repo-path>
  since          only sessions whose first record is on/after this date (e.g. 2026-11-09)
  nudge-log      <repo>/.claude/state/graph-nudge.log (adds the hook's own decision counts)
Columns: cat.cs / sed-n / grep = shell code reads; Read.cs = Read tool on a .cs; graph = graph-traversal,
graph.json or mcp graph calls. Counts are tool calls, not tokens — pair with pipeline-breakdown.py for cost.
"""
import collections
import datetime
import glob
import json
import os
import re
import sys

COLS = ("cat.cs", "sed-n", "grep", "Read.cs", "graph", "calls")


def classify(name, inp):
    cmd = inp.get("command", "") if name == "Bash" else ""
    if name == "Read":
        return "Read.cs" if inp.get("file_path", "").endswith(".cs") else None
    if name.startswith("mcp__graph"):
        return "graph"
    if name != "Bash":
        return None
    if "graph-traversal" in cmd or "graph.json" in cmd:
        return "graph"
    if re.search(r"\bsed -n\b", cmd):
        return "sed-n"
    if re.search(r"\b(cat|head|tail)\b.*\.cs", cmd):
        return "cat.cs"
    if re.search(r"\b(grep|rg)\b", cmd):
        return "grep"
    return None


def scan(path):
    c = collections.Counter()
    first = None
    for line in open(path, errors="ignore"):
        try:
            o = json.loads(line)
        except ValueError:
            continue
        first = first or o.get("timestamp")
        if o.get("type") != "assistant":
            continue
        for b in (o.get("message") or {}).get("content") or []:
            if isinstance(b, dict) and b.get("type") == "tool_use":
                c["calls"] += 1
                kind = classify(b["name"], b.get("input") or {})
                if kind:
                    c[kind] += 1
    return c, first


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = sys.argv[1]
    since = None
    if len(sys.argv) > 2 and sys.argv[2][:2] == "20":
        since = datetime.datetime.fromisoformat(sys.argv[2] + "T00:00:00+00:00")
    log = sys.argv[3] if len(sys.argv) > 3 else (sys.argv[2] if len(sys.argv) > 2 and not since else None)

    print("%-10s %-22s " % ("session", "agent") + " ".join("%7s" % c for c in COLS))
    tot = collections.Counter()
    for sess in sorted(glob.glob(os.path.join(root, "*.jsonl")), key=os.path.getmtime):
        c, first = scan(sess)
        if not first:
            continue
        if since and datetime.datetime.fromisoformat(first.replace("Z", "+00:00")) < since:
            continue
        rows = [("main", c)]
        for sub in glob.glob(sess[:-6] + "/subagents/*.jsonl"):
            meta = json.load(open(sub[:-6] + ".meta.json"))
            rows.append(("%s[%s]" % (meta.get("agentType"), (meta.get("model") or "")[:6]), scan(sub)[0]))
        for name, cnt in rows:
            tot.update(cnt)
            print("%-10s %-22s " % (os.path.basename(sess)[:8], name[:22]) + " ".join("%7d" % cnt[k] for k in COLS))
    print("%-10s %-22s " % ("TOTAL", "") + " ".join("%7d" % tot[k] for k in COLS))
    reads = tot["cat.cs"] + tot["sed-n"] + tot["grep"] + tot["Read.cs"]
    if reads:
        print("graph share of code-reading calls: %.0f%%  (%d graph / %d reads+graph)" % (
            100.0 * tot["graph"] / (reads + tot["graph"]), tot["graph"], reads + tot["graph"]))

    if log and os.path.isfile(log):
        d = collections.Counter(l.split("\t")[1] for l in open(log) if l.count("\t") >= 3)
        print("nudge log decisions: " + ", ".join("%s=%d" % kv for kv in sorted(d.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
