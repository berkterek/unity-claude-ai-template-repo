#!/usr/bin/env python3
"""test_traversal_resolution.py — regression tests for the RC1–RC4 call-edge
resolution fixes (see docs/PLAN_graph_call_resolution.md, Task 6).

Covers, on in-memory graph dicts (no file I/O, no full build):
  - RC4 traversal: interface_bridge / class_prefix / exact matched_via,
    method-query bridge (REV-methodbridge), multi-implementer ambiguity
    surfaced (REV1), one-directional bridge (REV3), impact direction guard
    (REV6).
  - REV5 method_match: True/False/None, confidence untouched, full vs.
    incremental agreement.
  - REV4 same-name tie-breaker in resolve_call_targets.
  - Incremental-retention blocker fix in merge_call_edges.

Stdlib-only (no pytest) per project convention — same `_run()` harness as
test_extractor_pubsub.py. graph_bfs_core.py has no tree-sitter dependency, so
these tests always run (never SKIP). graph-builder.py is imported via
importlib because of the hyphenated filename; importing it is side-effect
free (main() is guarded by `if __name__ == "__main__"`).

Run: python3 .claude/graph/test/test_traversal_resolution.py
Exit codes: 0 = all tests passed, 1 = at least one failure.
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_GRAPH_DIR = os.path.join(_HERE, "..")

sys.path.insert(0, _GRAPH_DIR)
import graph_bfs_core as bfs_core  # noqa: E402  (pure stdlib module, no tree-sitter dep)

_BUILDER_PATH = os.path.join(_GRAPH_DIR, "graph-builder.py")
_spec = importlib.util.spec_from_file_location("graph_builder", _BUILDER_PATH)
gb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gb)


# ── Helpers ───────────────────────────────────────────────────────────────

def _cls(name, implements=None, methods=None, file=None):
    return {
        "name": name,
        "file": file or f"{name}.cs",
        "implements": implements or [],
        "methods": [{"name": m} for m in (methods or [])],
    }


def _iface(name, methods=None, file=None):
    return {"name": name, "file": file or f"{name}.cs", "methods": [{"name": m} for m in (methods or [])]}


def _edge(caller, callee, file=None, confidence="EXTRACTED"):
    return {"caller": caller, "callee": callee, "file": file or "x.cs", "line": 1, "confidence": confidence}


def _graph(classes=None, interfaces=None, calls=None):
    return {
        "codebase": {
            "classes": classes or [],
            "interfaces": interfaces or [],
            "calls": calls or [],
        }
    }


def _build_adjacency(edges):
    """Mirror graph-traversal.py's simple method-level forward/reverse build
    (existing, unchanged behaviour) — used to feed callers_core/impact_core."""
    forward, reverse = {}, {}
    for e in edges:
        c, ce = e.get("caller"), e.get("callee")
        if not c or not ce:
            continue
        forward.setdefault(c, set()).add(ce)
        reverse.setdefault(ce, set()).add(c)
    return forward, reverse


# ── RC4: callers_core matched_via ───────────────────────────────────────────

def test_callers_interface_bridge_hit_tagged():
    # SoundManager implements ISoundService; a caller invokes ISoundService.Play
    # (DI-routed call) — `callers SoundManager` must surface it, tagged
    # interface_bridge.
    g = _graph(
        classes=[_cls("SoundManager", implements=["ISoundService"], methods=["Play"])],
        interfaces=[_iface("ISoundService", methods=["Play"])],
    )
    edges = [_edge("PlayerController.OnJump", "ISoundService.Play")]
    forward, reverse = _build_adjacency(edges)
    result = bfs_core.callers_core("SoundManager", g, forward, reverse, edges)
    assert result["ok"], result
    hits = result["hits"]
    assert len(hits) == 1, hits
    assert hits[0]["caller"] == "PlayerController.OnJump", hits[0]
    assert hits[0]["matched_via"] == "interface_bridge", hits[0]


def test_callers_class_prefix_hit_tagged():
    # A bare-class query hitting the concrete class's own method directly
    # (not via the interface) is tagged class_prefix.
    g = _graph(classes=[_cls("SoundManager", implements=["ISoundService"], methods=["Play"])],
               interfaces=[_iface("ISoundService", methods=["Play"])])
    edges = [_edge("MusicDirector.Cue", "SoundManager.Play")]
    forward, reverse = _build_adjacency(edges)
    result = bfs_core.callers_core("SoundManager", g, forward, reverse, edges)
    assert result["ok"], result
    assert result["hits"][0]["matched_via"] == "class_prefix", result["hits"]


def test_callers_exact_match_tagged():
    # A method-specific query (`SoundManager.Play`) matching that exact
    # callee string is tagged exact.
    g = _graph(classes=[_cls("SoundManager", implements=["ISoundService"], methods=["Play"])],
               interfaces=[_iface("ISoundService", methods=["Play"])])
    edges = [
        _edge("MusicDirector.Cue", "SoundManager.Play"),
        _edge("MusicDirector.Cue", "SoundManager.Stop"),
    ]
    forward, reverse = _build_adjacency(edges)
    result = bfs_core.callers_core("SoundManager.Play", g, forward, reverse, edges)
    assert result["ok"], result
    hits = result["hits"]
    assert len(hits) == 1, hits
    assert hits[0]["caller"] == "MusicDirector.Cue", hits[0]
    assert hits[0]["matched_via"] == "exact", hits[0]


def test_callers_method_query_also_bridges_to_interface():
    # REV-methodbridge: `callers SoundManager.Play` must ALSO return the
    # ISoundService.Play DI caller (interface_bridge) — a method query is
    # never poorer than the bare-class query.
    g = _graph(classes=[_cls("SoundManager", implements=["ISoundService"], methods=["Play"])],
               interfaces=[_iface("ISoundService", methods=["Play"])])
    edges = [
        _edge("MusicDirector.Cue", "SoundManager.Play"),
        _edge("PlayerController.OnJump", "ISoundService.Play"),
        _edge("Other.M", "ISoundService.Stop"),  # different method — must NOT match
    ]
    forward, reverse = _build_adjacency(edges)
    result = bfs_core.callers_core("SoundManager.Play", g, forward, reverse, edges)
    assert result["ok"], result
    hits = {h["caller"]: h["matched_via"] for h in result["hits"]}
    assert hits.get("MusicDirector.Cue") == "exact", hits
    assert hits.get("PlayerController.OnJump") == "interface_bridge", hits
    assert "Other.M" not in hits, hits  # different method on the interface — no match


def test_callers_multi_implementer_ambiguity_surfaced():
    # REV1: ISoundService has TWO implementers — production SoundManager and
    # a test fake FakeSoundService (test fakes are normal per rules/testing.md).
    # `callers SoundManager` still returns the ISoundService.Play caller,
    # labeled interface_bridge — the ambiguity is surfaced, not hidden or
    # silently attributed to one implementer.
    g = _graph(
        classes=[
            _cls("SoundManager", implements=["ISoundService"], methods=["Play"]),
            _cls("FakeSoundService", implements=["ISoundService"], methods=["Play"], file="Tests/FakeSoundService.cs"),
        ],
        interfaces=[_iface("ISoundService", methods=["Play"])],
    )
    edges = [_edge("PlayerController.OnJump", "ISoundService.Play")]
    forward, reverse = _build_adjacency(edges)
    result = bfs_core.callers_core("SoundManager", g, forward, reverse, edges)
    assert result["ok"], result
    assert len(result["hits"]) == 1, result["hits"]
    assert result["hits"][0]["matched_via"] == "interface_bridge", result["hits"]


def test_callers_interface_query_not_expanded_to_implementer_callers():
    # REV3: one-directional bridge — `callers ISoundService` must NOT be
    # expanded to include SoundManager's direct callers (concrete->interface
    # only, never interface->implementers). Exercised end-to-end through
    # callers_core now that all_nodes() indexes interfaces (see
    # test_bare_interface_query_passes_check_node for the enabling fix).
    g = _graph(classes=[_cls("SoundManager", implements=["ISoundService"], methods=["Play"])],
               interfaces=[_iface("ISoundService", methods=["Play"])])
    edges = [
        _edge("MusicDirector.Cue", "SoundManager.Play"),      # direct call on concrete
        _edge("PlayerController.OnJump", "ISoundService.Play"),  # DI call via interface
    ]
    forward, reverse = _build_adjacency(edges)
    result = bfs_core.callers_core("ISoundService", g, forward, reverse, edges)
    assert result["ok"], result
    callers = {h["caller"] for h in result["hits"]}
    assert "PlayerController.OnJump" in callers, callers
    assert "MusicDirector.Cue" not in callers, callers  # NOT bridged the other way


def test_bare_interface_query_passes_check_node():
    # Regression: all_nodes() must enumerate codebase.interfaces so a
    # bare-interface query (`callers ISoundService`) survives check_node
    # instead of failing not_found. Previously all_nodes() only walked
    # codebase.classes, closing the CLI path to the REV3 one-directional
    # bridge; now fixed in graph_bfs_core.all_nodes().
    g = _graph(classes=[_cls("SoundManager", implements=["ISoundService"], methods=["Play"])],
               interfaces=[_iface("ISoundService", methods=["Play"])])
    node_set = bfs_core.all_nodes(g, {}, {})
    assert "ISoundService" in node_set, node_set
    assert "SoundManager" in node_set, node_set
    found, msg = bfs_core.check_node("ISoundService", node_set)
    assert found is True, (found, msg)


# ── REV6: impact_core direction guard ──────────────────────────────────────

def test_impact_reaches_interface_only_caller_via_rev_class():
    # impact_core("SoundManager") must reach PlayerController, which calls
    # ONLY ISoundService.Play (never SoundManager directly) — this passes
    # ONLY if class_adjacency wires rev_class[concrete] |= {interface}
    # (upstream walk steps SoundManager -> ISoundService -> its callers).
    # A fwd_class-only wiring would fail this assertion.
    g = _graph(classes=[_cls("SoundManager", implements=["ISoundService"], methods=["Play"])],
               interfaces=[_iface("ISoundService", methods=["Play"])])
    edges = [_edge("PlayerController.OnJump", "ISoundService.Play")]
    forward, reverse = _build_adjacency(edges)
    result = bfs_core.impact_core("SoundManager", g, forward, reverse, edges, hops=3)
    assert result["ok"], result
    assert "PlayerController" in result["upstream"], result


def test_impact_direction_not_reversed_downstream():
    # Sanity companion: SoundManager's downstream must NOT wrongly include
    # PlayerController (that would indicate fwd/rev were swapped).
    g = _graph(classes=[_cls("SoundManager", implements=["ISoundService"], methods=["Play"])],
               interfaces=[_iface("ISoundService", methods=["Play"])])
    edges = [_edge("PlayerController.OnJump", "ISoundService.Play")]
    forward, reverse = _build_adjacency(edges)
    result = bfs_core.impact_core("SoundManager", g, forward, reverse, edges, hops=3)
    assert result["ok"], result
    assert "PlayerController" not in result["downstream"], result


# ── class_adjacency direction unit check (REV6, direct) ────────────────────

def test_class_adjacency_direction_is_load_bearing():
    g = _graph(classes=[_cls("SoundManager", implements=["ISoundService"])],
               interfaces=[_iface("ISoundService")])
    fwd, rev = bfs_core.class_adjacency([], g)
    assert "ISoundService" in rev.get("SoundManager", set()), rev
    assert "SoundManager" in fwd.get("ISoundService", set()), fwd


# ── REV5: method_match (graph-builder.resolve_call_targets) ────────────────

def test_method_match_true_when_method_present():
    classes = [_cls("SoundManager", methods=["Play", "Stop"])]
    calls = [_edge("PlayerController.OnJump", "SoundManager.Play")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["method_match"] is True, calls[0]
    assert calls[0]["confidence"] == "EXTRACTED", calls[0]  # untouched


def test_method_match_false_when_methods_populated_but_absent():
    classes = [_cls("SoundManager", methods=["Play", "Stop"])]
    calls = [_edge("PlayerController.OnJump", "SoundManager.Mute")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["method_match"] is False, calls[0]
    assert calls[0]["confidence"] == "EXTRACTED", calls[0]  # untouched even on mismatch


def test_method_match_none_when_methods_empty():
    classes = [_cls("SoundManager", methods=[])]
    calls = [_edge("PlayerController.OnJump", "SoundManager.Play")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["method_match"] is None, calls[0]


def test_method_match_does_not_alter_inferred_confidence():
    # An RC3 heuristic-derived edge stays INFERRED regardless of method_match.
    classes = [_cls("Type", methods=["FromJson"])]
    calls = [_edge("Loader.Load", "Type.Missing", confidence="INFERRED")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["method_match"] is False, calls[0]
    assert calls[0]["confidence"] == "INFERRED", calls[0]  # never mutated by method_match


def test_method_match_agrees_across_full_and_incremental():
    # Full rebuild: resolve_call_targets runs once over all_calls.
    classes = [_cls("SoundManager", methods=["Play"])]
    full_calls = [_edge("PlayerController.OnJump", "SoundManager.Play")]
    gb.resolve_call_targets(full_calls, classes, [])

    # Incremental rebuild: same edge retained (caller unchanged), re-resolved
    # fresh against the current index — resolve_call_targets runs over ALL
    # merged edges every build (per T1 step 3), so full and incremental must
    # agree on both confidence and method_match for the identical edge.
    existing = [_edge("PlayerController.OnJump", "SoundManager.Play")]
    merged = gb.merge_call_edges(existing, [], changed_cs=["Unrelated.cs"], mode="incremental")
    gb.resolve_call_targets(merged, classes, [])

    assert full_calls[0]["method_match"] == merged[0]["method_match"], (full_calls, merged)
    assert full_calls[0]["confidence"] == merged[0]["confidence"], (full_calls, merged)


# ── REV4: same-name tie-breaker in resolve_call_targets ─────────────────────

def test_tie_breaker_prefers_production_over_test_fake():
    classes = [
        _cls("Foo", methods=["Bar"], file="Assets/_GameFolders/Scripts/Games/Concretes/Foo.cs"),
        _cls("Foo", methods=["Bar"], file="Assets/_GameFolders/Scripts/Tests/Foo.cs"),
    ]
    calls = [_edge("Caller.M", "Foo.Bar")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] == "Foo", calls[0]
    assert calls[0]["callee_file"] == "Assets/_GameFolders/Scripts/Games/Concretes/Foo.cs", calls[0]


def test_tie_breaker_two_non_test_candidates_left_unresolved():
    classes = [
        _cls("Foo", methods=["Bar"], file="Assets/_GameFolders/Scripts/Games/Concretes/A/Foo.cs"),
        _cls("Foo", methods=["Bar"], file="Assets/_GameFolders/Scripts/Games/Concretes/B/Foo.cs"),
    ]
    calls = [_edge("Caller.M", "Foo.Bar")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] is None, calls[0]  # ambiguous -> never guessed
    assert calls[0]["callee_file"] is None, calls[0]


def test_tie_breaker_single_candidate_resolves_unconditionally():
    classes = [_cls("Foo", methods=["Bar"], file="Assets/Foo.cs")]
    calls = [_edge("Caller.M", "Foo.Bar")]
    gb.resolve_call_targets(calls, classes, [])
    assert calls[0]["callee_class"] == "Foo", calls[0]
    assert calls[0]["callee_file"] == "Assets/Foo.cs", calls[0]


# ── Incremental-retention blocker (RC1 / merge_call_edges) ──────────────────

def test_incremental_survives_callee_only_edit_across_two_builds():
    # Cross-file edge X.foo -> Y.bar. X (caller) is NEVER re-extracted across
    # two consecutive incremental builds; only Y's (callee's) file is edited
    # each time. Since extraction only regenerates the CALLER's outgoing
    # edges, the edge must never be dropped by the callee_file-only-derived
    # retention clause that used to exist (fixed: retention now keys on
    # caller_file only).
    caller_file = "Assets/PlayerController.cs"
    callee_file = "Assets/SoundManager.cs"
    edge = _edge("PlayerController.OnJump", "SoundManager.Play", file=caller_file)
    edge["caller_file"] = caller_file
    edge["callee_file"] = callee_file
    edge["callee_class"] = "SoundManager"

    # Build 1: callee_file changed, caller_file did NOT change, no new partial
    # calls (extraction wasn't re-run over the caller's file).
    after_build_1 = gb.merge_call_edges(
        existing_calls=[edge], new_partial_calls=[], changed_cs=[callee_file], mode="incremental")
    assert len(after_build_1) == 1, after_build_1
    assert after_build_1[0]["caller"] == "PlayerController.OnJump", after_build_1

    # Build 2: callee_file changed AGAIN, still no re-extraction of caller_file.
    after_build_2 = gb.merge_call_edges(
        existing_calls=after_build_1, new_partial_calls=[], changed_cs=[callee_file], mode="incremental")
    assert len(after_build_2) == 1, after_build_2
    assert after_build_2[0]["callee"] == "SoundManager.Play", after_build_2


def test_incremental_drops_edge_when_caller_file_changes_and_not_regenerated():
    # Companion sanity check: retention IS keyed on caller_file — if the
    # caller's file is the one that changed and extraction produced no new
    # partial call for it (e.g. the call site was removed), the stale edge
    # must NOT be retained.
    caller_file = "Assets/PlayerController.cs"
    edge = _edge("PlayerController.OnJump", "SoundManager.Play", file=caller_file)
    edge["caller_file"] = caller_file
    edge["callee_file"] = "Assets/SoundManager.cs"

    after_build = gb.merge_call_edges(
        existing_calls=[edge], new_partial_calls=[], changed_cs=[caller_file], mode="incremental")
    assert after_build == [], after_build


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
