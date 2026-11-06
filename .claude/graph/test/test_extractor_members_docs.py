#!/usr/bin/env python3
"""test_extractor_members_docs.py — pins member-level extraction in csharp_extractor.py.

Task 3 (docs/PLAN_graph_complete_map.md): classes carry end_line, methods carry end_line + signature,
and new `properties` / `fields` lists; interfaces carry end_line + properties. Expectations mirror
fixtures/members_docs/EXPECTED.md (encoded as Python data below). Line convention: declaration-node
range, attribute list included. Task 4 appends a docs section under its own heading.

stdlib only (tooling, not Unity code). Run: python3 .claude/graph/test/test_extractor_members_docs.py
Exit: 0 = ALL PASSED or SKIP (tree-sitter unavailable), 1 = failures.
"""
import importlib.util
import json
import os
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_EXTRACTOR_PATH = os.path.join(_HERE, "..", "extractors", "csharp_extractor.py")
_MEMBERS_CS = os.path.join(_HERE, "fixtures", "members_docs", "Members.cs")
_DOCS_CS = os.path.join(_HERE, "fixtures", "members_docs", "Docs.cs")

_spec = importlib.util.spec_from_file_location("csharp_extractor", _EXTRACTOR_PATH)
csx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(csx)

_failures = []


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


def _by_name(items, name):
    for it in items:
        if it.get("name") == name:
            return it
    return None


def _sub(actual, expected, label):
    """Every key in expected must equal actual[key]."""
    if actual is None:
        check(label + " exists", False)
        return
    for k, v in expected.items():
        check("%s.%s == %r" % (label, k, v), actual.get(k) == v, "got %r" % (actual.get(k, "<missing>"),))


PROP_KEYS = {"name", "type", "line", "end_line", "accessibility", "is_static", "accessors", "is_expression_bodied"}
FIELD_KEYS = {"name", "type", "line", "end_line", "accessibility", "is_static", "is_const", "is_readonly", "is_event"}

EXP_METHODS = {
    "Sum": {"line": 31, "end_line": 31, "signature": "public int Sum(int x, int y)"},
    "Combine": {"line": 33, "end_line": 38, "signature": "public static int Combine(int left, int right)"},
    "Reset": {"line": 40, "end_line": 45, "signature": "private void Reset()"},
    "EditorOnly": {"line": 48, "end_line": 51, "signature": "private void EditorOnly()"},
}
EXP_PROPS = {
    "Count": {"type": "int", "line": 18, "end_line": 18, "accessibility": "public", "is_static": False,
              "accessors": ["get", "set"], "is_expression_bodied": False},
    "Name": {"type": "string", "line": 19, "end_line": 19, "accessibility": "public", "is_static": False,
             "accessors": ["get"], "is_expression_bodied": True},
    "Value": {"type": "int", "line": 20, "end_line": 24, "accessibility": "public", "is_static": False,
              "accessors": ["get", "set"], "is_expression_bodied": False},
}
EXP_FIELDS = {
    "MAX_COUNT": {"type": "int", "line": 13, "end_line": 13, "accessibility": "public",
                  "is_const": True, "is_readonly": False, "is_event": False},
    "Label": {"type": "string", "line": 14, "end_line": 14, "accessibility": "private", "is_static": True,
              "is_const": False, "is_readonly": True, "is_event": False},
    "_a": {"type": "int", "line": 15, "end_line": 15, "accessibility": "private", "is_static": False,
           "is_const": False, "is_readonly": False, "is_event": False},
    "_b": {"type": "int", "line": 15, "end_line": 15, "accessibility": "private", "is_static": False,
           "is_const": False, "is_readonly": False, "is_event": False},
    "Changed": {"type": "Action", "line": 16, "end_line": 16, "accessibility": "public", "is_static": False,
                "is_const": False, "is_readonly": False, "is_event": True},
}
# Captured from the extractor BEFORE Task 3 — must not change.
EXP_FIELD_TYPES = {"MAX_COUNT": "int", "Label": "string", "_a": "int", "_b": "int"}


def _names(lst):
    return sorted(x.get("name") for x in lst)


def run():
    with open(_MEMBERS_CS, "rb") as f:
        src = f.read()
    res = csx.extract_file(_parser(), _MEMBERS_CS, src)

    # ── Task 3: members ──
    members = _by_name(res["classes"], "Members")
    inner = _by_name(res["classes"], "Inner")
    attr = _by_name(res["classes"], "ContextMenuAttribute")
    check("class records Members/Inner/ContextMenuAttribute exist", all([members, inner, attr]))
    if not members:
        return
    check("Members.line == 11", members.get("line") == 11)
    check("Members.end_line == 63", members.get("end_line") == 63, members.get("end_line", "<missing>"))

    # methods
    ms = members.get("methods", [])
    check("Members methods == Sum,Combine,Reset,EditorOnly (no ctor)",
          _names(ms) == sorted(EXP_METHODS), _names(ms))
    for n, exp in EXP_METHODS.items():
        _sub(_by_name(ms, n), exp, "method " + n)

    # properties
    props = members.get("properties")
    check("Members has properties list", isinstance(props, list) and props, props)
    props = props or []
    check("Members properties == Count,Name,Value", _names(props) == sorted(EXP_PROPS), _names(props))
    for p in props:
        check("property %s keys >= required" % p.get("name"), PROP_KEYS <= set(p), PROP_KEYS - set(p))
    for n, exp in EXP_PROPS.items():
        _sub(_by_name(props, n), exp, "property " + n)

    # fields
    fields = members.get("fields")
    check("Members has fields list", isinstance(fields, list) and fields, fields)
    fields = fields or []
    check("Members fields == MAX_COUNT,Label,_a,_b,Changed", _names(fields) == sorted(EXP_FIELDS), _names(fields))
    check("_a and _b are two separate field entries",
          sum(1 for f in fields if f.get("name") in ("_a", "_b")) == 2)
    for f in fields:
        check("field %s keys >= required" % f.get("name"), FIELD_KEYS <= set(f), FIELD_KEYS - set(f))
    for n, exp in EXP_FIELDS.items():
        _sub(_by_name(fields, n), exp, "field " + n)

    # unchanged field_types
    check("Members.field_types unchanged", members.get("field_types") == EXP_FIELD_TYPES, members.get("field_types"))

    # nested Inner: own record, no leak
    if inner:
        check("Inner.line/end_line == 54/62", (inner.get("line"), inner.get("end_line")) == (54, 62),
              (inner.get("line"), inner.get("end_line")))
        _sub(_by_name(inner.get("methods", []), "InnerMethod"),
             {"line": 59, "end_line": 61, "signature": "public void InnerMethod()"}, "Inner.InnerMethod")
        ip = inner.get("properties") or []
        _sub(_by_name(ip, "Hidden"), {"type": "int", "line": 57, "end_line": 57, "accessibility": "public",
                                      "accessors": ["get"], "is_expression_bodied": True}, "Inner.Hidden")
        ifl = inner.get("fields") or []
        _sub(_by_name(ifl, "_hidden"), {"type": "int", "line": 56, "end_line": 56,
                                        "accessibility": "private"}, "Inner._hidden")
    check("Inner members do not leak into Members",
          _by_name(ms, "InnerMethod") is None and _by_name(props, "Hidden") is None
          and _by_name(fields, "_hidden") is None)

    # ContextMenuAttribute: ctor excluded, no members
    if attr:
        check("ContextMenuAttribute.end_line == 70", attr.get("end_line") == 70, attr.get("end_line", "<missing>"))
        check("ContextMenuAttribute has no methods (ctor excluded)", attr.get("methods") == [], attr.get("methods"))
        check("ContextMenuAttribute has no properties/fields",
              not attr.get("properties") and not attr.get("fields"))

    # interface
    shape = _by_name(res["interfaces"], "IShape")
    check("interface IShape exists", shape is not None)
    if shape:
        check("IShape.end_line == 9", shape.get("end_line") == 9, shape.get("end_line", "<missing>"))
        ip = shape.get("properties") or []
        check("IShape has Area property", _by_name(ip, "Area") is not None, ip)
        _sub(_by_name(ip, "Area"), {"type": "float", "line": 7, "end_line": 7, "accessors": ["get"],
                                    "is_expression_bodied": False}, "IShape.Area")

    # CLI acceptance
    out = subprocess.run([sys.executable, _EXTRACTOR_PATH, "--changed-files", _MEMBERS_CS],
                         capture_output=True, text=True)
    check("CLI exits 0 with JSON", out.returncode == 0, out.stderr[-300:])
    try:
        data = json.loads(out.stdout)
    except ValueError as e:
        check("CLI output parses as JSON", False, e)
        return
    classes = data.get("classes", [])
    print("INFO: CLI classes[0] is %r (order: %s)" % (classes[0].get("name") if classes else None,
                                                     [c.get("name") for c in classes]))
    check("CLI classes[0] is Members (plan acceptance uses index 0)",
          bool(classes) and classes[0].get("name") == "Members")
    c = _by_name(classes, "Members") or {}
    check("CLI Members: all methods have end_line",
          bool(c.get("methods")) and all("end_line" in m for m in c["methods"]))
    check("CLI Members: properties non-empty", len(c.get("properties") or []) > 0)
    check("CLI Members: a field with is_event", any(f.get("is_event") for f in (c.get("fields") or [])))


# ── Task 4: docs ──────────────────────────────────────────────────────────────
# Fixture: fixtures/members_docs/Docs.cs. `doc` = {summary, remarks}, only non-empty parts; no `doc` key
# at all when a member has no attached /// block. DOC_CAP = 300 chars + "…".
EXP_DOC_RECORDS = 8  # IDocService, IDocService.Total, Docs, _total, Docs.Total, Add, Long, Attributed


def _no_empty_doc(node, path="$"):
    """Return the path of any empty/malformed `doc` object anywhere in the output, else None."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "doc" and (not isinstance(v, dict) or not v or not any(v.values())
                               or not set(v) <= {"summary", "remarks"}):
                return "%s.doc=%r" % (path, v)
            r = _no_empty_doc(v, path + "." + k)
            if r:
                return r
    elif isinstance(node, list):
        for i, v in enumerate(node):
            r = _no_empty_doc(v, "%s[%d]" % (path, i))
            if r:
                return r
    return None


def run_docs():
    print("\n# Task 4: docs")
    with open(_DOCS_CS, "rb") as f:
        src = f.read()
    res = csx.extract_file(_parser(), _DOCS_CS, src)

    svc = _by_name(res["interfaces"], "IDocService")
    check("interface IDocService exists", svc is not None)
    if svc:
        _sub(svc, {"doc": {"summary": "Contract for a doc-carrying service."}}, "IDocService")
        total_i = _by_name(svc.get("properties") or [], "Total")
        check("IDocService.Total exists", total_i is not None)
        if total_i:
            _sub(total_i, {"doc": {"summary": "Current total."}}, "IDocService.Total")

    cls = _by_name(res["classes"], "Docs")
    check("class Docs exists", cls is not None)
    if not cls:
        return
    _sub(cls, {"doc": {"summary": "Holds documented members across several lines.",
                       "remarks": "Implements IDocService for the fixture."}}, "Docs")
    _sub(_by_name(cls.get("fields") or [], "_total"), {"doc": {"summary": "Backing value for Total."}}, "Docs._total")
    _sub(_by_name(cls.get("properties") or [], "Total"), {"doc": {"summary": "Current total."}}, "Docs.Total")

    methods = cls.get("methods") or []
    _sub(_by_name(methods, "Add"), {"doc": {"summary": "Adds amount to the total.",
                                            "remarks": "Side effect: raises nothing."}}, "Docs.Add")
    long_m = _by_name(methods, "Long")
    check("Docs.Long exists", long_m is not None)
    if long_m:
        d = long_m.get("doc")
        check("Docs.Long has doc", isinstance(d, dict), d)
        if isinstance(d, dict):
            s = d.get("summary", "")
            check("Docs.Long summary truncated (len <= 301, ends with ellipsis)",
                  0 < len(s) <= 301 and s.endswith("\u2026"), "len=%d tail=%r" % (len(s), s[-5:]))
            check("Docs.Long summary starts with Lorem ipsum", s.startswith("Lorem ipsum dolor"), s[:20])
            check("Docs.Long has no remarks key", "remarks" not in d, d.keys())
    _sub(_by_name(methods, "Attributed"), {"doc": {"summary": "Attribute sits between doc and method."}},
         "Docs.Attributed")
    for name in ("PlainComment", "Detached", "Undocumented"):
        m = _by_name(methods, name)
        check("Docs.%s exists" % name, m is not None)
        if m is not None:
            check("Docs.%s has NO doc key" % name, "doc" not in m, m.get("doc"))

    bad = _no_empty_doc(res)
    check("no empty doc object anywhere in extract_file output", bad is None, bad)

    # CLI acceptance: count of "summary" == documented records
    out = subprocess.run([sys.executable, _EXTRACTOR_PATH, "--changed-files", _DOCS_CS],
                         capture_output=True, text=True)
    check("CLI (Docs.cs) exits 0", out.returncode == 0, out.stderr[-300:])
    n = out.stdout.count('"summary"')
    check('CLI stdout contains exactly %d occurrences of "summary"' % EXP_DOC_RECORDS,
          n == EXP_DOC_RECORDS, "got %d" % n)
    try:
        bad = _no_empty_doc(json.loads(out.stdout))
        check("CLI output has no empty doc object", bad is None, bad)
    except ValueError as e:
        check("CLI (Docs.cs) output parses as JSON", False, e)


# ── Task 6: builder ──────────────────────────────────────────────────────────
# Sandbox: temp git repo + a COPY of the graph tooling, so cache/.last-build/graph.json land in the
# temp dir (the builder resolves them against its own SCRIPT_DIR), never the real repo's.
import shutil
import tempfile

_GRAPH_DIR = os.path.abspath(os.path.join(_HERE, ".."))
_FIXTURE_DIR = os.path.join(_HERE, "fixtures", "members_docs")
_FIXTURE_REL = os.path.join("Assets", "_GameFolders", "Scripts", "Games", "Concretes", "Fixture")
_SCHEMA_PATH = os.path.join(_GRAPH_DIR, "schema.json")
_EXPECTED_SCHEMA_VERSION = "1.8.0"
_EXPECTED_EXTRACTION_VERSION = 7


def _make_sandbox():
    root = tempfile.mkdtemp(prefix="graph-t6-")
    subprocess.run(["git", "init", "-q", root], check=True)
    gdir = os.path.join(root, ".claude", "graph")
    os.makedirs(gdir)
    for f in os.listdir(_GRAPH_DIR):
        if f.endswith(".py"):
            shutil.copy(os.path.join(_GRAPH_DIR, f), gdir)
    shutil.copytree(os.path.join(_GRAPH_DIR, "extractors"), os.path.join(gdir, "extractors"),
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy(_SCHEMA_PATH, gdir)
    fx = os.path.join(root, _FIXTURE_REL)
    os.makedirs(fx)
    for f in ("Members.cs", "Docs.cs", "Registrations.cs"):
        shutil.copy(os.path.join(_FIXTURE_DIR, f), fx)
    return root, gdir, fx


def _build(root, gdir, out, *extra):
    return subprocess.run(
        [sys.executable, os.path.join(gdir, "graph-builder.py"), "--skip-mcp", "--output", out] + list(extra),
        capture_output=True, text=True, cwd=root)


def _all_records(g, key):
    return g.get("codebase", {}).get(key, []) or []


def _find_class(g, name):
    return next((c for c in _all_records(g, "classes") if c.get("name") == name), None)


def _find_reg_holder(g, name):
    vc = g.get("codebase", {}).get("vcontainer", {})
    for h in (vc.get("installers", []) or []) + (vc.get("scopes", []) or []):
        if h.get("name") == name:
            return h
    return None


def run_builder():
    # 4. schema.json declarations (no sandbox needed)
    try:
        schema = json.load(open(_SCHEMA_PATH))
    except ValueError as e:
        check("schema.json parses", False, e)
        schema = None
    if schema is not None:
        check("schema.json parses", True)
        d = schema.get("definitions", {})

        def props(n):
            return (d.get(n) or {}).get("properties", {})

        def req(n):
            return (d.get(n) or {}).get("required", []) or []

        for ent, keys in (("methodEntry", ["end_line", "doc"]),
                          ("classEntry", ["end_line", "doc", "properties", "fields"]),
                          ("interfaceEntry", ["end_line", "doc", "properties"]),
                          ("registrationEntry", ["method", "chain", "line", "factory_of"])):
            for k in keys:
                check("schema %s.%s declared" % (ent, k), k in props(ent))
                check("schema %s.%s not required" % (ent, k), k not in req(ent))
        enum = props("registrationEntry").get("method", {}).get("enum", [])
        check("schema registrationEntry.method enum has RegisterFactory + RegisterEntryPoint",
              "RegisterFactory" in enum and "RegisterEntryPoint" in enum, enum)
        for n in ("propertyEntry", "fieldEntry", "docEntry"):
            check("schema definitions.%s exists" % n, n in d)
        for k in ("summary", "remarks"):
            check("schema docEntry.%s maxLength == 301" % k,
                  props("docEntry").get(k, {}).get("maxLength") == 301)

    # 1-3, 5. builder sandbox
    root, gdir, fx = _make_sandbox()
    try:
        out = os.path.join(root, "graph.json")
        r = _build(root, gdir, out, "--full", "--quiet")
        check("--full build exits 0", r.returncode == 0, r.stderr[-300:])
        try:
            g = json.load(open(out))
        except (OSError, ValueError) as e:
            check("--full build wrote parseable graph.json", False, e)
            return
        check("graph schema_version == %s" % _EXPECTED_SCHEMA_VERSION,
              g.get("schema_version") == _EXPECTED_SCHEMA_VERSION, g.get("schema_version"))
        check("graph extraction_version == %d" % _EXPECTED_EXTRACTION_VERSION,
              g.get("extraction_version") == _EXPECTED_EXTRACTION_VERSION, g.get("extraction_version"))

        def survival(g, label):
            m = _find_class(g, "Members")
            check(label + ": Members class exists", m is not None)
            if m is not None:
                check(label + ": Members.end_line == 63", m.get("end_line") == 63, m.get("end_line"))
                check(label + ": Members.properties non-empty", bool(m.get("properties")))
                sm = _by_name(m.get("methods", []) or [], "Sum")
                check(label + ": Members.Sum.signature",
                      (sm or {}).get("signature") == "public int Sum(int x, int y)", (sm or {}).get("signature"))
            h = _find_reg_holder(g, "RegistrationsModule")
            check(label + ": RegistrationsModule installer exists", h is not None)
            regs = (h or {}).get("registrations", []) or []
            eps = [x for x in regs if x.get("method") == "RegisterEntryPoint"]
            check(label + ": RegisterEntryPoint registration kept method", len(eps) >= 1, regs)
            check(label + ": registrations carry chain + line",
                  any("AsImplementedInterfaces" in (x.get("chain") or []) and isinstance(x.get("line"), int)
                      for x in eps), eps)

        survival(g, "after --full")
        check("full: Docs class has doc", bool((_find_class(g, "Documented") or _find_class(g, "Docs") or
                                                 next((c for c in _all_records(g, "classes")
                                                       if c.get("doc")), {})).get("doc")))

        # 5. validate against schema.json if a validator is available
        try:
            import jsonschema
            try:
                jsonschema.validate(g, schema)
                check("full-build graph validates against schema.json", True)
            except jsonschema.ValidationError as e:
                check("full-build graph validates against schema.json", False, str(e.message)[:300])
        except ImportError:
            print("SKIP: jsonschema unavailable, schema validation not run")

        # 1. incremental: only Docs.cs touched
        docs_path = os.path.join(fx, "Docs.cs")
        r = _build(root, gdir, out, "--incremental", "--quiet", "--changed-files", docs_path)
        check("--incremental build exits 0", r.returncode == 0, r.stderr[-300:])
        g2 = json.load(open(out))
        survival(g2, "after --incremental(Docs.cs)")
        check("incremental: touched Docs file still has a documented record",
              any(c.get("doc") for c in _all_records(g2, "classes")))
        check("incremental: no promotion to full when version matches",
              "promoting" not in r.stderr, r.stderr[-300:])
        check("incremental: schema_version kept", g2.get("schema_version") == _EXPECTED_SCHEMA_VERSION)

        # 3. stale extraction_version -> promotion
        g2["extraction_version"] = 6
        json.dump(g2, open(out, "w"))
        r = _build(root, gdir, out, "--incremental", "--changed-files", docs_path)
        check("stale v6 --incremental run exits 0", r.returncode == 0, r.stderr[-300:])
        check('stale v6: stderr contains "promoting"', "promoting" in r.stderr, r.stderr[-400:])
        g3 = json.load(open(out))
        check("stale v6: graph restamped to %d" % _EXPECTED_EXTRACTION_VERSION,
              g3.get("extraction_version") == _EXPECTED_EXTRACTION_VERSION, g3.get("extraction_version"))
        survival(g3, "after promotion")
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    try:
        _parser()
    except Exception:
        print("SKIP: tree-sitter unavailable")
        return 0
    run()
    run_docs()
    run_builder()
    if _failures:
        print("\n%d FAILED:" % len(_failures))
        for f in _failures:
            print("  - " + f)
        return 1
    print("\nALL PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
