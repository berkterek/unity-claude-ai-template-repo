#!/usr/bin/env python3
"""Per-run report for pipeline commands: cost, speed, quality, rule compliance.

Usage: run-report.py [project_dir] [--since YYYY-MM-DD] [--command NAME ...]
  project_dir defaults to the current directory; --command defaults to
  plan-module, update-plan, orchestrate, implement.

Why this exists: token-report.py says what a project spent, not what one run of
a command cost or whether it got cheaper at the price of quality. A run starts
at the main-session line that invokes the command and ends at the next command
invocation (or the session's end). Per run:
  cost      main-session units + units of every subagent whose first line falls
            inside the run (units = cacheRead*0.1 + cacheWrite*1.25 + out*5)
  minutes   wall clock, first to last line of the run
  spawns    Agent tool calls by the main session; `coders` = coder-class spawns
  changes   CHANGES NEEDED in agent results returned to the main session
  failed    VERIFY FAILED / ISSUES FOUND / COMPILE|TEST FAILED / STALE ASSEMBLY
  gates     QUALITY_GATE / EXHAUSTION_GATE shown by the main session
  blocked   tool results carrying a hook block (exit 2) — rule enforcement hits
  gaps      `| GAP |` lines in reviewer results — criteria a reviewer failed
Compare runs of the same command; normalise by `coders` (≈ tasks implemented).
"""
import collections
import datetime
import glob
import json
import os
import re
import sys

COMMANDS = ("plan-module", "update-plan", "orchestrate", "implement")
CODERS = ("coder", "unity-coder", "unity-setup", "unity-fixer")
FAILED = re.compile(r"VERIFY FAILED|ISSUES FOUND|COMPILE FAILED|TEST FAILED|STALE ASSEMBLY")
BLOCKED = re.compile(r"hook error|BLOCKED:|\[BLOCK|exit code 2", re.I)


def transcript_dir(project_dir):
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(project_dir))
    return os.path.expanduser(os.path.join("~/.claude/projects", slug))


def units(u):
    return (u.get("cache_read_input_tokens", 0) * 0.1 + u.get("cache_creation_input_tokens", 0) * 1.25
            + u.get("input_tokens", 0) + u.get("output_tokens", 0) * 5)


def ts(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))


def text_of(c):
    if isinstance(c, str):
        return c
    out = []
    for x in c or []:
        if isinstance(x, dict):
            if x.get("type") == "text":
                out.append(x.get("text", ""))
            elif x.get("type") == "tool_result":
                r = x.get("content")
                out.append(r if isinstance(r, str) else json.dumps(r))
    return "\n".join(out)


def subagent_costs(session_path):
    res = []
    for tf in glob.glob(session_path[:-len(".jsonl")] + "/subagents/*.jsonl"):
        seen, cost, first = set(), 0.0, None
        for line in open(tf, errors="replace"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            first = first or d.get("timestamp")
            m = d.get("message") or {}
            if d.get("type") == "assistant" and m.get("id") and m["id"] not in seen and "usage" in m:
                seen.add(m["id"])
                cost += units(m["usage"])
        if first:
            res.append((first, cost))
    return res


def runs_of(path, wanted):
    runs, cur, seen = [], None, set()
    for line in open(path, errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        t = d.get("timestamp")
        m = d.get("message") or {}
        c = m.get("content")
        if d.get("type") == "user":
            s = text_of(c)
            cmd = re.search(r"<command-name>/?([\w:-]+)</command-name>", s)
            if cmd and cmd.group(1) not in ("model", "context", "cost", "status"):
                if cur:
                    runs.append(cur)
                cur = None
                if cmd.group(1) in wanted:
                    args = re.search(r"<command-args>(.*?)</command-args>", s, re.S)
                    cur = collections.Counter()
                    cur.update(cmd=0)
                    cur_meta = dict(cmd=cmd.group(1), args=(args.group(1) if args else "")[:30], start=t, end=t)
                    cur["_meta"] = 0
                    cur.meta = cur_meta
                continue
            if cur is not None and isinstance(c, list):
                # tool results only — the command's own expansion is a user text block that
                # quotes "CHANGES NEEDED" / "FAILED" and would count on every run
                body = text_of([x for x in c if isinstance(x, dict) and x.get("type") == "tool_result"])
                cur["changes"] += body.count("CHANGES NEEDED")
                cur["failed"] += len(FAILED.findall(body))
                cur["blocked"] += len(BLOCKED.findall(body))
                cur["gaps"] += len(re.findall(r"\|\s*GAP\s*\|", body))
        if cur is None:
            continue
        if t:
            cur.meta["end"] = t
        if d.get("type") == "assistant" and isinstance(c, list):
            if m.get("id") and m["id"] not in seen and "usage" in m:
                seen.add(m["id"])
                cur["main"] += units(m["usage"])
            for x in c:
                if x.get("type") == "text":
                    cur["gates"] += len(re.findall(r"QUALITY_GATE|EXHAUSTION_GATE", x.get("text", "")))
                if x.get("type") == "tool_use" and x["name"] == "Agent":
                    cur["spawns"] += 1
                    if (x.get("input") or {}).get("subagent_type") in CODERS:
                        cur["coders"] += 1
    if cur:
        runs.append(cur)
    return runs


def main():
    args = sys.argv[1:]
    since, wanted = None, set()
    if "--since" in args:
        i = args.index("--since")
        since = args[i + 1]
        del args[i:i + 2]
    while "--command" in args:
        i = args.index("--command")
        wanted.add(args[i + 1].lstrip("/"))
        del args[i:i + 2]
    wanted = wanted or set(COMMANDS)
    root = transcript_dir(args[0] if args else ".")
    if not os.path.isdir(root):
        sys.exit("no transcripts at " + root)

    rows = []
    for f in glob.glob(os.path.join(root, "*.jsonl")):
        subs = subagent_costs(f)
        for r in runs_of(f, wanted):
            meta = r.meta
            if not meta["start"] or (since and meta["start"][:10] < since):
                continue
            r["sub"] = sum(c for t0, c in subs if meta["start"] <= t0 <= meta["end"])
            minutes = (ts(meta["end"]) - ts(meta["start"])).total_seconds() / 60
            rows.append((meta, r, minutes))

    print("%-16s %-12s %-12s %7s %7s %6s %6s %6s %7s %6s %5s %7s %5s" %
          ("start", "command", "args", "costM", "M/coder", "min", "spawns", "coders",
           "changes", "failed", "gates", "blocked", "gaps"))
    for meta, r, minutes in sorted(rows, key=lambda x: x[0]["start"]):
        cost = (r["main"] + r["sub"]) / 1e6
        print("%-16s %-12s %-12s %7.1f %7s %6.0f %6d %6d %7d %6d %5d %7d %5d" %
              (meta["start"][:16], meta["cmd"], meta["args"].strip()[:12], cost,
               "%.1f" % (cost / r["coders"]) if r["coders"] else "-", minutes, r["spawns"], r["coders"],
               r["changes"], r["failed"], r["gates"], r["blocked"], r["gaps"]))


if __name__ == "__main__":
    main()
