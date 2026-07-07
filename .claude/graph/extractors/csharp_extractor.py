#!/usr/bin/env python3
# csharp_extractor.py — tree-sitter C# AST extractor.
# Optional dep: pip install tree-sitter tree-sitter-c-sharp
# Exit codes: 0=success, 1=parse error, 2=tree-sitter unavailable
import sys
import json
import argparse
import os
import re


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


def _detect_vcontainer(class_body, src):
    """Detect builder.Register* and eventBus.Subscribe/Publish patterns."""
    registrations = []
    pub_sub = []
    text = _node_text(class_body, src)
    # Register<T>, RegisterInstance<T>, RegisterComponent<T>, RegisterEntryPoint<T>
    for m in re.finditer(r'builder\.Register(?:Instance|Component|EntryPoint)?<([A-Za-z0-9_]+)>', text):
        registrations.append({"type": m.group(1), "as": "", "lifetime": ""})
    # RegisterInstance(obj) — type from variable name not available, skip
    # Any field name ending with eventBus / _eventBus / bus etc.
    for m in re.finditer(r'\w+\.(Publish|Subscribe|Unsubscribe)<([A-Za-z0-9_]+)>', text):
        pub_sub.append({"action": m.group(1), "event": m.group(2)})
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
        registrations, pub_sub = _detect_vcontainer(body, src) if body else ([], [])

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
