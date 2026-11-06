#!/usr/bin/env python3
"""test_graph_coverage.py — pins .claude/graph/graph_coverage.py (Task 1 of
docs/PLAN_graph_complete_map.md): code-map parsing, symbol normalisation,
graph resolution, LOCATION / BEHAVIOUR measurement, mode detection and the CLI.

What it pins
------------
1. parse_code_map(text) -> (aliases, rows) on fixtures/coverage/13-power-readout.code-map.md
   (verbatim nile module-13 code-map): rows_total 34, in_scope 27, out-of-scope grouped by
   extension WITHOUT the dot: asmdef 1, unity 1, asset 1, uxml 1, uss 1, md 2 (=7).
   aliases == {"S": "BounceLegion/Assets/_GameFolders/Scripts/Games"}; row["file"] has `S/` expanded.
   Row dict keys used: file, symbols (list of NORMALISED symbol dicts, see 2), hint (raw Lines
   cell text), in_scope (bool), ext (no dot).
2. normalise_symbol(tok) -> dict | None:
   - {"kind": "name", "owner": str|None, "member": str}   `Owner.Member` is split, bare name has owner None
   - {"kind": "reg", "method": "Register...", "targ": "T"} for `Register\\w*<T>`
   - `(...)` argument lists are dropped (incl. generic args inside them); empty token -> None.
   Row level (parse_code_map): `A -> B` inside one backtick pair yields both symbols; a token
   immediately followed by `(new)` is skipped (expected-absent); un-backticked words are never
   symbols; a row with zero symbols is resolved to its file's primary type (type named like the
   file stem, else the first type).
3. measure(code_map_path, graph_path) on fixtures/coverage/mini.* — intended per-row outcome
   (mini.code-map.md, 5 in-scope rows + 1 out-of-scope .uxml):

     row  file            symbol                         LOCATION  BEHAVIOUR  fact source
     R1   MiniService.cs  MiniService (type)             yes       yes        doc
     R2   MiniTicker.cs   MiniTicker.Tick(float)         yes       yes        callers (callers_core:
                                                                              MiniController.Update
                                                                              -> MiniTicker.Tick)
     R3   MiniModel.cs    Score (property)               yes       NO         none: no doc, no callers,
                                                                              no registration
     R4   MiniController.cs _ticks (field)               NO        NO         field is resolved but has
                                                                              `line` and no `end_line`:
                                                                              start-only, so not located
     R5   MiniModule.cs   RegisterEntryPoint<MiniBoot>   yes       yes        registration (located by
                                                                              `line` alone, no range)
     R6   Mini.uxml       panel-main                     out of scope (uxml)

   => location 4/5 = 80.0, behaviour 3/5 = 60.0, location_start_only 5/5 = 100.0,
      out_of_scope == {"uxml": 1}. A row that is not located cannot satisfy BEHAVIOUR
      (R4 counts as a behaviour miss; an empty symbol set must not pass vacuously).
   per_row holds IN-SCOPE rows only, each with keys: file, located (bool), behaviour (bool),
   facts (list of "doc"/"callers"/"registration"). failing_symbols is a list whose entries
   (stringified) name `_ticks`.
4. detect_mode(g): "tree-sitter" for the mini graph; "regex" when any class has confidence other
   than EXTRACTED, or validation.warnings carries a FALLBACK_EXTRACTOR entry
   ({"code": "FALLBACK_EXTRACTOR", "message": ...}, the shape graph-builder.py writes).
5. CLI (subprocess): --json parses with keys mode, rows_total, in_scope, out_of_scope,
   location_pct, behaviour_pct, location_start_only_pct, per_row, failing_symbols;
   --gate-location 100 -> exit 1; --gate-location 50 -> exit 0; --gate-behaviour 60 -> 0 and 61 -> 1;
   a missing --graph path -> exit 2.
6. Plan acceptance: the 13-power-readout code-map against mini.graph.json gives rows_total 34,
   in_scope 27 (library and CLI).

Stdlib-only. Run: python3 .claude/graph/test/test_graph_coverage.py
Exit codes: 0 = ALL PASSED, 1 = at least one failure (or graph_coverage.py missing).
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_GRAPH_DIR = os.path.abspath(os.path.join(_HERE, ".."))
_MODULE_PATH = os.path.join(_GRAPH_DIR, "graph_coverage.py")
_FIX = os.path.join(_HERE, "fixtures", "coverage")
REAL_MAP = os.path.join(_FIX, "13-power-readout.code-map.md")
MINI_MAP = os.path.join(_FIX, "mini.code-map.md")
MINI_GRAPH = os.path.join(_FIX, "mini.graph.json")

_failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name} {detail}")
        _failures.append(name)


def _finish():
    if _failures:
        print(f"\n{len(_failures)} FAILED: " + ", ".join(_failures))
        sys.exit(1)
    print("\nALL PASSED")
    sys.exit(0)


# ── Load the module under test ────────────────────────────────────────────
if not os.path.isfile(_MODULE_PATH):
    check("graph_coverage.py exists", False, f"({_MODULE_PATH} missing)")
    _finish()
sys.path.insert(0, _GRAPH_DIR)
_spec = importlib.util.spec_from_file_location("graph_coverage", _MODULE_PATH)
gc = importlib.util.module_from_spec(_spec)
try:
    _spec.loader.exec_module(gc)
except Exception as exc:  # noqa: BLE001
    check("graph_coverage.py imports", False, repr(exc))
    _finish()


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _sig(s):
    return (s.get("kind"), s.get("owner"), s.get("member"), s.get("method"), s.get("targ"))


def _name(owner, member):
    return ("name", owner, member, None, None)


def _reg(method, targ):
    return ("reg", None, None, method, targ)


def _run_cli(*args):
    return subprocess.run(
        [sys.executable, _MODULE_PATH, *args], capture_output=True, text=True, timeout=60
    )


# ── 1. parse_code_map on the real module-13 map ───────────────────────────
print("parse_code_map (13-power-readout)")
aliases, rows = gc.parse_code_map(_read(REAL_MAP))
check("alias S expanded value",
      aliases.get("S") == "BounceLegion/Assets/_GameFolders/Scripts/Games", repr(aliases))
check("rows_total 34", len(rows) == 34, f"got {len(rows)}")
in_scope = [r for r in rows if r["in_scope"]]
check("in_scope 27", len(in_scope) == 27, f"got {len(in_scope)}")
oos = {}
for r in rows:
    if not r["in_scope"]:
        oos[r["ext"]] = oos.get(r["ext"], 0) + 1
check("out_of_scope by extension",
      oos == {"asmdef": 1, "unity": 1, "asset": 1, "uxml": 1, "uss": 1, "md": 2}, repr(oos))
check("S/ prefix expanded in every in-scope file",
      all(r["file"].startswith("BounceLegion/Assets/") and r["file"].endswith(".cs") for r in in_scope))
check("non-S file kept verbatim",
      any(r["file"] == "BounceLegion/Assets/_Scenes/Game.unity" for r in rows))


def _row(file_suffix, first_member):
    for r in rows:
        if r["file"].endswith(file_suffix) and r["symbols"] and \
                (r["symbols"][0].get("member") or r["symbols"][0].get("method")) == first_member:
            return r
    return None


r_stats = _row("GameHub/Controllers/CardController.cs", "Damage")
check("multi-symbol row: Damage, HitsPerShot, OnStatsChanged",
      r_stats is not None and [_sig(s) for s in r_stats["symbols"]] ==
      [_name(None, "Damage"), _name(None, "HitsPerShot"), _name(None, "OnStatsChanged")],
      repr(r_stats and r_stats["symbols"]))
check("hint kept raw", r_stats is not None and r_stats["hint"].strip() == "61-67")
r_args = _row("GameHub/Controllers/CardController.cs", "GetTriggerZones")
check("arg list with generics dropped: GetTriggerZones(List<Rect>)",
      r_args is not None and [_sig(s) for s in r_args["symbols"]] == [_name(None, "GetTriggerZones")])
r_owner = _row("GameHub/Abstracts/Services/ICardService.cs", "CardsOnGame")
check("Owner.Member split: ICardService.CardsOnGame",
      r_owner is not None and [_sig(s) for s in r_owner["symbols"]] == [_name("ICardService", "CardsOnGame")])
# Two GameScope rows start with RegisterComponentInHierarchy (CardManager, XpLevelView) — pick by type arg.
r_reg = next((r for r in rows if r["file"].endswith("Infrastructure/GameScope.cs") and r["symbols"]
              and r["symbols"][0].get("targ") == "XpLevelView"), None)
check("registration + owner/member in one row",
      r_reg is not None and [_sig(s) for s in r_reg["symbols"]] ==
      [_reg("RegisterComponentInHierarchy", "XpLevelView"), _name("SceneModules", "InstallGame")],
      repr(r_reg and r_reg["symbols"]))
r_arrow = _row("Lobby/LobbyModule.cs", "InstallMenu")
check("arrow row yields both: InstallMenu -> RegisterFactory<IBattleTabViewModel>",
      r_arrow is not None and [_sig(s) for s in r_arrow["symbols"]] ==
      [_name(None, "InstallMenu"), _reg("RegisterFactory", "IBattleTabViewModel")],
      repr(r_arrow and r_arrow["symbols"]))
r_fields = _row("GameHub/Controllers/DamageableCardController.cs", "DamageableCardController")
check("un-backticked 'fields' is not a symbol",
      r_fields is not None and len(r_fields["symbols"]) == 1)

# ── 2. normalise_symbol ───────────────────────────────────────────────────
print("normalise_symbol")
n = gc.normalise_symbol
check("bare name", _sig(n("MiniService")) == _name(None, "MiniService"))
check("arg list dropped", _sig(n("Init(ICardService)")) == _name(None, "Init"))
check("generic arg list dropped", _sig(n("GetTriggerZones(List<Rect>)")) == _name(None, "GetTriggerZones"))
check("Owner.Member with args",
      _sig(n("PowerModule.Install(IContainerBuilder)")) == _name("PowerModule", "Install"))
check("Owner.Member with (builder)",
      _sig(n("SceneModules.InstallGame(builder)")) == _name("SceneModules", "InstallGame"))
check("registration kind",
      _sig(n("RegisterComponentInHierarchy<CardManager>")) == _reg("RegisterComponentInHierarchy", "CardManager"))
check("registration kind RegisterFactory",
      _sig(n("RegisterFactory<IBattleTabViewModel>")) == _reg("RegisterFactory", "IBattleTabViewModel"))
check("empty token -> None", n("") is None and n("   ") is None)

SYNTH = """Base `S` = `Assets/X`.

| Task(s) | File | Symbol | Lines | Why |
|---|---|---|---|---|
| T1 | `S/A.cs` | `Foo -> Bar.Baz(int)` | 1-2 | single tick, arrow |
| T1b | `S/A.cs` | `Foo → Bar.Baz(int)` | 1-2 | single tick, unicode arrow |
| T2 | `S/A.cs` | `_powerConfig` (new), `Real` | — | new is skipped |
| T3 | `S/A.cs` | constructor, fields, properties | — | descriptive words |
| T4 | `S/B.txt` | `x` | — | out of scope |
"""
sa, srows = gc.parse_code_map(SYNTH)
check("synthetic: alias", sa.get("S") == "Assets/X")
check("synthetic: 5 rows, 4 in scope",
      len(srows) == 5 and sum(1 for r in srows if r["in_scope"]) == 4)
check("synthetic: ascii arrow yields both",
      [_sig(s) for s in srows[0]["symbols"]] == [_name(None, "Foo"), _name("Bar", "Baz")],
      repr(srows[0]["symbols"]))
check("synthetic: unicode arrow yields both",
      [_sig(s) for s in srows[1]["symbols"]] == [_name(None, "Foo"), _name("Bar", "Baz")],
      repr(srows[1]["symbols"]))
check("synthetic: (new) token skipped",
      [_sig(s) for s in srows[2]["symbols"]] == [_name(None, "Real")], repr(srows[2]["symbols"]))
check("synthetic: un-backticked words give zero symbols", srows[3]["symbols"] == [])
check("synthetic: ext of out-of-scope row", srows[4]["ext"] == "txt" and not srows[4]["in_scope"])

# zero-symbol row resolves to the file's primary type (name == stem, not first type)
print("zero-symbol row -> primary type")
with tempfile.TemporaryDirectory() as tmp:
    cm = os.path.join(tmp, "map.md")
    gp = os.path.join(tmp, "g.json")
    with open(cm, "w", encoding="utf-8") as f:
        f.write("Base `S` = `Assets/X`.\n\n| Task(s) | File | Symbol | Lines | Why |\n|---|---|---|---|---|\n"
                "| T1 | `S/Foo.cs` | constructor, fields | — | descriptive only |\n")
    base = {"namespace": "N", "file": "Assets/X/Foo.cs", "source_file": "Assets/X/Foo.cs",
            "base_types": [], "is_mono_behaviour": False, "implements": [], "dependencies": [],
            "events_published": [], "events_subscribed": [], "has_static_instance": False,
            "methods": [], "properties": [], "fields": [], "confidence": "EXTRACTED"}
    graph = {"codebase": {
        "classes": [dict(base, name="Other", line=1, end_line=3),
                    dict(base, name="Foo", line=5, end_line=9, doc={"summary": "Foo does it.", "remarks": ""})],
        "interfaces": [], "events": [], "calls": [], "vcontainer": {"installers": [], "scopes": []}},
        "validation": {"errors": [], "warnings": []}}
    with open(gp, "w", encoding="utf-8") as f:
        json.dump(graph, f)
    res = gc.measure(cm, gp)
    check("zero-symbol row located", res["location_pct"] == 100.0, repr(res["location_pct"]))
    check("zero-symbol row resolved to Foo (doc fact), not first type Other",
          res["behaviour_pct"] == 100.0, repr(res["behaviour_pct"]))

# ── 3. measure on mini fixtures ───────────────────────────────────────────
print("measure (mini)")
m = gc.measure(MINI_MAP, MINI_GRAPH)
check("rows_total 6, in_scope 5", m["rows_total"] == 6 and m["in_scope"] == 5, repr((m["rows_total"], m["in_scope"])))
check("out_of_scope == {'uxml': 1}", m["out_of_scope"] == {"uxml": 1}, repr(m["out_of_scope"]))
check("location_pct 80.0", round(m["location_pct"], 1) == 80.0, repr(m["location_pct"]))
check("behaviour_pct 60.0", round(m["behaviour_pct"], 1) == 60.0, repr(m["behaviour_pct"]))
check("location_start_only_pct 100.0", round(m["location_start_only_pct"], 1) == 100.0,
      repr(m["location_start_only_pct"]))
check("mode tree-sitter", m["mode"] == "tree-sitter", repr(m["mode"]))
check("failing_symbols names _ticks",
      isinstance(m["failing_symbols"], list) and any("_ticks" in json.dumps(x) for x in m["failing_symbols"]),
      repr(m["failing_symbols"]))

pr = m["per_row"]
check("per_row has the 5 in-scope rows", len(pr) == 5, f"got {len(pr)}")


def _pr(suffix):
    for r in pr:
        if r["file"].endswith(suffix):
            return r
    return None


expect = {
    "MiniService.cs": (True, True, {"doc"}),
    "MiniTicker.cs": (True, True, {"callers"}),
    "MiniModel.cs": (True, False, set()),
    "MiniController.cs": (False, False, set()),
    "MiniModule.cs": (True, True, {"registration"}),
}
for suffix, (loc, beh, facts) in expect.items():
    r = _pr(suffix)
    check(f"per_row {suffix} located={loc}", r is not None and r["located"] is loc, repr(r))
    check(f"per_row {suffix} behaviour={beh}", r is not None and r["behaviour"] is beh, repr(r))
    check(f"per_row {suffix} facts={sorted(facts)}", r is not None and set(r["facts"]) == facts, repr(r))

# ── 4. detect_mode ────────────────────────────────────────────────────────
print("detect_mode")
with open(MINI_GRAPH, encoding="utf-8") as f:
    mini_g = json.load(f)
check("mini graph -> tree-sitter", gc.detect_mode(mini_g) == "tree-sitter")
g2 = json.loads(json.dumps(mini_g))
g2["codebase"]["classes"][0]["confidence"] = "INFERRED"
check("one non-EXTRACTED class -> regex", gc.detect_mode(g2) == "regex")
g3 = json.loads(json.dumps(mini_g))
g3["validation"]["warnings"].append({"code": "FALLBACK_EXTRACTOR",
                                     "message": "tree-sitter unavailable — pub/sub + registration data is LOW CONFIDENCE"})
check("FALLBACK_EXTRACTOR warning -> regex", gc.detect_mode(g3) == "regex")

# ── 5. CLI ────────────────────────────────────────────────────────────────
print("CLI")
p = _run_cli("--code-map", MINI_MAP, "--graph", MINI_GRAPH, "--json")
check("--json exits 0", p.returncode == 0, p.stderr[-300:])
try:
    d = json.loads(p.stdout)
except ValueError:
    d = {}
    check("--json output parses", False, p.stdout[:200])
want = ["mode", "rows_total", "in_scope", "out_of_scope", "location_pct", "behaviour_pct",
        "location_start_only_pct", "per_row", "failing_symbols"]
check("--json has all keys", all(k in d for k in want), repr(sorted(d)))
check("--json values match measure()", d.get("rows_total") == 6 and round(d.get("location_pct", -1), 1) == 80.0)
check("--gate-location 100 -> exit 1",
      _run_cli("--code-map", MINI_MAP, "--graph", MINI_GRAPH, "--gate-location", "100").returncode == 1)
check("--gate-location 50 -> exit 0",
      _run_cli("--code-map", MINI_MAP, "--graph", MINI_GRAPH, "--gate-location", "50").returncode == 0)
check("--gate-behaviour 60 -> exit 0 (boundary)",
      _run_cli("--code-map", MINI_MAP, "--graph", MINI_GRAPH, "--gate-behaviour", "60").returncode == 0)
check("--gate-behaviour 61 -> exit 1",
      _run_cli("--code-map", MINI_MAP, "--graph", MINI_GRAPH, "--gate-behaviour", "61").returncode == 1)
check("missing --graph path -> exit 2",
      _run_cli("--code-map", MINI_MAP, "--graph", os.path.join(_FIX, "does-not-exist.json")).returncode == 2)
check("missing --code-map path -> exit 2",
      _run_cli("--code-map", os.path.join(_FIX, "nope.md"), "--graph", MINI_GRAPH).returncode == 2)

# ── 6. Plan acceptance: real map vs mini graph ────────────────────────────
print("plan acceptance")
pa = _run_cli("--code-map", REAL_MAP, "--graph", MINI_GRAPH, "--json")
try:
    da = json.loads(pa.stdout)
except ValueError:
    da = {}
check("CLI: 13-power-readout vs mini graph -> 34 27", (da.get("rows_total"), da.get("in_scope")) == (34, 27),
      repr((da.get("rows_total"), da.get("in_scope"))))
ma = gc.measure(REAL_MAP, MINI_GRAPH)
check("measure(): 13-power-readout vs mini graph -> 34 27", (ma["rows_total"], ma["in_scope"]) == (34, 27))
check("out_of_scope on real map",
      ma["out_of_scope"] == {"asmdef": 1, "unity": 1, "asset": 1, "uxml": 1, "uss": 1, "md": 2},
      repr(ma["out_of_scope"]))

_finish()
