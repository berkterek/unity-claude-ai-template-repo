#!/usr/bin/env python3
"""test_extractor_interface_access_nameof.py — interface members are implicitly public; nameof is no call.

C# interface members with no modifier are public (C# 8 allows an explicit modifier, which wins), but
_extract_accessibility defaulted every modifier-less member to "private" — right for class members,
wrong for the 164/166 interface methods measured on nile. `nameof(x)` is a compile-time operator that
parses as an invocation_expression, so it was recorded as a call `Class.nameof`.

stdlib only (tooling, not Unity code). Run: python3 .claude/graph/test/test_extractor_interface_access_nameof.py
Exit: 0 = ALL PASSED or SKIP (tree-sitter unavailable), 1 = failures.
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "csharp_extractor", os.path.join(_HERE, "..", "extractors", "csharp_extractor.py"))
csx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(csx)

_failures = []

SRC = b"""namespace Fixture
{
    public interface ISvc
    {
        int Count { get; }
        void Run();
        public void Explicit();
        private void Helper() { }
    }

    public class Impl
    {
        void Plain() { }
        private int _n;
        public string Name => nameof(Impl);
        public void Use() { var s = nameof(Impl); Plain(); }
    }
}
"""


def check(name, cond, detail=""):
    if cond:
        print("PASS: " + name)
    else:
        print("FAIL: " + name + (" -- " + str(detail) if detail else ""))
        _failures.append(name)


def _parser():
    lang, cls = csx._try_import()
    p = cls()
    p.language = lang
    return p


def _by(items, name):
    return next((i for i in items if i["name"] == name), {})


def run():
    res = csx.extract_file(_parser(), "Fixture.cs", SRC)
    iface = _by(res["interfaces"], "ISvc")
    cls = _by(res["classes"], "Impl")

    check("modifier-less interface method is public",
          _by(iface["methods"], "Run").get("accessibility") == "public", _by(iface["methods"], "Run"))
    check("modifier-less interface property is public",
          _by(iface["properties"], "Count").get("accessibility") == "public", _by(iface["properties"], "Count"))
    check("explicit public interface method stays public",
          _by(iface["methods"], "Explicit").get("accessibility") == "public")
    check("explicit private interface helper stays private (explicit modifier wins)",
          _by(iface["methods"], "Helper").get("accessibility") == "private")
    check("modifier-less class method is still private",
          _by(cls["methods"], "Plain").get("accessibility") == "private")
    check("modifier-less class field is still private",
          _by(cls["fields"], "_n").get("accessibility") == "private")

    callees = [c["callee"] for c in res["partial_calls"]]
    check("nameof(...) is not recorded as a call", not any("nameof" in c for c in callees), callees)
    check("a genuine bare self-call is still recorded", "Impl.Plain" in callees, callees)


def main():
    try:
        _parser()
    except Exception:
        print("SKIP: tree-sitter unavailable")
        return 0
    run()
    if _failures:
        print("\n%d FAILED:" % len(_failures))
        for f in _failures:
            print("  - " + f)
        return 1
    print("\nALL PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
