#!/usr/bin/env python3
"""test_validate_entrypoint_rule.py — pins the ENTRYPOINT_DOUBLE_INTERFACES rule in
graph_validate.run_consistency (Task 7 of docs/PLAN_graph_complete_map.md).

Rule: `RegisterEntryPoint<A>(...).AsImplementedInterfaces()` throws VContainer's
"Conflict implementation type" at runtime (RegisterEntryPoint already registers the
lifecycle interfaces). Flag every registration record with method == "RegisterEntryPoint"
and "AsImplementedInterfaces" in chain, in installers[] AND in vcontainer.scopes[].

Issue shape (pinned): {"type": "ENTRYPOINT_DOUBLE_INTERFACES", "installer"|"scope": <holder name>,
"registered": <type>, "line": <int>, "detail": "...RegisterEntryPoint...AsImplementedInterfaces...
Conflict implementation type...line N..."}.

ASSUMPTION (registrations_without_method placement): run_consistency keeps returning a plain list
of issues (its callers and sibling tests depend on that). The count of registration records that
lack a `method` key (older graphs, across installers[] and scopes[]) is exposed on the graph dict:
    g["validation"]["consistency_stats"]["registrations_without_method"]
written by run_consistency (setdefault chain; main() later assigns validation.consistency
without clobbering it). Such records never produce an ENTRYPOINT issue.

Stdlib-only. Run: python3 .claude/graph/test/test_validate_entrypoint_rule.py
Exit: 0 = ALL PASSED or SKIP (tree-sitter unavailable for the e2e part), 1 = failures.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("graph_validate", os.path.join(_HERE, "..", "graph_validate.py"))
gv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gv)

_failures = []
RULE = "ENTRYPOINT_DOUBLE_INTERFACES"


def check(name, cond, detail=""):
    if cond:
        print("PASS: " + name)
    else:
        print("FAIL: " + name + (" -- " + str(detail) if detail else ""))
        _failures.append(name)


def _graph(installers=None, scopes=None, classes=("A",)):
    vc = {"installers": installers or []}
    if scopes is not None:
        vc["scopes"] = scopes
    return {"codebase": {"classes": [{"name": n} for n in classes], "interfaces": [],
                         "events": [], "calls": [], "vcontainer": vc}}


def _rule(issues):
    return [i for i in issues if i.get("type") == RULE]


def _holder(i):
    return i.get("installer") or i.get("scope") or i.get("holder")


def _stats(g):
    return g.get("validation", {}).get("consistency_stats", {})


def run_synthetic():
    reg = {"method": "RegisterEntryPoint", "type": "A", "chain": ["AsImplementedInterfaces"], "line": 49}

    # (a)
    g = _graph(installers=[{"name": "AModule", "registrations": [dict(reg)]}])
    issues = gv.run_consistency(g)
    check("(a) exactly one issue overall", len(issues) == 1, issues)
    r = _rule(issues)
    check("(a) one ENTRYPOINT_DOUBLE_INTERFACES", len(r) == 1, issues)
    if r:
        i = r[0]
        check("(a) holder name", _holder(i) == "AModule", i)
        check("(a) registered == A", i.get("registered") == "A", i)
        check("(a) line == 49", i.get("line") == 49, i)
        d = i.get("detail", "")
        for s in ("RegisterEntryPoint", "AsImplementedInterfaces", "Conflict implementation type", "line 49"):
            check("(a) detail contains %r" % s, s in d, d)

    # (b)
    g = _graph(installers=[{"name": "M", "registrations": [
        {"method": "RegisterEntryPoint", "type": "A", "chain": ["AsSelf"], "line": 5}]}])
    check("(b) RegisterEntryPoint + AsSelf -> none", _rule(gv.run_consistency(g)) == [])

    # (c)
    g = _graph(installers=[{"name": "M", "registrations": [
        {"method": "Register", "type": "A", "chain": ["As<IFoo>", "AsImplementedInterfaces"], "line": 6}]}])
    check("(c) Register + As<IFoo>,AsImplementedInterfaces -> none", _rule(gv.run_consistency(g)) == [])

    # (d)
    g = _graph(scopes=[{"name": "GameScope", "registrations": [dict(reg)]}])
    r = _rule(gv.run_consistency(g))
    check("(d) fires for vcontainer.scopes[]", len(r) == 1, r)
    if r:
        check("(d) scope holder name", _holder(r[0]) == "GameScope", r[0])
        check("(d) scope line == 49", r[0].get("line") == 49, r[0])

    # (e)
    legacy = {"type": "A", "chain": ["AsImplementedInterfaces"], "line": 7}  # no `method` key
    g = _graph(installers=[{"name": "M1", "registrations": [dict(legacy), dict(legacy),
                                                            {"method": "Register", "type": "A", "chain": []}]}],
               scopes=[{"name": "S", "registrations": [dict(legacy)]}])
    issues = gv.run_consistency(g)
    check("(e) no-method records -> no ENTRYPOINT issue", _rule(issues) == [], issues)
    check("(e) registrations_without_method == 3",
          _stats(g).get("registrations_without_method") == 3, g.get("validation"))


def run_e2e():
    sys.path.insert(0, _HERE)
    try:
        import test_extractor_members_docs as m
        m._parser()
    except Exception as e:
        print("SKIP: e2e (tree-sitter / helper unavailable: %s)" % e)
        return
    root, gdir, _fx = m._make_sandbox()
    try:
        out = os.path.join(root, "graph.json")
        b = m._build(root, gdir, out, "--full", "--quiet")
        check("(f) sandbox build exits 0", b.returncode == 0, b.stderr[-300:])
        r = subprocess.run([sys.executable, os.path.join(gdir, "graph_validate.py"), "--graph", out],
                           capture_output=True, text=True, cwd=root)
        text = r.stdout + r.stderr
        check("(f) graph_validate exits 0", r.returncode == 0, text[-300:])
        n = text.count("[%s]" % RULE)
        check("(f) output has [%s] exactly once" % RULE, n == 1, "count=%d\n%s" % (n, text[-600:]))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    run_synthetic()
    run_e2e()
    if _failures:
        print("\n%d FAILED:" % len(_failures))
        for f in _failures:
            print("  - " + f)
        return 1
    print("\nALL PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
