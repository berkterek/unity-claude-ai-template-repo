#!/usr/bin/env python3
"""Re-discovery report: how often subagents search for and re-read the same code.

Usage: read-dup-report.py [project_dir] [--since YYYY-MM-DD] [--module NN ...]
  project_dir defaults to the current directory.

Why this exists: every subagent starts with an empty context, so the planner,
plan reviewer, tester, coder and code reviewer of one module each found the
same source files again (measured Nov 2026: 15-22 agents opened the same file
per module, ~800 `grep` calls in two days). code-map.md hands the planner's
findings on; this report is the before/after number for that change.

A subagent belongs to module NN when its spawn prompt names it ("modules/NN",
"module NN", "plan NN") or a task ID inside docs/modules/NN-*. Per module:
  searches   grep/rg/find/`sed -n`/Grep/Glob calls — looking for code
  reads      (agent, file) pairs for .cs files and spec/design/tasks.md
  repeat     pairs whose file an earlier agent of the same module already read
A coder re-reading the file it edits is a legitimate repeat; watch `searches`
per agent first — that is the part code-map.md is meant to remove.

Quality guard, same table: `changes` = reviewer verdicts CHANGES NEEDED,
`failed` = verifier/validator verdicts that found a defect (VERIFY FAILED,
ISSUES FOUND, COMPILE/TEST FAILED, STALE ASSEMBLY). Read from each subagent's
last message. Fewer searches with more `changes`/`failed` means the map made
agents miss code — a cost cut paid for in quality.
"""
import collections
import glob
import json
import os
import re
import sys

CHANGES = re.compile(r"CHANGES NEEDED")
FAILED = re.compile(r"VERIFY FAILED|ISSUES FOUND|COMPILE FAILED|TEST FAILED|STALE ASSEMBLY")
SEARCH = re.compile(r"(^|[;&|]\s*|\bcd\s+\S+\s*&&\s*)(grep|rg|find|sed\s+-n|awk)\b")
FILE = re.compile(r"[\w./-]+\.(?:cs|md)\b")
PLAN_DOCS = ("spec.md", "design.md", "tasks.md")


def transcript_dir(project_dir):
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(project_dir))
    return os.path.expanduser(os.path.join("~/.claude/projects", slug))


def module_of(prompt):
    m = re.search(r"(?:modules?/|module |plan |Plan )0?(\d{1,2})\b", prompt)
    return m.group(1).zfill(2) if m else None


def scan(path, since):
    prompt, start, last = None, None, ""
    files, searches, uses = collections.Counter(), 0, 0
    for line in open(path, errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        start = start or d.get("timestamp")
        c = (d.get("message") or {}).get("content")
        if prompt is None and d.get("type") == "user":
            prompt = c if isinstance(c, str) else " ".join(
                x.get("text", "") for x in c or [] if isinstance(x, dict))
        if d.get("type") != "assistant" or not isinstance(c, list):
            continue
        for x in c:
            if isinstance(x, dict) and x.get("type") == "text" and x.get("text", "").strip():
                last = x["text"]
            if not isinstance(x, dict) or x.get("type") != "tool_use":
                continue
            name, inp = x["name"], x.get("input") or {}
            if name in ("Grep", "Glob"):
                searches += 1
                continue
            if name == "Read":
                hit = [inp.get("file_path", "")]
            elif name == "Bash":
                cmd = inp.get("command", "")
                if SEARCH.search(cmd):
                    searches += 1
                if not re.search(r"\b(cat|sed -n|head|tail|grep|awk)\b", cmd):
                    continue
                hit = FILE.findall(cmd)
            else:
                continue
            uses += 1
            for f in hit:
                b = os.path.basename(f)
                if b.endswith(".cs") or b in PLAN_DOCS:
                    files[b] += 1
    if not start or (since and start[:10] < since):
        return None
    return dict(prompt=prompt or "", start=start, files=files, searches=searches,
                changes=bool(CHANGES.search(last)), failed=bool(FAILED.search(last)))


def main():
    args = sys.argv[1:]
    since, only = None, set()
    if "--since" in args:
        i = args.index("--since")
        since = args[i + 1]
        del args[i:i + 2]
    while "--module" in args:
        i = args.index("--module")
        only.add(args[i + 1].zfill(2))
        del args[i:i + 2]
    root = transcript_dir(args[0] if args else ".")
    if not os.path.isdir(root):
        sys.exit("no transcripts at " + root)

    mods = collections.defaultdict(list)
    for mf in glob.glob(os.path.join(root, "*", "subagents", "*.meta.json")):
        tf = mf[: -len(".meta.json")] + ".jsonl"
        if not os.path.exists(tf):
            continue
        r = scan(tf, since)
        if not r:
            continue
        mod = module_of(r["prompt"])
        if mod and (not only or mod in only):
            r["type"] = json.load(open(mf)).get("agentType")
            mods[mod].append(r)

    print("%-6s %6s %9s %10s %7s %7s %8s %8s %7s" %
          ("module", "agents", "searches", "search/ag", "reads", "repeat", "repeat%", "changes", "failed"))
    per_type = collections.defaultdict(collections.Counter)
    for mod in sorted(mods):
        agents = sorted(mods[mod], key=lambda r: r["start"])
        seen, reads, repeat = set(), 0, 0
        for r in agents:
            for f in r["files"]:
                reads += 1
                repeat += f in seen
                seen.add(f)
            per_type[r["type"]]["agents"] += 1
            per_type[r["type"]]["searches"] += r["searches"]
        s = sum(r["searches"] for r in agents)
        print("%-6s %6d %9d %10.1f %7d %7d %7.0f%% %8d %7d" %
              (mod, len(agents), s, s / len(agents), reads, repeat, 100.0 * repeat / max(reads, 1),
               sum(r["changes"] for r in agents), sum(r["failed"] for r in agents)))
    print()
    print("%-24s %6s %9s %10s" % ("agent", "agents", "searches", "search/ag"))
    for typ, c in sorted(per_type.items(), key=lambda x: -x[1]["searches"]):
        print("%-24s %6d %9d %10.1f" % (typ, c["agents"], c["searches"], c["searches"] / c["agents"]))


if __name__ == "__main__":
    main()
