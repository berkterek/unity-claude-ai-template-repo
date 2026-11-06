#!/usr/bin/env python3
"""test_extractor_qualified_calls.py — pins callee resolution for namespace-qualified receivers.

`Game.Concretes.Lobby.LobbyModule.InstallMenu(builder)` must yield callee `LobbyModule.InstallMenu`
(right-most type segment), not `Game.InstallMenu` (left-most token), so graph-builder's
resolve_call_targets can link it by simple type name. A dotted chain whose head is a field/local, or
whose last segment is lowercase, must NOT be treated as a namespace-qualified type; `this.<field>`
keeps resolving through the symbol table.

The right-most-segment guess is syntactic (`StaticClass.Instance.Method()` becomes `Instance.Method`),
so edges from dotted receivers are labelled confidence INFERRED; `this.<field>` and a bare
`Type.Method()` stay EXTRACTED.

stdlib only (tooling, not Unity code). Run: python3 .claude/graph/test/test_extractor_qualified_calls.py
Exit: 0 = ALL PASSED or SKIP (tree-sitter unavailable), 1 = failures.
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_EXTRACTOR_PATH = os.path.join(_HERE, "..", "extractors", "csharp_extractor.py")

_spec = importlib.util.spec_from_file_location("csharp_extractor", _EXTRACTOR_PATH)
csx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(csx)

_failures = []

SRC = b"""namespace Fixture
{
    public interface ISvc { void Run(); }

    public class Caller
    {
        private Player _player;
        private ISvc _svc;

        public void Qualified(object builder)
        {
            Game.Concretes.Lobby.LobbyModule.InstallMenu(builder);
        }

        public void Engine()
        {
            UnityEngine.Debug.Log("x");
        }

        public void FieldHead()
        {
            _player.Body.Move();
        }

        public void ThisField()
        {
            this._svc.Run();
        }

        public void LowerLast()
        {
            Foo.bar.Baz();
        }

        public void Bare()
        {
            LobbyModule.InstallMenu(null);
        }

        public void StaticProp()
        {
            StaticClass.Instance.Method();
        }
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


def _confs(res, caller_method):
    return [c["confidence"] for c in res["partial_calls"] if c["caller"].endswith("." + caller_method)]


def _callees(res, caller_method):
    return [c["callee"] for c in res["partial_calls"] if c["caller"].endswith("." + caller_method)]


def run():
    res = csx.extract_file(_parser(), "Caller.cs", SRC)
    by = {m: _callees(res, m) for m in ("Qualified", "Engine", "FieldHead", "ThisField", "LowerLast", "Bare", "StaticProp")}
    print("INFO: callees " + repr(by))

    check("namespace-qualified static call -> LobbyModule.InstallMenu",
          by["Qualified"] == ["LobbyModule.InstallMenu"], by["Qualified"])
    check("UnityEngine.Debug.Log -> Debug.Log", by["Engine"] == ["Debug.Log"], by["Engine"])
    check("field-headed chain is not resolved to Body.Move",
          bool(by["FieldHead"]) and "Body.Move" not in by["FieldHead"], by["FieldHead"])
    check("this._svc.Run() still resolves via field type", by["ThisField"] == ["ISvc.Run"], by["ThisField"])
    check("lowercase last segment is not resolved to bar.Baz",
          bool(by["LowerLast"]) and "bar.Baz" not in by["LowerLast"], by["LowerLast"])

    check("qualified call edge is INFERRED", _confs(res, "Qualified") == ["INFERRED"], _confs(res, "Qualified"))
    check("this._svc.Run() edge stays EXTRACTED", _confs(res, "ThisField") == ["EXTRACTED"], _confs(res, "ThisField"))
    check("bare LobbyModule.InstallMenu() stays EXTRACTED",
          by["Bare"] == ["LobbyModule.InstallMenu"] and _confs(res, "Bare") == ["EXTRACTED"],
          (by["Bare"], _confs(res, "Bare")))
    check("StaticClass.Instance.Method() -> Instance.Method, INFERRED (known false guess)",
          by["StaticProp"] == ["Instance.Method"] and _confs(res, "StaticProp") == ["INFERRED"],
          (by["StaticProp"], _confs(res, "StaticProp")))


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
