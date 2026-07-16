#!/usr/bin/env python3
"""test_validate_interface_nodes.py — graph_validate.run_consistency must treat
INTERFACES as valid call-edge targets.

Bug: DANGLING_CALL built its node set from codebase.classes only, so every call
edge resolved to an interface (`ISoundService.Play` — the normal shape for a
DI-routed call, and now also produced by resolve_call_targets' inherited-field
second-chance) was falsely flagged "not in graph". Interfaces are first-class
call targets; they must be in the node set.

Stdlib-only (no pytest), same `_run()` harness as the sibling tests.
Run: python3 .claude/graph/test/test_validate_interface_nodes.py
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_PATH = os.path.join(_HERE, "..", "graph_validate.py")
_spec = importlib.util.spec_from_file_location("graph_validate", _PATH)
gv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gv)


def _graph(classes=None, interfaces=None, calls=None):
    return {"codebase": {
        "classes": classes or [], "interfaces": interfaces or [],
        "events": [], "calls": calls or [], "vcontainer": {},
    }}


def _dangling(issues):
    return [i for i in issues if i["type"] == "DANGLING_CALL"]


def test_interface_callee_is_not_dangling():
    g = _graph(
        classes=[{"name": "PlayerController"}],
        interfaces=[{"name": "ISoundService", "methods": [{"name": "Play"}]}],
        calls=[{"caller": "PlayerController.OnClick",
                "callee": "ISoundService.Play", "callee_class": "ISoundService"}],
    )
    assert _dangling(gv.run_consistency(g)) == [], _dangling(gv.run_consistency(g))


def test_class_callee_still_not_dangling():
    g = _graph(
        classes=[{"name": "SoundManager"}],
        calls=[{"caller": "X.M", "callee": "SoundManager.Play", "callee_class": "SoundManager"}],
    )
    assert _dangling(gv.run_consistency(g)) == [], _dangling(gv.run_consistency(g))


def test_truly_missing_callee_still_flagged():
    # A callee_class that is neither a class nor an interface remains dangling —
    # the check must not be neutered, only widened to include interfaces.
    g = _graph(
        classes=[{"name": "SoundManager"}],
        calls=[{"caller": "X.M", "callee": "Ghost.Do", "callee_class": "Ghost"}],
    )
    d = _dangling(gv.run_consistency(g))
    assert len(d) == 1 and d[0]["callee"] == "Ghost", d


def test_null_callee_never_dangling():
    g = _graph(
        classes=[{"name": "SoundManager"}],
        calls=[{"caller": "X.M", "callee": "_var.Do", "callee_class": None}],
    )
    assert _dangling(gv.run_consistency(g)) == []


def _run():
    fns = [(n, f) for n, f in sorted(globals().items())
           if n.startswith("test_") and callable(f)]
    failures = []
    for n, f in fns:
        try:
            f()
            print(f"  ok    {n}")
        except AssertionError as e:
            failures.append(n)
            print(f"  FAIL  {n}: {e!r}", file=sys.stderr)
        except Exception as e:
            failures.append(n)
            print(f"  ERR   {n}: {type(e).__name__}: {e}", file=sys.stderr)
    if failures:
        print(f"\n{len(failures)}/{len(fns)} FAILED", file=sys.stderr)
        return False
    print("OK")
    return True


if __name__ == "__main__":
    sys.exit(0 if _run() else 1)
