#!/usr/bin/env python3
# csharp_extractor.py — tree-sitter C# AST extractor.
# Optional dep: pip install tree-sitter tree-sitter-c-sharp
# Exit codes: 0=success, 1=parse error, 2=tree-sitter unavailable
import sys
import json
import argparse
import os


def _try_import():
    try:
        import tree_sitter_c_sharp as ts_cs
        from tree_sitter import Language, Parser
        return Language(ts_cs.language()), Parser
    except Exception as e:
        print(f"csharp_extractor.py: tree-sitter unavailable ({e})", file=sys.stderr)
        sys.exit(2)


def _node_text(node, src):
    return src[node.start_byte:node.end_byte].decode("utf-8", errors="replace")


def _find_children(node, kind):
    return [c for c in node.children if c.type == kind]


def _walk(node, kind, results=None):
    if results is None:
        results = []
    if node.type == kind:
        results.append(node)
    for child in node.children:
        _walk(child, kind, results)
    return results


def _extract_namespace(root, src):
    for ns_node in _walk(root, "namespace_declaration"):
        name_node = ns_node.child_by_field_name("name")
        if name_node:
            return _node_text(name_node, src)
    return ""


def _extract_accessibility(modifier_nodes, src):
    for m in modifier_nodes:
        t = _node_text(m, src)
        if t in ("public", "internal", "protected", "private"):
            return t
    return "private"


def _extract_methods(class_body, src):
    methods = []
    for m_node in _walk(class_body, "method_declaration"):
        name_node = m_node.child_by_field_name("name")
        if not name_node:
            continue
        name = _node_text(name_node, src)
        modifiers = _find_children(m_node, "modifier")
        accessibility = _extract_accessibility(modifiers, src)
        mod_texts = [_node_text(m, src) for m in modifiers]
        is_async = "async" in mod_texts
        is_static = "static" in mod_texts
        ret_node = m_node.child_by_field_name("type")
        ret_type = _node_text(ret_node, src) if ret_node else ""
        methods.append({
            "name": name,
            "line": m_node.start_point[0] + 1,
            "accessibility": accessibility,
            "is_async": is_async,
            "is_static": is_static,
            "return_type": ret_type,
        })
    return methods


def _extract_invocations(class_body, src):
    calls = []
    for inv in _walk(class_body, "invocation_expression"):
        func_node = inv.child_by_field_name("function")
        if func_node:
            calls.append(_node_text(func_node, src))
    return calls


_TYPE_NODES = {"identifier", "qualified_name", "generic_name", "predefined_type"}


def _type_name(node, src):
    # normalize any type node to its LAST segment (Ns.Outer<Foo> -> Outer)
    if node is None:
        return None
    if node.type == "qualified_name":
        name = node.child_by_field_name("name")          # final segment (may be generic_name)
        if name is not None:
            return _type_name(name, src)
        idents = _find_children(node, "identifier")
        return _node_text(idents[-1], src) if idents else None
    if node.type == "generic_name":
        idents = _find_children(node, "identifier")
        return _node_text(idents[0], src) if idents else None
    return _node_text(node, src)  # identifier / predefined_type


def _member_name_and_typearg(func, src):        # func = member_access_expression
    name = func.child_by_field_name("name") or func.named_children[-1]
    if name.type == "identifier":
        return _node_text(name, src), None
    if name.type == "generic_name":
        idents = _find_children(name, "identifier")
        method = idents[0] if idents else None
        tal = next((c for c in name.children if c.type == "type_argument_list"), None)
        payload = next((c for c in tal.named_children if c.type in _TYPE_NODES), None) if tal else None
        return (_node_text(method, src) if method is not None else None), _type_name(payload, src)
    return None, None


def _first_arg_node(inv, src, kind_filter):
    args = inv.child_by_field_name("arguments")            # argument_list
    if not args:
        return None
    arg = next((c for c in args.named_children if c.type == "argument"), None)
    if not arg:
        return None
    return next((c for c in arg.named_children if kind_filter(c)), None)


def _first_arg_new_type(inv, src):
    oce = _first_arg_node(inv, src, lambda c: c.type == "object_creation_expression")
    if not oce:
        return None
    tnode = next((c for c in oce.named_children if c.type in _TYPE_NODES), None)
    return _type_name(tnode, src)


def _first_arg_identifier(inv, src):
    idn = _first_arg_node(inv, src, lambda c: c.type == "identifier")
    return _node_text(idn, src) if idn else None


def _detect_member(member_body, src, symbols, registrations, pub_sub):
    PUBSUB = {"Publish", "Subscribe", "Unsubscribe"}
    REG = {"Register", "RegisterInstance", "RegisterComponent", "RegisterEntryPoint", "RegisterComponentInHierarchy"}
    for inv in _walk(member_body, "invocation_expression"):
        func = inv.child_by_field_name("function")
        if not func:
            continue
        if func.type == "conditional_access_expression":
            # null-conditional call: `_eventBus?.Publish(...)` — the callee name
            # lives on the nested member_binding_expression, not directly on `func`.
            func = next((c for c in func.children if c.type == "member_binding_expression"), None)
            if not func:
                continue
        elif func.type != "member_access_expression":
            continue
        method, type_arg = _member_name_and_typearg(func, src)
        if method in PUBSUB:
            ev = type_arg or _first_arg_new_type(inv, src)   # generic wins -> no double count
            if ev:
                pub_sub.append({"action": method, "event": ev})
        elif method in REG:
            t = type_arg
            if not t and method == "RegisterInstance":
                t = _first_arg_new_type(inv, src) or symbols.get(_first_arg_identifier(inv, src), "")
            reg = {"type": t or "", "as": "", "lifetime": ""}   # never skip
            if not t:
                reg["unresolved"] = True
                reg["confidence"] = "AMBIGUOUS"   # D3
            registrations.append(reg)


def _class_field_symbols(cls_node, src):
    syms = {}
    body = cls_node.child_by_field_name("body")
    if not body:
        return syms
    for fd in _find_children(body, "field_declaration"):
        vd = next((c for c in fd.named_children if c.type == "variable_declaration"), None)
        if not vd:
            continue
        tnode = next((c for c in vd.named_children if c.type in _TYPE_NODES), None)
        tname = _type_name(tnode, src)
        for decl in _find_children(vd, "variable_declarator"):
            nm = decl.child_by_field_name("name")
            if nm and tname:
                syms[_node_text(nm, src)] = tname
    return syms


def _local_var_symbols(member_body, src):
    syms = {}
    for lds in _walk(member_body, "local_declaration_statement"):
        vd = next((c for c in lds.named_children if c.type == "variable_declaration"), None)
        if not vd:
            continue
        tnode = next((c for c in vd.named_children if c.type in _TYPE_NODES), None)
        is_var = any(c.type == "implicit_type" for c in vd.named_children)
        for decl in _find_children(vd, "variable_declarator"):
            nm = decl.child_by_field_name("name")
            if not nm:
                continue
            tname = _type_name(tnode, src) if tnode and not is_var else None
            if not tname and is_var:
                init = next((c for c in decl.named_children if c.type == "object_creation_expression"), None)
                if init:
                    itnode = next((c for c in init.named_children if c.type in _TYPE_NODES), None)
                    tname = _type_name(itnode, src)
            if tname:
                syms[_node_text(nm, src)] = tname
    return syms


def _detect_vcontainer(cls_node, src):
    """Detect builder.Register* and eventBus.Subscribe/Publish patterns via AST walk."""
    registrations, pub_sub = [], []
    fields = _class_field_symbols(cls_node, src)
    body = cls_node.child_by_field_name("body")
    members = (_find_children(body, "method_declaration")
               + _find_children(body, "constructor_declaration")) if body else []
    for member in members:
        symbols = dict(fields)
        plist = member.child_by_field_name("parameters")
        if plist:
            for p in _find_children(plist, "parameter"):
                pn = p.child_by_field_name("name")
                pt = p.child_by_field_name("type")
                if pn and pt:
                    symbols[_node_text(pn, src)] = _type_name(pt, src)
        mbody = member.child_by_field_name("body")
        if mbody:
            symbols.update(_local_var_symbols(mbody, src))
            _detect_member(mbody, src, symbols, registrations, pub_sub)
    return registrations, pub_sub


def extract_file(parser, path, src=None):
    if src is None:
        try:
            src = open(path, "rb").read()
        except Exception as e:
            print(f"csharp_extractor.py: cannot read {path}: {e}", file=sys.stderr)
            return {"classes": [], "interfaces": [], "events": [], "partial_calls": []}

    tree = parser.parse(src)
    root = tree.root_node
    namespace = _extract_namespace(root, src)

    classes = []
    interfaces = []
    events = []
    partial_calls = []
    installers = []
    scopes = []

    for cls_node in _walk(root, "class_declaration"):
        name_node = cls_node.child_by_field_name("name")
        if not name_node:
            continue
        name = _node_text(name_node, src)
        line = cls_node.start_point[0] + 1

        # Extract class modifiers (static, sealed, etc.)
        class_modifiers = _find_children(cls_node, "modifier")
        class_mod_texts = [_node_text(m, src) for m in class_modifiers]
        is_static = "static" in class_mod_texts

        # Base types — tree-sitter-c-sharp uses base_list named child, not "bases" field
        base_types = []
        bases_node = cls_node.child_by_field_name("bases")
        if not bases_node:
            for child in cls_node.named_children:
                if child.type == "base_list":
                    bases_node = child
                    break
        if bases_node:
            for bt in _walk(bases_node, "identifier"):
                base_types.append(_node_text(bt, src))

        implements = [b for b in base_types if b.startswith("I") and len(b) > 1 and b[1].isupper()]
        is_mono = "MonoBehaviour" in base_types

        body = cls_node.child_by_field_name("body")
        methods = _extract_methods(body, src) if body else []
        registrations, pub_sub = _detect_vcontainer(cls_node, src)

        events_published = [p["event"] for p in pub_sub if p["action"] == "Publish"]
        events_subscribed = [p["event"] for p in pub_sub if p["action"] in ("Subscribe", "Unsubscribe")]

        invocations = _extract_invocations(body, src) if body else []
        for inv in invocations:
            partial_calls.append({
                "caller": f"{name}",
                "callee": inv,
                "file": path,
                "line": 0,
                "confidence": "EXTRACTED",
            })

        is_installer = name.endswith("Installer") or (name.endswith("Module") and is_static)
        is_scope = "LifetimeScope" in base_types
        entry = {"name": name, "file": path, "source_file": path, "registrations": registrations}
        if is_scope:
            scopes.append(entry)
        elif is_installer:
            installers.append(entry)

        classes.append({
            "name": name,
            "namespace": namespace,
            "file": path,
            "source_file": path,
            "line": line,
            "base_types": base_types,
            "is_mono_behaviour": is_mono,
            "implements": implements,
            "dependencies": [],
            "events_published": events_published,
            "events_subscribed": events_subscribed,
            "has_static_instance": False,
            "methods": methods,
            "confidence": "EXTRACTED",
        })

    for struct_node in _walk(root, "struct_declaration"):
        name_node = struct_node.child_by_field_name("name")
        if not name_node:
            continue
        name = _node_text(name_node, src)
        # Collect base types using same base_list fallback
        struct_bases = []
        sb_node = struct_node.child_by_field_name("bases")
        if not sb_node:
            for child in struct_node.named_children:
                if child.type == "base_list":
                    sb_node = child
                    break
        if sb_node:
            for bt in _walk(sb_node, "identifier"):
                struct_bases.append(_node_text(bt, src))
        if "IEvent" in struct_bases:
            events.append({
                "name": name,
                "namespace": namespace,
                "file": path,
                "source_file": path,
                "line": struct_node.start_point[0] + 1,
                "confidence": "EXTRACTED",
            })

    for iface_node in _walk(root, "interface_declaration"):
        name_node = iface_node.child_by_field_name("name")
        if not name_node:
            continue
        name = _node_text(name_node, src)
        interfaces.append({
            "name": name,
            "namespace": namespace,
            "file": path,
            "source_file": path,
            "line": iface_node.start_point[0] + 1,
            "implementers": [],
            "confidence": "EXTRACTED",
        })

    return {
        "classes": classes,
        "interfaces": interfaces,
        "events": events,
        "partial_calls": partial_calls,
        "vcontainer": {"installers": installers, "scopes": scopes},
    }


def main():
    ap = argparse.ArgumentParser(
        description="C# AST extractor using tree-sitter. Exit 2 if tree-sitter unavailable."
    )
    ap.add_argument("--changed-files", default="", help="Comma-separated list of .cs files")
    args = ap.parse_args()

    lang, ParserCls = _try_import()
    parser = ParserCls()
    parser.language = lang

    files = [f.strip() for f in args.changed_files.split(",") if f.strip().endswith(".cs")]
    if not files:
        # No .cs files — emit empty valid output (caller can decide)
        print(json.dumps({
            "classes": [], "interfaces": [], "events": [],
            "vcontainer": {"installers": [], "scopes": []}, "partial_calls": [],
        }))
        return

    out = {
        "classes": [],
        "interfaces": [],
        "events": [],
        "vcontainer": {"installers": [], "scopes": []},
        "partial_calls": [],
    }
    for f in files:
        if not os.path.isfile(f):
            continue
        r = extract_file(parser, f)
        out["classes"].extend(r["classes"])
        out["interfaces"].extend(r["interfaces"])
        out["events"].extend(r["events"])
        out["partial_calls"].extend(r["partial_calls"])
        out["vcontainer"]["installers"].extend(r.get("vcontainer", {}).get("installers", []))
        out["vcontainer"]["scopes"].extend(r.get("vcontainer", {}).get("scopes", []))

    print(json.dumps(out))


if __name__ == "__main__":
    main()
