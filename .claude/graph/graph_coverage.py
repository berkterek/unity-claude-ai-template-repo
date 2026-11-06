#!/usr/bin/env python3
"""Code-map x graph coverage report — LOCATION / BEHAVIOUR / extractor mode.

Measures how much of a module code-map the knowledge graph can answer:
LOCATION  = every symbol of a row resolves to a record with line+end_line
            (registrations: line only).
BEHAVIOUR = every symbol of a located row has a doc summary, a caller, or a
            registration fact.
Exit codes: 0 ok, 1 gate missed, 2 input error. Stdlib only.
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import graph_bfs_core

ROW_RE = re.compile(r"^\|(.+)\|\s*$")
TICK_RE = re.compile(r"`([^`]+)`")
REG_RE = re.compile(r"^(Register\w*)<([A-Za-z0-9_.]+)>")
ALIAS_RE = re.compile(r"Base\s+`(\w+)`\s*=\s*`([^`]+)`")
ARROW_RE = re.compile(r"\s*(?:->|→)\s*")
NEW_RE = re.compile(r"^\s*\(new\)")
ARGS_RE = re.compile(r"\(.*\)\s*$")
MEMBER_KEYS = ("methods", "properties", "fields", "events")


def normalise_symbol(tok):
    tok = ARGS_RE.sub("", tok.strip()).strip()
    if not tok:
        return None
    m = REG_RE.match(tok)
    if m:
        return {"kind": "reg", "method": m.group(1), "targ": m.group(2)}
    if "." in tok:
        owner, member = tok.rsplit(".", 1)
        owner = owner.rsplit(".", 1)[-1]
        if owner and member:
            return {"kind": "name", "owner": owner, "member": member}
    return {"kind": "name", "owner": None, "member": tok}


def _symbols_of(cell):
    out = []
    for m in TICK_RE.finditer(cell):
        if NEW_RE.match(cell[m.end():]):
            continue
        for part in ARROW_RE.split(m.group(1)):
            sym = normalise_symbol(part)
            if sym is not None:
                out.append(sym)
    return out


def parse_code_map(text):
    aliases = {}
    rows = []
    in_table = False
    for line in text.splitlines():
        am = ALIAS_RE.search(line)
        if am and not in_table:
            aliases[am.group(1)] = am.group(2)
        if not ROW_RE.match(line):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if not in_table:
            if cells and all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
                in_table = True
            continue
        if len(cells) < 4:
            continue
        file = cells[1].strip("`").strip()
        for key, val in aliases.items():
            if file.startswith(key + "/"):
                file = val + file[len(key):]
                break
        ext = os.path.splitext(file)[1].lstrip(".")
        rows.append({
            "file": file,
            "symbols": _symbols_of(cells[2]),
            "hint": cells[3],
            "in_scope": ext == "cs",
            "ext": ext,
        })
    return aliases, rows


def index_graph(g):
    cb = g.get("codebase", {}) or {}
    files = defaultdict(lambda: {"types": [], "regs": []})
    by_name = {}
    for rec in (cb.get("classes") or []) + (cb.get("interfaces") or []):
        f = rec.get("file") or rec.get("source_file")
        files[f]["types"].append(rec)
        by_name.setdefault(rec.get("name"), rec)
    vc = cb.get("vcontainer", {}) or {}
    all_regs = []
    for group in (vc.get("installers") or []) + (vc.get("scopes") or []):
        f = group.get("file") or group.get("source_file")
        for reg in group.get("registrations") or []:
            files[f]["regs"].append(reg)
            all_regs.append(reg)
    return {"files": files, "by_name": by_name, "regs": all_regs}


def _resolved(rec, kind, typ=None):
    return {"line": rec.get("line"), "end_line": rec.get("end_line"),
            "kind": kind, "record": rec, "type": typ}


def _find_member(trec, name):
    for key in MEMBER_KEYS:
        for mem in trec.get(key) or []:
            if mem.get("name") == name:
                return _resolved(mem, key[:-1] if key != "properties" else "property", trec)
    return None


def _reg_matches(reg, targ):
    if targ in (reg.get("type"), reg.get("as"), reg.get("factory_of")):
        return True
    return targ in (reg.get("as_resolved") or [])


def resolve(sym, row_file, idx):
    entry = idx["files"].get(row_file)
    if entry is None:
        return None
    if sym["kind"] == "reg":
        for reg in entry["regs"]:
            if reg.get("method") == sym["method"] and _reg_matches(reg, sym["targ"]):
                return _resolved(reg, "registration")
        return None
    owner, member = sym["owner"], sym["member"]
    if owner is not None:
        trec = idx["by_name"].get(owner)
        for t in entry["types"]:
            if t.get("name") == owner:
                trec = t
        return _find_member(trec, member) if trec is not None else None
    for t in entry["types"]:
        if t.get("name") == member:
            return _resolved(t, "type")
    for t in entry["types"]:
        found = _find_member(t, member)
        if found:
            return found
    return None


def primary_type(row_file, idx):
    types = idx["files"].get(row_file, {}).get("types", [])
    stem = os.path.splitext(os.path.basename(row_file))[0]
    for t in types:
        if t.get("name") == stem:
            return t
    return types[0] if types else None


def _is_located(res):
    if res is None:
        return False
    if res["kind"] == "registration":
        return _is_int(res["line"])
    return _is_int(res["line"]) and _is_int(res["end_line"])


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def _has_callers(node, g, bfs_ctx):
    fwd, rev, edges = bfs_ctx
    return bool(graph_bfs_core.callers_core(node, g, fwd, rev, edges).get("ok"))


def behaviour_facts(res, g, idx, bfs_ctx):
    facts = []
    rec, kind = res["record"], res["kind"]
    doc = rec.get("doc") or {}
    if (doc.get("summary") or "").strip():
        facts.append("doc")
    if kind == "registration":
        if rec.get("method"):
            facts.append("registration")
        return facts
    if kind == "type":
        name = rec.get("name")
        if _has_callers(name, g, bfs_ctx):
            facts.append("callers")
        if any(name in (r.get("type"), r.get("as"), r.get("factory_of"))
               or name in (r.get("as_resolved") or []) for r in idx["regs"]):
            facts.append("registration")
    else:
        node = f"{res['type'].get('name')}.{rec.get('name')}"
        if _has_callers(node, g, bfs_ctx):
            facts.append("callers")
    return facts


def detect_mode(g):
    cb = g.get("codebase", {}) or {}
    for c in cb.get("classes") or []:
        if c.get("confidence") != "EXTRACTED":
            return "regex"
    warnings = (g.get("validation", {}) or {}).get("warnings") or []
    for w in warnings:
        if isinstance(w, dict) and w.get("code") == "FALLBACK_EXTRACTOR":
            return "regex"
    return "tree-sitter"


def _build_bfs_ctx(g):
    edges = (g.get("codebase", {}) or {}).get("calls", []) or []
    forward, reverse = defaultdict(set), defaultdict(set)
    for e in edges:
        caller, callee = e.get("caller", ""), e.get("callee", "")
        if caller and callee:
            forward[caller].add(callee)
            reverse[callee].add(caller)
    return forward, reverse, edges


def _label(sym):
    if sym["kind"] == "reg":
        return f"{sym['method']}<{sym['targ']}>"
    return f"{sym['owner']}.{sym['member']}" if sym["owner"] else sym["member"]


def _measure_row(row, g, idx, bfs_ctx, failing):
    syms = row["symbols"]
    resolved = []
    if syms:
        resolved = [(_label(s), resolve(s, row["file"], idx)) for s in syms]
    else:
        ptype = primary_type(row["file"], idx)
        resolved = [(os.path.basename(row["file"]), _resolved(ptype, "type") if ptype else None)]
    located = bool(resolved) and all(_is_located(r) for _, r in resolved)
    start_only = bool(resolved) and all(r is not None and _is_int(r["line"]) for _, r in resolved)
    facts, behaviour = [], located
    # Diagnostic only: facts over resolved symbols, ranged or not — at baseline nothing has a range,
    # and gating facts on location would hide what callers/registrations already supply.
    resolved_behaviour = bool(resolved)
    for label, res in resolved:
        sym_facts = behaviour_facts(res, g, idx, bfs_ctx) if res is not None else []
        resolved_behaviour = resolved_behaviour and bool(sym_facts)
        for f in sym_facts:
            if f not in facts:
                facts.append(f)
        if not _is_located(res):
            failing.append({"file": row["file"], "symbol": label,
                            "reason": "unresolved" if res is None else "no range"})
        elif not sym_facts:
            behaviour = False
            failing.append({"file": row["file"], "symbol": label, "reason": "no behaviour fact"})
    return {"file": row["file"], "located": located, "behaviour": behaviour and located,
            "resolved_behaviour": resolved_behaviour, "facts": facts}, start_only


def _pct(n, total):
    return round(100.0 * n / total, 1) if total else 0.0


def measure(code_map_path, graph_path):
    with open(code_map_path, encoding="utf-8") as f:
        _, rows = parse_code_map(f.read())
    with open(graph_path, encoding="utf-8") as f:
        g = json.load(f)
    idx = index_graph(g)
    bfs_ctx = _build_bfs_ctx(g)
    out_of_scope = defaultdict(int)
    per_row, failing, start_only_n = [], [], 0
    for row in rows:
        if not row["in_scope"]:
            out_of_scope[row["ext"]] += 1
            continue
        result, start_only = _measure_row(row, g, idx, bfs_ctx, failing)
        per_row.append(result)
        start_only_n += 1 if start_only else 0
    total = len(per_row)
    return {
        "mode": detect_mode(g),
        "rows_total": len(rows),
        "in_scope": total,
        "out_of_scope": dict(out_of_scope),
        "location_pct": _pct(sum(r["located"] for r in per_row), total),
        "behaviour_pct": _pct(sum(r["behaviour"] for r in per_row), total),
        "location_start_only_pct": _pct(start_only_n, total),
        "behaviour_resolved_pct": _pct(sum(r["resolved_behaviour"] for r in per_row), total),
        "fact_sources": {s: sum(s in r["facts"] for r in per_row) for s in ("doc", "callers", "registration")},
        "per_row": per_row,
        "failing_symbols": failing,
    }


def main(argv):
    p = argparse.ArgumentParser(description="Code-map x graph coverage report.")
    p.add_argument("--code-map", required=True)
    p.add_argument("--graph", required=True)
    p.add_argument("--json", action="store_true")
    p.add_argument("--gate-location", type=float)
    p.add_argument("--gate-behaviour", type=float)
    args = p.parse_args(argv)
    for path in (args.code_map, args.graph):
        if not os.path.isfile(path):
            print(f"ERR_INPUT_MISSING: {path}", file=sys.stderr)
            return 2
    try:
        res = measure(args.code_map, args.graph)
    except (OSError, ValueError) as exc:
        print(f"ERR_INPUT_INVALID: {exc}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(res, indent=2))
    else:
        print(f"mode={res['mode']} rows={res['rows_total']} in_scope={res['in_scope']} "
              f"out_of_scope={res['out_of_scope']}")
        print(f"location={res['location_pct']}% (start-only {res['location_start_only_pct']}%) "
              f"behaviour={res['behaviour_pct']}%")
        for fs in res["failing_symbols"]:
            print(f"  miss {fs['file']} :: {fs['symbol']} ({fs['reason']})")
    missed = False
    if args.gate_location is not None and res["location_pct"] < args.gate_location:
        print(f"GATE FAIL: location {res['location_pct']} < {args.gate_location}", file=sys.stderr)
        missed = True
    if args.gate_behaviour is not None and res["behaviour_pct"] < args.gate_behaviour:
        print(f"GATE FAIL: behaviour {res['behaviour_pct']} < {args.gate_behaviour}", file=sys.stderr)
        missed = True
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
