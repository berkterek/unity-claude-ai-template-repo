#!/usr/bin/env python3
"""test_what_where.py — pins `what` / `where` symbol lookups (Task 8, docs/PLAN_graph_complete_map.md).

Pinned API (graph_bfs_core): CHARS_PER_TOKEN=2.5, est_tokens, resolve_symbol(name, g),
where_core(name, g) -> {"ok","hits":[{"file","line","end_line","read":{"offset","limit"}}], "ambiguous"},
what_core(name, g, forward, reverse, edges, budget_tokens=2000) -> {"ok","text","truncated","sections"},
budget_truncate(sections, budget_tokens) -> (text, truncated).
CLI: graph-traversal.py [--graph G] where <sym> [--json] ; what <sym> [--budget N] [--json].

Fixture graph is built in a temp sandbox from fixtures/members_docs (never the repo's graph.json).
Each missing piece fails its own check (no single crash). stdlib only.
Run: python3 .claude/graph/test/test_what_where.py   Exit 0 = ALL PASSED, 1 = failures.
"""
import asyncio
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback

_HERE = os.path.dirname(os.path.abspath(__file__))
_GRAPH_DIR = os.path.abspath(os.path.join(_HERE, ".."))
_FIXTURE_DIR = os.path.join(_HERE, "fixtures", "members_docs")
_FIXTURE_REL = os.path.join("Assets", "_GameFolders", "Scripts", "Games", "Concretes", "MembersDocs")
_TRAVERSAL = os.path.join(_GRAPH_DIR, "graph-traversal.py")
_MCP_SERVER = os.path.join(_GRAPH_DIR, "graph-mcp-server.py")

sys.path.insert(0, _GRAPH_DIR)
import graph_bfs_core as core  # noqa: E402

_failures = []


def check(name, cond, detail=""):
    if cond:
        print("PASS: " + name)
    else:
        print("FAIL: " + name + (" -- " + str(detail)[:400] if detail else ""))
        _failures.append(name)


def guarded(label, fn):
    """Run a check group; an exception (ImportError/AttributeError/...) fails only this group."""
    try:
        fn()
    except Exception as e:  # noqa: BLE001
        check(label + " (no exception)", False, "%s: %s" % (type(e).__name__, e))
        traceback.print_exc(limit=2)


def _api(attr):
    return getattr(core, attr)


def _load_traversal():
    spec = importlib.util.spec_from_file_location("graph_traversal", _TRAVERSAL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _make_sandbox():
    root = tempfile.mkdtemp(prefix="graph-t8-")
    subprocess.run(["git", "init", "-q", root], check=True)
    gdir = os.path.join(root, ".claude", "graph")
    os.makedirs(gdir)
    for f in os.listdir(_GRAPH_DIR):
        if f.endswith(".py"):
            shutil.copy(os.path.join(_GRAPH_DIR, f), gdir)
    shutil.copytree(os.path.join(_GRAPH_DIR, "extractors"), os.path.join(gdir, "extractors"),
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy(os.path.join(_GRAPH_DIR, "schema.json"), gdir)
    fx = os.path.join(root, _FIXTURE_REL)
    os.makedirs(fx)
    for f in ("Members.cs", "Docs.cs", "Registrations.cs"):
        shutil.copy(os.path.join(_FIXTURE_DIR, f), fx)
    return root, gdir


def _load_ctx(path):
    """(g, forward, reverse, edges) exactly as graph-traversal.load_graph builds them."""
    return _load_traversal().load_graph(path)


def _synthetic():
    """Dict graph: Foo.Tick + Bar.Tick (ambiguous bare member), Foo.NoRange (no end_line), Svc with no edges."""
    classes = [
        {"name": "Foo", "file": "A/Foo.cs", "line": 1, "end_line": 20,
         "methods": [{"name": "Tick", "line": 5, "end_line": 8, "signature": "public void Tick()"},
                     {"name": "NoRange", "line": 10}]},
        {"name": "Bar", "file": "A/Bar.cs", "line": 1, "end_line": 20,
         "methods": [{"name": "Tick", "line": 6, "end_line": 9, "signature": "public void Tick()"}]},
    ]
    g = {"codebase": {"classes": classes, "interfaces": [], "calls": []}}
    return g, {}, {}, []


def _text(res):
    return res.get("text", "") if isinstance(res, dict) else ""


def run_units(g, fwd, rev, edges):
    sg, sf, sr, se = _synthetic()

    # 10. budget_truncate unit tests
    def t_budget():
        bt = _api("budget_truncate")
        cpt = _api("CHARS_PER_TOKEN")
        check("CHARS_PER_TOKEN == 2.5", cpt == 2.5, cpt)
        check("est_tokens ceil(len/2.5)", _api("est_tokens")("x" * 6) == 3, _api("est_tokens")("x" * 6))
        secs = [("header", ["HEADER LINE"]), ("a", ["a1", "a2"]), ("b", ["b1", "b2"])]
        text, trunc = bt(secs, 1000)
        check("budget_truncate: ample budget not truncated", trunc is False, trunc)
        idx = [text.find(x) for x in ("HEADER LINE", "a1", "a2", "b1", "b2")]
        check("budget_truncate: sections in order", all(i >= 0 for i in idx) and idx == sorted(idx), idx)
        lines = ["line-%02d-xxxxxxxx" % i for i in range(30)]
        secs = [("header", ["HEADER LINE"]), ("big", lines), ("low", ["LOWER-SECTION"])]
        text, trunc = bt(secs, 30)
        check("budget_truncate: overflow flagged", trunc is True, trunc)
        check("budget_truncate: overflow section partially filled", "line-00" in text and "line-29" not in text, text)
        check("budget_truncate: '… +N more (raise --budget)'", "… +" in text and "more (raise --budget)" in text, text)
        check("budget_truncate: lower sections dropped", "LOWER-SECTION" not in text, text)
        check("budget_truncate: header kept", "HEADER LINE" in text, text)
        text, trunc = bt([("header", ["H" * 200]), ("a", ["a1"])], 5)
        check("budget_truncate: header kept when budget < header", "H" * 200 in text, text)
        check("budget_truncate: budget < header drops body", "a1" not in text and trunc is True, (text, trunc))
        text, trunc = bt([("header", ["H"]), ("body", ["a1"])], 1)
        check("budget_truncate: bare marker emitted, nothing else",
              text == "H\n… +1 more (raise --budget)" and trunc is True, (text, trunc))
        lines = ["line-%02d-xxxxxxxx" % i for i in range(30)]
        text, trunc = bt([("header", ["HEADER LINE"]), ("big", lines)], 60)
        body = text.split("\n", 1)[1]
        check("budget_truncate: mid-size body incl. marker within budget",
              trunc is True and "more (raise --budget)" in body
              and _api("est_tokens")(body) <= 60, (text, _api("est_tokens")(body)))
    guarded("budget_truncate", t_budget)

    # 2. where on a member without end_line
    def t_where_norange():
        r = _api("where_core")("Foo.NoRange", sg)
        check("where: no-end_line ok", r.get("ok") is True, r)
        h = (r.get("hits") or [{}])[0]
        check("where: no-end_line -> end_line None", h.get("end_line") is None and h.get("line") == 10, h)
    guarded("where no end_line", t_where_norange)

    # 3. ambiguous bare member
    def t_ambiguous():
        r = _api("where_core")("Tick", sg)
        hits = r.get("hits") or []
        check("where: bare ambiguous member lists all candidates",
              r.get("ok") is True and sorted(h.get("file", "") for h in hits) == ["A/Bar.cs", "A/Foo.cs"], r)
        check("where: ambiguous marked", r.get("ambiguous") is True, r)
        c = _api("resolve_symbol")("Tick", sg)
        check("resolve_symbol: bare Tick -> 2 candidates", isinstance(c, list) and len(c) == 2, c)
        if isinstance(c, list) and c:
            for k in ("kind", "owner", "name", "file", "line", "end_line", "signature", "doc", "record"):
                check("resolve_symbol candidate has key " + k, k in c[0], sorted(c[0]))
        c1 = _api("resolve_symbol")("Foo.Tick", sg)
        check("resolve_symbol: Type.Member exact -> 1", len(c1) == 1 and c1[0].get("line") == 5, c1)
    guarded("ambiguous", t_ambiguous)

    # 5. unknown symbol
    def t_unknown():
        r = _api("where_core")("Membrs", g)
        check("where: unknown -> ok False", r.get("ok") is False, r)
        check("where: unknown carries suggestion", "Members" in json.dumps(r), r)
        r = _api("what_core")("Membrs", g, fwd, rev, edges)
        check("what: unknown -> ok False + suggestion", r.get("ok") is False and "Members" in json.dumps(r), r)
        check("resolve_symbol: unknown -> []", _api("resolve_symbol")("ZzzNope", g) == [], "")
    guarded("unknown", t_unknown)

    # 1. where Members.Combine
    def t_where_combine():
        r = _api("where_core")("Members.Combine", g)
        check("where Members.Combine ok", r.get("ok") is True, r)
        hs = r.get("hits") or []
        check("where Members.Combine: single hit", len(hs) == 1, hs)
        if hs:
            h = hs[0]
            check("where Combine: file endswith Members.cs", str(h.get("file", "")).endswith("Members.cs"), h)
            check("where Combine: line/end_line == 33/38", (h.get("line"), h.get("end_line")) == (33, 38), h)
            check("where Combine: read == {offset:33, limit:6}", h.get("read") == {"offset": 33, "limit": 6}, h)
    guarded("where Combine", t_where_combine)

    # 4. Register*<T>
    def t_reg():
        r = _api("where_core")("RegisterEntryPoint<A>", g)
        check("where RegisterEntryPoint<A> ok", r.get("ok") is True, r)
        hs = r.get("hits") or []
        check("where RegisterEntryPoint<A>: hit in RegistrationsModule file",
              any(str(h.get("file", "")).endswith("Registrations.cs") for h in hs), hs)
        vc = g.get("codebase", {}).get("vcontainer", {})
        want = None
        for h in (vc.get("installers") or []) + (vc.get("scopes") or []):
            if h.get("name") == "RegistrationsModule":
                for x in h.get("registrations") or []:
                    if x.get("method") == "RegisterEntryPoint" and x.get("impl", x.get("type")) in ("A", None) \
                            and "A" in json.dumps(x):
                        want = x.get("line")
                        break
        check("where RegisterEntryPoint<A>: line equals graph registration line",
              want is not None and any(h.get("line") == want for h in hs), (want, hs))
    guarded("register lookup", t_reg)

    # 6. what Members default budget
    def t_what_members():
        r = _api("what_core")("Members", g, fwd, rev, edges)
        check("what Members ok", r.get("ok") is True, r)
        t = _text(r)
        check("what Members: len <= 2000*2.5", 0 < len(t) <= 2000 * 2.5, len(t))
        check("what Members: header has kind", "class" in t.lower(), t[:300])
        check("what Members: header has file", "Members.cs" in t, t[:300])
        check("what Members: header has range 11-63", "11-63" in t, t[:300])
        for m in ("Sum", "Combine", "Reset", "Count", "Value"):
            check("what Members: members list has " + m, m in t, t)
        check("what Members: member range shown (Combine 33-38)", "33-38" in t, t)
        check("what Members: not truncated by default", r.get("truncated") is False, r.get("truncated"))
        check("what Members: sections list", isinstance(r.get("sections"), list) and r["sections"], r.get("sections"))

        # 7. tiny budget
        r = _api("what_core")("Members", g, fwd, rev, edges, budget_tokens=50)
        t = _text(r)
        check("what --budget 50: header kept", "Members.cs" in t and "11-63" in t, t)
        check("what --budget 50: contains '… +'", "… +" in t, t)
        check("what --budget 50: 'raise --budget'", "raise --budget" in t, t)
        check("what --budget 50: truncated True", r.get("truncated") is True, r.get("truncated"))
    guarded("what Members", t_what_members)

    # 8. interface implementers + D3 dispatch label
    def t_what_iface():
        r = _api("what_core")("IShape", g, fwd, rev, edges)
        check("what IShape ok", r.get("ok") is True, r)
        impl = [c for c in g.get("codebase", {}).get("classes", []) if "IShape" in (c.get("implements") or [])]
        name = "IShape" if impl else "IDocService"
        r = _api("what_core")(name, g, fwd, rev, edges)
        t = _text(r)
        check("what %s: implementers section lists Docs" % name, "Docs" in t and "mplementer" in t, t)
        check("what %s: D3 label 'dispatch: 1 implementer(s)'" % name, "dispatch: 1 implementer(s)" in t, t)
        check("what %s: confidence high" % name, "high" in t, t)
    guarded("what interface", t_what_iface)

    # 9. docs + registrations in what
    def t_what_docs_regs():
        t = _text(_api("what_core")("Docs.Add", g, fwd, rev, edges))
        check("what Docs.Add: doc summary", "Adds amount to the total." in t, t)
        t = _text(_api("what_core")("A", g, fwd, rev, edges))
        check("what A: registration method RegisterEntryPoint", "RegisterEntryPoint" in t, t)
        check("what A: registration chain AsImplementedInterfaces", "AsImplementedInterfaces" in t, t)
        check("what A: registration holder RegistrationsModule", "RegistrationsModule" in t, t)
    guarded("what docs/regs", t_what_docs_regs)


def run_cli(gpath):
    def _run(*args):
        return subprocess.run([sys.executable, _TRAVERSAL, "--graph", gpath] + list(args),
                              capture_output=True, text=True)

    def t_where():
        r = _run("where", "Members.Combine")
        check("cli where exits 0", r.returncode == 0, r.stderr[-300:])
        check("cli where prints Members.cs:33-38", "Members.cs:33-38" in r.stdout, r.stdout)
        check("cli where prints 'Read offset=33 limit=6'", "Read offset=33 limit=6" in r.stdout, r.stdout)
        r = _run("where", "Members.Combine", "--json")
        try:
            data = json.loads(r.stdout)
            check("cli where --json parses with hits", bool(data.get("hits")), data)
        except ValueError as e:
            check("cli where --json parses", False, e)
        r = _run("where", "Members")
        check("cli where Members (type) ok", r.returncode == 0 and "Members.cs:11-63" in r.stdout, r.stdout + r.stderr)
    guarded("cli where", t_where)

    def t_where_norange():
        # graph with a member lacking end_line, via a synthetic graph file
        sg, _, _, _ = _synthetic()
        d = tempfile.mkdtemp(prefix="graph-t8-syn-")
        try:
            p = os.path.join(d, "graph.json")
            json.dump(sg, open(p, "w"))
            r = subprocess.run([sys.executable, _TRAVERSAL, "--graph", p, "where", "Foo.NoRange"],
                               capture_output=True, text=True)
            check("cli where (no end_line): 'range unavailable (no end_line'",
                  "range unavailable (no end_line" in r.stdout, r.stdout + r.stderr)
            r = subprocess.run([sys.executable, _TRAVERSAL, "--graph", p, "where", "Tick"],
                               capture_output=True, text=True)
            check("cli where bare ambiguous: lists both + 'ambiguous'",
                  "Foo.cs" in r.stdout and "Bar.cs" in r.stdout and "ambiguous" in r.stdout.lower(),
                  r.stdout + r.stderr)
        finally:
            shutil.rmtree(d, ignore_errors=True)
    guarded("cli where no-range", t_where_norange)

    def t_notfound():
        for sub in ("what", "where"):
            r = _run(sub, "NoSuchSymbolXyz")
            check("cli %s not-found: exit 0 + stderr message" % sub,
                  r.returncode == 0 and "not found" in r.stderr and not r.stdout.strip(),
                  (r.returncode, r.stdout, r.stderr))
            r = _run(sub, "NoSuchSymbolXyz", "--json")
            check("cli %s --json not-found: exit 0, message on stderr, empty stdout" % sub,
                  r.returncode == 0 and "not found" in r.stderr and not r.stdout.strip(),
                  (r.returncode, r.stdout, r.stderr))
    guarded("cli not-found", t_notfound)

    def t_what():
        r = _run("what", "Members", "--budget", "50", "--json")
        try:
            data = json.loads(r.stdout)
            check("cli what --budget 50 --json parses", True)
            check("cli what --json: truncated True + text keeps header",
                  data.get("truncated") is True and "Members.cs" in data.get("text", ""), data)
        except ValueError as e:
            check("cli what --budget 50 --json parses", False, "%s | %s" % (e, r.stdout[:200] + r.stderr[-200:]))
        r = _run("what", "Members", "--budget", "50")
        check("cli what text: '… +' and 'raise --budget'", "… +" in r.stdout and "raise --budget" in r.stdout,
              r.stdout + r.stderr)
        r = _run("what", "Members")
        check("cli what default <= 5000 chars", r.returncode == 0 and 0 < len(r.stdout) <= 5000 + 200,
              (r.returncode, len(r.stdout), r.stderr[-200:]))
    guarded("cli what", t_what)

    def t_existing():
        r = _run("callers", "Members.Sum")
        check("cli existing `callers` still works (exit 0)", r.returncode == 0, r.stderr[-300:])
    guarded("cli existing", t_existing)


def run_mcp():
    try:
        import mcp  # noqa: F401
    except ImportError:
        print("SKIP: MCP tools what/where — `mcp` package not installed")
        return
    spec = importlib.util.spec_from_file_location("graph_mcp_server", _MCP_SERVER)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:  # noqa: BLE001
        print("SKIP: MCP tools what/where — server import failed: %s" % e)
        return
    lt = getattr(mod, "list_tools", None)
    if lt is None:
        print("SKIP: MCP tools what/where — no in-process list_tools()")
        return
    names = [t.name for t in asyncio.run(lt())]
    check("MCP tool 'what' exists", "what" in names, names)
    check("MCP tool 'where' exists", "where" in names, names)


def main():
    root, gdir = _make_sandbox()
    try:
        out = os.path.join(root, "graph.json")
        r = subprocess.run([sys.executable, os.path.join(gdir, "graph-builder.py"), "--skip-mcp",
                            "--output", out, "--full", "--quiet"], capture_output=True, text=True, cwd=root)
        check("fixture graph build exits 0", r.returncode == 0, r.stderr[-300:])
        if r.returncode != 0 or not os.path.exists(out):
            return
        g, fwd, rev, edges = _load_ctx(out)
        run_units(g, fwd, rev, edges)
        run_cli(out)
        guarded("mcp", run_mcp)
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
    if _failures:
        print("\n%d FAILED: %s" % (len(_failures), ", ".join(_failures[:10])))
        sys.exit(1)
    print("\nALL PASSED")
