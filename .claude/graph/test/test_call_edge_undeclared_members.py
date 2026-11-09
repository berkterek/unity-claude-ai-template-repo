#!/usr/bin/env python3
"""test_call_edge_undeclared_members.py — a member the project type does not declare is not an internal edge.

`Instantiate(...)` (inherited from MonoBehaviour), `GetType()`/`ReferenceEquals` (object),
`_svc.Received()` (NSubstitute extension) and `GetCancellationTokenOnDestroy()` (UniTask extension)
resolved to the caller's own / receiver's project class and were labelled callee_kind=internal with
method_match=False — noise in callers/impact and inflated god-node degrees.

resolve_call_targets now looks for the method on the type, its project base classes and its project
interfaces; found -> internal, method_match True (inherited project members are no longer
method_match False); declared nowhere in the chain -> external, no callee_class/callee_file.

Stdlib-only. Run: python3 .claude/graph/test/test_call_edge_undeclared_members.py
Exit codes: 0 = all passed, 1 = at least one failure.
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("gb", os.path.join(_HERE, "..", "graph-builder.py"))
gb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gb)

_failures = []


def check(label, actual, expected):
    if actual == expected:
        print(f"[PASS] {label}")
    else:
        print(f"[FAIL] {label}\n       expected: {expected}\n       actual:   {actual}")
        _failures.append(label)


def _m(*names):
    return [{"name": n} for n in names]


CLASSES = [
    {"name": "Base", "file": "Base.cs", "methods": _m("Tick"), "base_types": [], "implements": []},
    {"name": "Child", "file": "Child.cs", "methods": _m("Run"), "base_types": ["Base", "ISvc"],
     "implements": ["ISvc"]},
    {"name": "Behaviour", "file": "Behaviour.cs", "methods": _m("Go"), "base_types": ["MonoBehaviour"],
     "implements": []},
]
IFACES = [
    {"name": "ISvc", "file": "ISvc.cs", "methods": _m("Save"), "base_types": []},
    {"name": "IOther", "file": "IOther.cs", "methods": _m("Ping"), "base_types": []},
]


def _edge(caller, callee):
    return {"caller": caller, "callee": callee}


def _resolve(callee, caller="Behaviour.Go"):
    return gb.resolve_call_targets([_edge(caller, callee)], CLASSES, IFACES)[0]


def test_declared_member_is_internal_match():
    e = _resolve("Child.Run")
    check("declared method: internal + method_match True",
          (e["callee_kind"], e["callee_class"], e["method_match"]), ("internal", "Child", True))


def test_inherited_project_member_is_match():
    e = _resolve("Child.Tick")
    check("method on a project base class: internal + method_match True",
          (e["callee_kind"], e["callee_class"], e["method_match"]), ("internal", "Child", True))


def test_interface_member_via_implemented_interface_is_match():
    e = _resolve("Child.Save")
    check("method on an implemented project interface: internal + method_match True",
          (e["callee_kind"], e["method_match"]), ("internal", True))


def test_undeclared_member_is_external():
    for callee in ("Behaviour.Instantiate", "Behaviour.ReferenceEquals", "ISvc.Received",
                   "Behaviour.GetCancellationTokenOnDestroy"):
        e = _resolve(callee)
        check(f"{callee}: undeclared -> external, no project link",
              (e["callee_kind"], e["callee_class"], e["callee_file"]), ("external", None, None))


def test_type_without_methods_left_alone():
    classes = CLASSES + [{"name": "Empty", "file": "Empty.cs", "methods": [], "base_types": [], "implements": []}]
    e = gb.resolve_call_targets([_edge("Behaviour.Go", "Empty.Anything")], classes, IFACES)[0]
    check("empty methods[] stays unknown (internal, method_match None)",
          (e["callee_kind"], e["method_match"]), ("internal", None))


if __name__ == "__main__":
    test_declared_member_is_internal_match()
    test_inherited_project_member_is_match()
    test_interface_member_via_implemented_interface_is_match()
    test_undeclared_member_is_external()
    test_type_without_methods_left_alone()
    print(f"\n{'FAILED' if _failures else 'OK'} — {len(_failures)} failure(s)")
    sys.exit(1 if _failures else 0)
