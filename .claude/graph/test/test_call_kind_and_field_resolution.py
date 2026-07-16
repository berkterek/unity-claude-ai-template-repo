#!/usr/bin/env python3
"""test_call_kind_and_field_resolution.py — tests for two call-edge resolution
enhancements in graph-builder.resolve_call_targets:

  Lever 0 — every edge gets a `callee_kind` classification:
    * "internal"   — head resolved to a project class/interface (callee_class set)
    * "external"   — head is a resolved-but-non-project type (Unity/BCL/3rd-party,
                     e.g. Transform, List, IContainerBuilder) — a CORRECT null
    * "unresolved" — head is a bare variable name the extractor could not type,
                     or an ambiguous same-name project type — the genuine miss

  Lever 1 — inherited-field second-chance: when the head is a variable name
    (lowercase / underscore) rather than a type, resolve it through the caller
    class's own + inherited `field_types` map (walking base_types), and link
    ONLY when the resolved PROJECT type actually declares the called method
    (method_match guard). This prevents fluent-chain tails (e.g.
    `_playerController.Observable.Subscribe()` surfacing head `_playerController`)
    from producing false `PlayerController.Subscribe` edges.

Stdlib-only (no pytest), same `_run()` harness as the sibling tests.
Run: python3 .claude/graph/test/test_call_kind_and_field_resolution.py
Exit codes: 0 = all passed, 1 = at least one failure.
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_GRAPH_DIR = os.path.join(_HERE, "..")

_BUILDER_PATH = os.path.join(_GRAPH_DIR, "graph-builder.py")
_spec = importlib.util.spec_from_file_location("graph_builder", _BUILDER_PATH)
gb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gb)


# ── Helpers ───────────────────────────────────────────────────────────────

def _cls(name, methods=None, base_types=None, implements=None, field_types=None, file=None):
    return {
        "name": name,
        "file": file or f"{name}.cs",
        "methods": [{"name": m} for m in (methods or [])],
        "base_types": base_types or [],
        "implements": implements or [],
        "field_types": field_types or {},
    }


def _iface(name, methods=None, file=None):
    return {"name": name, "file": file or f"{name}.cs", "methods": [{"name": m} for m in (methods or [])]}


def _edge(caller, callee, file=None, confidence="EXTRACTED"):
    return {"caller": caller, "callee": callee, "file": file or "x.cs", "line": 1, "confidence": confidence}


# ── Lever 0: callee_kind classification ─────────────────────────────────────

def test_kind_internal_when_resolved_to_project_class():
    classes = [_cls("SoundManager", methods=["Play"])]
    calls = [_edge("PlayerController.OnJump", "SoundManager.Play")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] == "SoundManager", calls[0]
    assert calls[0]["callee_kind"] == "internal", calls[0]


def test_kind_internal_when_resolved_to_project_interface():
    ifaces = [_iface("ISoundService", methods=["Play"])]
    calls = [_edge("PlayerController.OnJump", "ISoundService.Play")]
    gb.resolve_call_targets(calls, [], ifaces)
    assert calls[0]["callee_class"] == "ISoundService", calls[0]
    assert calls[0]["callee_kind"] == "internal", calls[0]


def test_kind_external_when_pascalcase_head_not_a_project_type():
    # Transform.Rotate — extractor resolved the receiver to a Unity type; there
    # is no project node to link. This is a CORRECT null, tagged external.
    calls = [_edge("PlayerController.Update", "Transform.Rotate")]
    gb.resolve_call_targets(calls, [], [])
    assert calls[0]["callee_class"] is None, calls[0]
    assert calls[0]["callee_kind"] == "external", calls[0]


def test_kind_unresolved_when_variable_head_and_no_field_info():
    # Bare variable receiver the extractor could not type, and the caller class
    # is unknown / has no field_types — the genuine miss.
    calls = [_edge("Foo.Bar", "_thing.Do")]
    gb.resolve_call_targets(calls, [], [])
    assert calls[0]["callee_class"] is None, calls[0]
    assert calls[0]["callee_kind"] == "unresolved", calls[0]


def test_kind_unresolved_when_ambiguous_project_name():
    # Two non-test classes share a simple name → REV4 leaves it unresolved.
    # It is a project type but we could not pin which one — tag unresolved, not
    # external (external is reserved for confidently non-project types).
    classes = [
        _cls("Foo", methods=["Bar"], file="Assets/Games/Concretes/A/Foo.cs"),
        _cls("Foo", methods=["Bar"], file="Assets/Games/Concretes/B/Foo.cs"),
    ]
    calls = [_edge("Caller.M", "Foo.Bar")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] is None, calls[0]
    assert calls[0]["callee_kind"] == "unresolved", calls[0]


# ── Lever 1: inherited-field second-chance resolution ───────────────────────

def test_inherited_field_links_when_method_present():
    # DerivedController : BaseController; _soundService is declared on the BASE
    # class and typed ISoundService (a project interface with Play).
    # `_soundService.Play(...)` (single-hop) must link to ISoundService.
    classes = [
        _cls("DerivedController", base_types=["BaseController"], field_types={}),
        _cls("BaseController", base_types=["MonoBehaviour"],
             field_types={"_soundService": "ISoundService"}),
    ]
    ifaces = [_iface("ISoundService", methods=["Play"])]
    calls = [_edge("DerivedController.HandleClick", "_soundService.Play")]
    gb.resolve_call_targets(calls, classes, ifaces)
    assert calls[0]["callee_class"] == "ISoundService", calls[0]
    assert calls[0]["callee_kind"] == "internal", calls[0]
    assert calls[0]["method_match"] is True, calls[0]


def test_same_class_field_second_chance_links():
    # Field declared on the caller's OWN class (not inherited).
    classes = [_cls("Foo", methods=["M"], field_types={"_bar": "Bar"}),
               _cls("Bar", methods=["Do"])]
    calls = [_edge("Foo.M", "_bar.Do")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] == "Bar", calls[0]
    assert calls[0]["callee_kind"] == "internal", calls[0]


def test_no_false_link_when_resolved_type_lacks_method():
    # Fluent-chain tail: `_playerController.<Observable>.Subscribe()` surfaces
    # head `_playerController` typed PlayerController, but PlayerController has
    # NO Subscribe method → must NOT fabricate a PlayerController.Subscribe edge.
    classes = [_cls("MenuController", methods=["Init"],
                    field_types={"_playerController": "PlayerController"}),
               _cls("PlayerController", methods=["Move", "Jump"])]
    calls = [_edge("MenuController.Init", "_playerController.Subscribe")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] is None, calls[0]
    assert calls[0]["callee_kind"] == "unresolved", calls[0]


def test_field_resolving_to_external_type_marked_external():
    # `_transform.Rotate` where _transform is typed Transform (non-project).
    classes = [_cls("Mover", methods=["Tick"], field_types={"_transform": "Transform"})]
    calls = [_edge("Mover.Tick", "_transform.Rotate")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] is None, calls[0]
    assert calls[0]["callee_kind"] == "external", calls[0]


def test_second_chance_conservative_when_method_unknown():
    # Resolved type is a project class but its methods[] is empty/unknown → we
    # cannot confirm the method belongs to it, so do NOT link (avoid guessing).
    classes = [_cls("Foo", methods=["M"], field_types={"_bar": "Bar"}),
               _cls("Bar", methods=[])]
    calls = [_edge("Foo.M", "_bar.Do")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] is None, calls[0]
    assert calls[0]["callee_kind"] == "unresolved", calls[0]


def test_base_chain_walk_is_bounded_on_cycle():
    # Pathological base cycle A->B->A must not hang; unresolved field just fails.
    classes = [_cls("A", base_types=["B"], field_types={}),
               _cls("B", base_types=["A"], field_types={})]
    calls = [_edge("A.M", "_missing.Do")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] is None, calls[0]
    assert calls[0]["callee_kind"] == "unresolved", calls[0]


# ── Regression: primary path unchanged (method_match still set both ways) ────

def test_primary_path_still_links_even_when_method_absent():
    # Existing REV5 behavior: a direct Type.Method edge links on the type name
    # regardless of method_match (False here) — Lever 1's method guard applies
    # ONLY to the second-chance variable-head path, never to the primary path.
    classes = [_cls("SoundManager", methods=["Play", "Stop"])]
    calls = [_edge("PlayerController.OnJump", "SoundManager.Mute")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] == "SoundManager", calls[0]
    assert calls[0]["method_match"] is False, calls[0]
    assert calls[0]["callee_kind"] == "internal", calls[0]


# ── Runner ───────────────────────────────────────────────────────────────────

def _run():
    test_fns = [(name, fn) for name, fn in sorted(globals().items())
                if name.startswith("test_") and callable(fn)]
    failures = []
    for name, fn in test_fns:
        try:
            fn()
            print(f"  ok    {name}")
        except AssertionError as e:
            failures.append(name)
            print(f"  FAIL  {name}: {e!r}", file=sys.stderr)
        except Exception as e:
            failures.append(name)
            print(f"  ERR   {name}: {type(e).__name__}: {e}", file=sys.stderr)
    if failures:
        print(f"\n{len(failures)}/{len(test_fns)} FAILED: {', '.join(failures)}", file=sys.stderr)
        return False
    print("OK")
    return True


if __name__ == "__main__":
    passed = _run()
    sys.exit(0 if passed else 1)
