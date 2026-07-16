#!/usr/bin/env python3
"""test_extractor_pubsub.py — regression tests pinning the pub/sub + registration
AST-detection bug in csharp_extractor.py::_detect_vcontainer.

Root cause (see Docs/PLAN_graph_extractor_pubsub_and_viz.md, Task 1):
_detect_vcontainer flattens the class body to text and regexes
`\\w+\\.(Publish|Subscribe|Unsubscribe)<T>` — this only matches the GENERIC
call form. Real code overwhelmingly uses the type-inferred form
`_eventBus.Publish(new FooEvent())` (no angle brackets), which the regex
misses entirely. The same function also explicitly skips
`builder.RegisterInstance(config)` (non-generic registration).

This test is stdlib-only (no pytest) per project convention — it is
tooling, not Unity C#, so the NUnit/NSubstitute rules do not apply.

Run: python3 .claude/graph/test/test_extractor_pubsub.py
Exit codes: 0 = all tests passed, 1 = at least one failure,
            0 with "SKIP" printed = tree-sitter unavailable (not a failure).
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_EXTRACTOR_PATH = os.path.join(_HERE, "..", "extractors", "csharp_extractor.py")
_FIXTURES_DIR = os.path.join(_HERE, "fixtures", "pubsub_realworld")
_CALL_RESOLUTION_FIXTURES_DIR = os.path.join(_HERE, "fixtures", "call_resolution")

_spec = importlib.util.spec_from_file_location("csharp_extractor", _EXTRACTOR_PATH)
csx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(csx)


# ── Helpers ───────────────────────────────────────────────────────────────

def _parser():
    lang, ParserCls = csx._try_import()
    parser = ParserCls()
    parser.language = lang
    return parser


def _extract(code_str, path="mem.cs"):
    """Run the extractor over an in-memory snippet. Returns the full result dict."""
    parser = _parser()
    return csx.extract_file(parser, path, code_str.encode("utf-8"))


def _facts(code_str):
    """Return the first class entry (classes[0]) for a single-class snippet."""
    res = _extract(code_str)
    assert res["classes"], "extractor found no classes in snippet:\n" + code_str
    return res["classes"][0]


def _installer_or_scope_regs(code_str):
    """Return the `registrations` list of the first vcontainer installer/scope
    entry found — this is where registrations actually surface today (the
    plain `classes[]` entries do not carry a `registrations` key).
    """
    res = _extract(code_str)
    vc = res.get("vcontainer", {})
    entries = vc.get("installers", []) + vc.get("scopes", [])
    assert entries, "no installer/scope entry found — check naming convention " \
                     "(name must end with 'Installer', or be a static '*Module' " \
                     "class, or a 'LifetimeScope' subclass):\n" + code_str
    return entries[0]["registrations"]


def _extract_fixture(filename):
    path = os.path.join(_FIXTURES_DIR, filename)
    assert os.path.isfile(path), f"fixture missing: {path}"
    with open(path, "rb") as f:
        src = f.read()
    parser = _parser()
    return csx.extract_file(parser, path, src)


def _extract_call_resolution_fixture(filename):
    path = os.path.join(_CALL_RESOLUTION_FIXTURES_DIR, filename)
    assert os.path.isfile(path), f"fixture missing: {path}"
    with open(path, "rb") as f:
        src = f.read()
    parser = _parser()
    return csx.extract_file(parser, path, src)


def _class_named(code_str, class_name):
    """Return the class entry with the given name (for multi-class snippets)."""
    res = _extract(code_str)
    match = next((c for c in res["classes"] if c["name"] == class_name), None)
    assert match is not None, f"class {class_name!r} not found in: {[c['name'] for c in res['classes']]}"
    return match


# ── Task 1 acceptance cases: pub/sub ────────────────────────────────────────

def test_non_generic_publish():
    # BUG PIN: `.Publish(new FooEvent())` has no <T> — regex-based detection misses it.
    code = (
        "namespace N { class S { "
        "void M(IEventBus b) { b.Publish(new FooEvent()); } "
        "} }"
    )
    c = _facts(code)
    assert c["events_published"] == ["FooEvent"], c["events_published"]


def test_generic_publish_no_double_count():
    # Regression guard: generic form must still resolve, and must not be
    # counted twice (once via <T>, once via `new T()`).
    code = (
        "namespace N { class S { "
        "void M(IEventBus b) { b.Publish<GoldChangedEvent>(new GoldChangedEvent(5)); } "
        "} }"
    )
    c = _facts(code)
    assert c["events_published"] == ["GoldChangedEvent"], c["events_published"]


def test_null_conditional_publish():
    # BUG PIN: real project code almost always uses `_eventBus?.Publish(...)`.
    # The null-conditional operator changes the AST shape but must still resolve.
    code = (
        "namespace N { class S { "
        "IEventBus _eventBus; "
        "void M() { _eventBus?.Publish(new SettingsClosedEvent()); } "
        "} }"
    )
    c = _facts(code)
    assert c["events_published"] == ["SettingsClosedEvent"], c["events_published"]


def test_qualified_new_type_publish():
    # BUG PIN: `new Ns.FooEvent()` must resolve to the last segment "FooEvent".
    code = (
        "namespace N { class S { "
        "void M(IEventBus b) { b.Publish(new Ns.FooEvent()); } "
        "} }"
    )
    c = _facts(code)
    assert c["events_published"] == ["FooEvent"], c["events_published"]


def test_subscribe_still_works():
    # Regression guard: Subscribe<T> has no argument to infer a type from,
    # so it was already generic-only and must keep working.
    code = (
        "namespace N { class S { "
        "void M(IEventBus b) { b.Subscribe<XEvent>(OnX); } "
        "void OnX(XEvent e) { } "
        "} }"
    )
    c = _facts(code)
    assert c["events_subscribed"] == ["XEvent"], c["events_subscribed"]


# ── Task 1 acceptance cases: registrations ──────────────────────────────────

def test_registerinstance_resolvable():
    # BUG PIN: `builder.RegisterInstance(config)` is explicitly skipped today
    # ("type from variable name not available, skip"). When `config` is a
    # method parameter of a known type, it must resolve.
    code = (
        "namespace N { public static class AudioModule { "
        "public static void Install(IContainerBuilder builder, AudioConfiguration config) { "
        "builder.RegisterInstance(config); "
        "} } }"
    )
    regs = _installer_or_scope_regs(code)
    matches = [r for r in regs if r.get("type") == "AudioConfiguration"]
    assert matches, regs
    assert matches[0].get("unresolved", False) is False, matches[0]


def test_registerinstance_unresolvable():
    # BUG PIN (D3): when the variable's type cannot be resolved, the
    # registration must still be recorded — never silently dropped — tagged
    # unresolved/AMBIGUOUS instead of an empty type with no explanation.
    code = (
        "namespace N { public static class AudioModule { "
        "public static void Install(IContainerBuilder builder) { "
        "builder.RegisterInstance(unknownVar); "
        "} } }"
    )
    regs = _installer_or_scope_regs(code)
    matches = [r for r in regs if r.get("type", "") == "" and r.get("unresolved") is True]
    assert matches, regs
    assert matches[0].get("confidence") == "AMBIGUOUS", matches[0]


def test_registerinstance_local_explicit_type_resolvable():
    # Local variable declared with an explicit type must resolve, same as a
    # method parameter.
    code = (
        "namespace N { public static class AudioModule { "
        "public static void Install(IContainerBuilder builder) { "
        "AudioConfiguration config = new AudioConfiguration(); "
        "builder.RegisterInstance(config); "
        "} } }"
    )
    regs = _installer_or_scope_regs(code)
    matches = [r for r in regs if r.get("type") == "AudioConfiguration"]
    assert matches, regs
    assert matches[0].get("unresolved", False) is False, matches[0]


def test_registerinstance_local_var_resolvable():
    # `var` locals must resolve via the `new T()` initializer type.
    code = (
        "namespace N { public static class AudioModule { "
        "public static void Install(IContainerBuilder builder) { "
        "var config = new AudioConfiguration(); "
        "builder.RegisterInstance(config); "
        "} } }"
    )
    regs = _installer_or_scope_regs(code)
    matches = [r for r in regs if r.get("type") == "AudioConfiguration"]
    assert matches, regs
    assert matches[0].get("unresolved", False) is False, matches[0]


def test_chained_register_single_count():
    # `.AsImplementedInterfaces()` chained onto `Register<T>(...)` must not
    # produce a second (bogus) registration — exactly one entry, type AudioService.
    code = (
        "namespace N { public static class AudioModule { "
        "public static void Install(IContainerBuilder builder) { "
        "builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces(); "
        "} } }"
    )
    regs = _installer_or_scope_regs(code)
    assert len(regs) == 1, regs
    assert regs[0].get("type") == "AudioService", regs[0]


# ── Task 3: real-world fixtures ──────────────────────────────────────────────
# Each fixture below is a minimal, self-contained snippet stripped from a real
# call shape found in the example project (nile_hole_sphere_repo), harvested
# once and committed here so verification never depends on that external repo
# being present (Grill decision D2). See fixtures/pubsub_realworld/EXPECTED.md.

def test_fixture_settings_panel_null_conditional_subscribe_and_publish():
    c = _extract_fixture("SettingsPanel.cs")["classes"][0]
    assert sorted(c["events_subscribed"]) == ["SettingsClosedEvent", "SettingsOpenedEvent"], \
        c["events_subscribed"]
    assert c["events_published"] == ["SettingsClosedEvent"], c["events_published"]


def test_fixture_upgrade_service_non_generic_publish():
    c = _extract_fixture("UpgradeService.cs")["classes"][0]
    assert c["events_published"] == ["UpgradePurchasedEvent", "UpgradePurchasedEvent"], \
        c["events_published"]


def test_fixture_audio_module_registerinstance_and_chained_register():
    res = _extract_fixture("AudioModule.cs")
    regs = res["vcontainer"]["installers"][0]["registrations"]
    types = [r.get("type") for r in regs]
    assert "AudioConfiguration" in types, regs
    assert "AudioService" in types, regs
    assert len(regs) == 2, regs  # RegisterInstance(config) + Register<AudioService>(...)


def test_fixture_run_summary_view_null_conditional_publish_with_args():
    c = _extract_fixture("RunSummaryView.cs")["classes"][0]
    assert sorted(c["events_published"]) == ["ContinueButtonPressedEvent", "GoldChangedEvent"], \
        c["events_published"]


# ── Extractor correctness regressions (template bug-fix pins) ────────────────

def test_file_scoped_namespace_resolves():
    # BUG: _extract_namespace only matched `namespace_declaration`; C# 10+
    # file-scoped `namespace N;` parses as `file_scoped_namespace_declaration`
    # and silently yielded namespace="".
    code = "namespace Game.Concretes.Audio;\npublic class AudioService { }"
    c = _facts(code)
    assert c["namespace"] == "Game.Concretes.Audio", c["namespace"]


def test_block_namespace_still_resolves():
    # Regression guard: block-scoped namespace must keep resolving.
    code = "namespace Game.Concretes.Audio { public class AudioService { } }"
    c = _facts(code)
    assert c["namespace"] == "Game.Concretes.Audio", c["namespace"]


def test_generic_base_type_argument_not_treated_as_base():
    # BUG: base types were collected via _walk(...,"identifier"), which also
    # pulled generic type ARGUMENTS. `UiPanel<IThing>` wrongly produced an
    # implements edge to IThing and polluted base_types.
    code = "namespace N { public class HomePanel : UiPanel<IThing> { } }"
    c = _facts(code)
    assert "IThing" not in c["implements"], c["implements"]
    assert "IThing" not in c["base_types"], c["base_types"]
    assert "UiPanel" in c["base_types"], c["base_types"]


def test_qualified_base_type_normalized_and_mono_detected():
    # A qualified base (UnityEngine.MonoBehaviour) must resolve to the final
    # segment and still flag is_mono — not leak "UnityEngine" into base_types.
    code = "namespace N { public class V : UnityEngine.MonoBehaviour { } }"
    c = _facts(code)
    assert c["is_mono_behaviour"] is True, c["base_types"]
    assert "UnityEngine" not in c["base_types"], c["base_types"]


def test_nested_class_methods_not_double_counted():
    # BUG: _extract_methods used a recursive _walk, so a nested class's methods
    # were also attributed to the outer class.
    code = (
        "namespace N { public class Outer { "
        "  public void OuterM() { } "
        "  public class Inner { public void InnerM() { } } "
        "} }"
    )
    outer = _class_named(code, "Outer")
    inner = _class_named(code, "Inner")
    assert [m["name"] for m in outer["methods"]] == ["OuterM"], outer["methods"]
    assert [m["name"] for m in inner["methods"]] == ["InnerM"], inner["methods"]


def test_preprocessor_wrapped_method_still_captured():
    # REGRESSION: excluding nested types must NOT drop own methods that sit
    # inside a `#if UNITY_EDITOR` (or #region) block — those parse as preproc_*
    # wrapper nodes, not nested type declarations.
    code = (
        "namespace N { public class Svc { "
        "  public void Always() { } "
        "#if UNITY_EDITOR\n"
        "  public void EditorOnly() { } "
        "#endif\n"
        "} }"
    )
    c = _class_named(code, "Svc")
    names = [m["name"] for m in c["methods"]]
    assert "Always" in names, names
    assert "EditorOnly" in names, names


# ── Injection (DIP) dependency extraction ────────────────────────────────────

def test_dependencies_all_three_di_styles():
    """A class mixing a real constructor, a Zenject `[Zenject.Inject]`
    Constructor method, and a VContainer `[VContainer.Inject]` Construct method
    must surface all three parameter types in dependencies[], deduped."""
    code = """
    namespace N {
      public class Hybrid {
        public Hybrid(IScoreService score) {}
        [Zenject.Inject] public void Constructor(IEventBus bus) {}
        [VContainer.Inject] public void Construct(ISaveLoadService save) {}
        public void NotInjected(int notADep) {}
      }
    }
    """
    c = _facts(code)
    deps = c["dependencies"]
    assert "IScoreService" in deps, deps       # real constructor
    assert "IEventBus" in deps, deps           # [Zenject.Inject]
    assert "ISaveLoadService" in deps, deps    # [VContainer.Inject]
    assert "int" not in deps, deps             # non-inject method param excluded
    assert len(deps) == len(set(deps)), deps   # deduped


# ── T1/T3/T4 (PLAN_graph_call_resolution.md): call-edge extractor asserts ────

def _calls_of(code_str, class_name=None):
    """Return the `partial_calls` list for a snippet (the extractor's raw
    per-file call-edge output — resolution into callee_class/callee_file
    happens later in graph-builder.resolve_call_targets); if class_name
    given, filter to edges whose caller starts with `ClassName.`."""
    res = _extract(code_str)
    calls = res.get("partial_calls", [])
    if class_name:
        calls = [c for c in calls if (c.get("caller") or "").startswith(class_name + ".")]
    return calls


def test_call_edge_callee_file_and_class_none_from_extractor():
    # T1: the extractor itself never fabricates callee_file/callee_class — those
    # are filled downstream by graph-builder.resolve_call_targets. Every emitted
    # call edge must carry callee_file=None, callee_class=None at extraction time.
    code = (
        "namespace N { class S { "
        "void M(Other o) { o.DoThing(); } "
        "} }"
    )
    calls = _calls_of(code, "S")
    assert calls, calls
    for c in calls:
        assert c["callee_file"] is None, c
        assert c["callee_class"] is None, c
        assert c["caller_file"] == "mem.cs", c  # caller_file IS the scanned file — correct


def test_call_edge_no_parens_or_newlines_in_callee():
    # T3 (RC2): no callee string may contain '(', ')', '=>' or a newline —
    # regardless of whether it resolved cleanly or fell back to flattened text.
    code = (
        "namespace N { class S { "
        "void M(System.Action a) { "
        "DOTween.To(() => _value,\n"
        "    x => _value = x,\n"
        "    1f, 1f).SetEase(Ease.Linear).OnComplete(() => Done()); "
        "} "
        "void Done() {} "
        "} }"
    )
    calls = _calls_of(code, "S")
    assert calls, calls
    for c in calls:
        callee = c["callee"]
        assert "(" not in callee, c
        assert ")" not in callee, c
        assert "=>" not in callee, c
        assert "\n" not in callee, c


def test_fluent_chain_callee_is_head_dot_method():
    # T3: `.SetEase(...)` chained onto `DOTween.To(...)` must resolve to a
    # clean single-line `head.Method` — DOTween is PascalCase so recv_type
    # resolves directly for `To`; the chained `.SetEase` falls back to the
    # `_receiver_head_token` walk since the inner invocation's return type is
    # unknown (deferred per Task 3 scope note).
    code = (
        "namespace N { class S { "
        "void M() { DOTween.To(() => _v, x => _v = x, 1f, 1f).SetEase(Ease.Linear); } "
        "} }"
    )
    calls = _calls_of(code, "S")
    methods = {c["callee"] for c in calls}
    assert "DOTween.To" in methods, methods       # direct PascalCase-receiver resolution
    assert "DOTween.SetEase" in methods, methods   # chained call falls back to head-token walk


def test_lambda_subscribe_callee_is_head_dot_method():
    # T3: a lambda-subscribe call (`_button.onClick.AddListener(() => Foo())`)
    # must not leak the lambda body into the callee string.
    code = (
        "namespace N { class S { "
        "Button _button; "
        "void M() { _button.onClick.AddListener(() => DoSomething()); } "
        "void DoSomething() {} "
        "} }"
    )
    calls = _calls_of(code, "S")
    methods = {c["callee"] for c in calls}
    assert any(m.endswith(".AddListener") or m == "AddListener" for m in methods), methods
    for m in methods:
        assert "(" not in m and ")" not in m and "=>" not in m, m


def test_type_fromjson_factory_local_type_inferred():
    # T4 (RC3): `var asset = InputActionAsset.FromJson(json)` must type `asset`
    # as `InputActionAsset`, so a later `asset.FindActionMap()` resolves to
    # `InputActionAsset.FindActionMap` instead of staying unresolved.
    code = (
        "namespace N { class S { "
        "void M(string json) { "
        "var asset = InputActionAsset.FromJson(json); "
        "asset.FindActionMap(\"gameplay\"); "
        "} "
        "} }"
    )
    calls = _calls_of(code, "S")
    hit = next((c for c in calls if c["callee"] == "InputActionAsset.FindActionMap"), None)
    assert hit is not None, calls
    # RC3 heuristic-derived receiver type -> edge confidence must be INFERRED.
    assert hit["confidence"] == "INFERRED", hit


def test_instance_init_local_leaves_no_false_project_edge():
    # T4 negative case: `var b = obj.Get();` (instance call, non-PascalCase
    # receiver) must NOT be given a fabricated type — `b.Use()` stays
    # unresolved (head token kept as-is, no false project-class edge).
    code = (
        "namespace N { class S { "
        "void M(Holder obj) { "
        "var b = obj.Get(); "
        "b.Use(); "
        "} "
        "} }"
    )
    calls = _calls_of(code, "S")
    use_hit = next((c for c in calls if c["callee"].endswith(".Use") or c["callee"] == "Use"), None)
    assert use_hit is not None, calls
    assert use_hit["callee"] != "Holder.Use", use_hit  # must not fabricate Holder as b's type
    assert use_hit["callee"] != "obj.Use", use_hit  # obj is the wrong receiver entirely


# ── call_resolution/ fixtures (see EXPECTED.md) ─────────────────────────────

def test_fixture_soundmanager_implements_isoundservice():
    res = _extract_call_resolution_fixture("SoundManager.cs")
    c = res["classes"][0]
    assert c["name"] == "SoundManager", c["name"]
    assert c["implements"] == ["ISoundService"], c["implements"]


def test_fixture_playercontroller_di_call_unresolved_at_extraction():
    res = _extract_call_resolution_fixture("PlayerController.cs")
    calls = res["partial_calls"]
    assert calls, calls
    hit = calls[0]
    # DI-routed call: receiver's DECLARED type is the interface (RC4 shape) —
    # extractor never fabricates callee_file/callee_class.
    assert hit["callee"] == "ISoundService.Play", hit
    assert hit["callee_file"] is None, hit
    assert hit["callee_class"] is None, hit


def test_fixture_scoretween_chain_no_multiline_or_parens():
    res = _extract_call_resolution_fixture("ScoreTweenController.cs")
    callees = {c["callee"] for c in res["partial_calls"]}
    assert callees == {"DOTween.To", "DOTween.SetEase"}, callees
    for c in callees:
        assert "(" not in c and ")" not in c and "\n" not in c, c


def test_fixture_inputmaploader_factory_local_inferred():
    res = _extract_call_resolution_fixture("InputMapLoader.cs")
    calls = res["partial_calls"]
    hit = next(c for c in calls if c["callee"] == "InputActionAsset.FindActionMap")
    assert hit["confidence"] == "INFERRED", hit


# ── Runner ───────────────────────────────────────────────────────────────────

def _run():
    """Run every test_* fn, reporting each by name. Unlike a plain loop, a single
    failure does NOT abort the rest — all failures are collected and named."""
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
        except Exception as e:  # report, don't abort; SystemExit (BaseException) still propagates for SKIP
            failures.append(name)
            print(f"  ERR   {name}: {type(e).__name__}: {e}", file=sys.stderr)
    if failures:
        print(f"\n{len(failures)}/{len(test_fns)} FAILED: {', '.join(failures)}", file=sys.stderr)
        return False
    print("OK")
    return True


if __name__ == "__main__":
    try:
        passed = _run()
    except SystemExit as e:
        # csx._try_import() calls sys.exit(2) when tree-sitter is unavailable.
        if getattr(e, "code", None) == 2:
            print("SKIP: tree-sitter unavailable")
            sys.exit(0)
        raise
    sys.exit(0 if passed else 1)
