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


# A LifetimeScope's parent reaches VContainer by two routes and the graph must read both:
#
#   1. Inspector — the serialized `parentReference.TypeName` on the prefab. Read by the MCP
#      extractor (mcp-extractor.md Step 2b); invisible to this file, and unavailable at all
#      when Unity is not connected.
#   2. Code — `parentReference = ParentReference.Create<AppScope>()` in the scope's Awake(),
#      before base.Awake(). Read here.
#
# Both end in the same runtime call (`LifetimeScope.GetRuntimeParent()` → `Find(Type)`), so
# neither is "the real one". The code route wins on conflict, because `Create<T>()` overwrites
# the whole struct at runtime and therefore discards whatever the Inspector had.
#
# Why this lives here and not in the MCP extractor: this is a fact about C# source, and the MCP
# extractor only runs with the Editor open — putting it there would leave a `--full` build with
# Unity closed still reporting a bare null, which is the exact misreading this exists to stop.
_PARENT_REF_CREATE = re.compile(
    r"ParentReference\s*\.\s*Create\s*<\s*([A-Za-z_][A-Za-z0-9_]*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*>"
)


def _detect_scope_parent_in_code(cls_node, src):
    """Parent type named by `ParentReference.Create<T>()` inside this class, else None.

    Returns the SHORT type name, matching how the MCP extractor reports it and how every other
    name in the graph is keyed. Comments and string literals are not stripped first: a mention
    inside a comment is a false positive here, which is the safe direction — it names a parent
    that a reader can check, rather than hiding one that exists.
    """
    m = _PARENT_REF_CREATE.search(_node_text(cls_node, src))
    if not m:
        return None
    return m.group(1).replace(" ", "").split(".")[-1] or None


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
    # Match both block-scoped `namespace N { }` and C# 10+ file-scoped
    # `namespace N;` (parsed as file_scoped_namespace_declaration) — the latter
    # was previously unmatched, silently yielding "".
    for kind in ("file_scoped_namespace_declaration", "namespace_declaration"):
        for ns_node in _walk(root, kind):
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


_NESTED_TYPE_KINDS = {
    "class_declaration", "struct_declaration", "interface_declaration",
    "record_declaration", "record_struct_declaration", "enum_declaration",
}


def _own_method_nodes(node, results):
    """method_declaration nodes belonging to THIS type. Descends through
    wrappers (e.g. `#if UNITY_EDITOR` / `#region` → preproc_* nodes) so guarded
    methods are still captured, but does NOT descend into nested type
    declarations (their methods belong to their own class entry) nor into a
    method's own body. A plain `_find_children` would drop preproc-wrapped
    methods; a plain recursive `_walk` would double-count nested-type methods."""
    for child in node.children:
        t = child.type
        if t in _NESTED_TYPE_KINDS:
            continue
        if t == "method_declaration":
            results.append(child)
            continue
        _own_method_nodes(child, results)
    return results


def _extract_methods(class_body, src):
    methods = []
    for m_node in _own_method_nodes(class_body, []):
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


def _call_method_name(name_node, src):
    """Method identifier from a member_access/binding `name` node (handles Foo<T>)."""
    if name_node is None:
        return None
    if name_node.type == "generic_name":
        idents = _find_children(name_node, "identifier")
        return _node_text(idents[0], src) if idents else None
    return _node_text(name_node, src)


def _resolve_receiver_type(recv, src, symbols, self_class, base_types):
    """Resolve a call receiver expression to its declared type name.

    Returns the type string, or None when the receiver cannot be resolved
    (chained expressions, unknown locals, element access). None callees are
    kept as raw text so downstream node-id filtering drops them.
    """
    if recv is None:
        return None
    t = recv.type
    if t == "identifier":
        tok = _node_text(recv, src)
        if tok in symbols:
            return symbols[tok]
        # Bare `Type.StaticMethod()` — receiver token IS the type (PascalCase heuristic).
        if tok and tok[0].isupper():
            return tok
        return None
    if t == "this":
        return self_class
    if t == "base":
        # First non-interface base is the base class (heuristic: not `I<Upper>`).
        for b in base_types:
            if not (b.startswith("I") and len(b) > 1 and b[1].isupper()):
                return b
        return None
    if t == "member_access_expression":
        # `this.<field>.Method()` → resolve the field via the symbol table.
        inner = recv.child_by_field_name("expression")
        nm = recv.child_by_field_name("name")
        if inner is not None and inner.type == "this" and nm is not None:
            return symbols.get(_node_text(nm, src))
        return None
    if t in ("invocation_expression", "conditional_access_expression"):
        # Fluent/lambda chain (`.AddTo(...)`, `?.Foo()`) — recurse into the inner
        # call's own receiver head. Inner return type is unknown (deferred, see
        # Task 3/4 scope note) so this only resolves via the symbol table when
        # the inner receiver head is itself a known symbol/self/base; otherwise None.
        inner_recv = recv.child_by_field_name("expression") or recv.child_by_field_name("condition")
        return _resolve_receiver_type(inner_recv, src, symbols, self_class, base_types)
    return None


def _receiver_head_token(func, src):
    """Walk a call's receiver chain to its left-most identifier/this/base token.

    Used as a fallback when `_resolve_receiver_type` cannot resolve a type
    (fluent chains, lambdas) — gives a readable `head.Method` callee instead
    of a raw multi-line node-text blob.
    """
    n = func.child_by_field_name("expression") or func.child_by_field_name("condition")
    while n is not None:
        if n.type in ("identifier", "this", "base"):
            return _node_text(n, src).strip()
        nxt = (n.child_by_field_name("expression") or n.child_by_field_name("condition")
               or n.child_by_field_name("function"))
        if nxt is None:
            break
        n = nxt
    return None


def _flatten_one_line(text):
    """Collapse whitespace and strip from the first `(` onward.

    Last-resort guard so a callee string never contains a multi-line
    node-text blob, lambda body, or `(...)` argument list.
    """
    return " ".join(text.split()).split("(", 1)[0]


def _extract_calls(cls_node, src, self_class, base_types, path):
    """Method-scoped call edges with receiver→type resolution.

    caller = `Class.Method`; callee = `ResolvedType.Method` when the receiver
    resolves, else the raw `receiver.method` text (kept for completeness,
    unlinkable at class level). Symbol table = fields + params + locals.
    """
    calls = []
    body = cls_node.child_by_field_name("body")
    if not body:
        return calls
    fields = _class_field_symbols(cls_node, src)
    members = (_find_children(body, "method_declaration")
               + _find_children(body, "constructor_declaration")
               + _find_children(body, "property_declaration"))
    for member in members:
        mn = member.child_by_field_name("name")
        method_name = (_node_text(mn, src) if mn
                       else "ctor" if member.type == "constructor_declaration" else None)
        caller = f"{self_class}.{method_name}" if method_name else self_class

        symbols = dict(fields)
        plist = member.child_by_field_name("parameters")
        if plist:
            for p in _find_children(plist, "parameter"):
                pn = p.child_by_field_name("name")
                pt = p.child_by_field_name("type")
                if pn and pt:
                    symbols[_node_text(pn, src)] = _type_name(pt, src)

        # Method blocks, expression-bodied members, and property accessors.
        bodies = []
        mbody = member.child_by_field_name("body")
        if mbody:
            bodies.append(mbody)
        for c in member.named_children:
            if c.type in ("arrow_expression_clause", "accessor_list"):
                bodies.append(c)
        heuristic_syms = set()
        for b in bodies:
            b_syms, b_heuristic = _local_var_symbols(b, src)
            symbols.update(b_syms)
            heuristic_syms.update(b_heuristic)

        for b in bodies:
            for inv in _walk(b, "invocation_expression"):
                func = inv.child_by_field_name("function")
                if not func:
                    continue
                recv_type = None
                method = None
                recv_node = None
                if func.type == "identifier":
                    # Bare `Foo()` — intra-class call on self.
                    method = _node_text(func, src)
                    recv_type = self_class
                elif func.type == "member_access_expression":
                    method = _call_method_name(func.child_by_field_name("name"), src)
                    recv_node = func.child_by_field_name("expression")
                    recv_type = _resolve_receiver_type(
                        recv_node, src, symbols, self_class, base_types)
                elif func.type == "conditional_access_expression":
                    mbe = next((c for c in func.children if c.type == "member_binding_expression"), None)
                    if mbe is not None:
                        nm = mbe.child_by_field_name("name") or (
                            mbe.named_children[-1] if mbe.named_children else None)
                        method = _call_method_name(nm, src)
                    recv_node = func.child_by_field_name("condition")
                    recv_type = _resolve_receiver_type(
                        recv_node, src, symbols, self_class, base_types)
                else:
                    continue

                # RC3: receiver type resolved via the `var x = Type.Static()`
                # heuristic (declaring type, not a verified return type) —
                # mark the edge INFERRED instead of EXTRACTED.
                confidence = "EXTRACTED"
                if (recv_node is not None and recv_node.type == "identifier"
                        and _node_text(recv_node, src) in heuristic_syms):
                    confidence = "INFERRED"

                if recv_type and method:
                    callee = f"{recv_type}.{method}"
                elif method:
                    head = _receiver_head_token(func, src)
                    callee = f"{head}.{method}" if head else method
                else:
                    callee = _flatten_one_line(_node_text(func, src))
                calls.append({
                    "caller": caller,
                    "callee": callee,
                    "caller_file": path,     # caller side IS this file — correct
                    "callee_file": None,     # RC1: resolved in graph-builder.resolve_call_targets
                    "callee_class": None,    # RC1: filled by the builder pass
                    "file": path,
                    "line": inv.start_point[0] + 1,
                    "confidence": confidence,
                })
    return calls


def _has_inject_attr(member, src):
    """True if a member carries an attribute whose name ends with `Inject`
    (covers `[Inject]`, `[Zenject.Inject]`, `[VContainer.Inject]`)."""
    for al in member.children:
        if al.type != "attribute_list":
            continue
        for at in al.children:
            if at.type != "attribute":
                continue
            an = at.child_by_field_name("name")
            nm = _type_name(an, src) if an else None
            if nm and nm.endswith("Inject"):
                return True
    return False


def _extract_dependencies(cls_node, src):
    """Constructor + [*Inject] method parameter types → deduped dependency list.

    Collects pure-C# real constructors, Zenject `[Zenject.Inject]`, and
    VContainer `[VContainer.Inject]` styles. No type filtering here — resolution
    to real graph nodes happens downstream; unresolved framework types drop out.
    """
    deps = []
    seen = set()
    body = cls_node.child_by_field_name("body")
    if not body:
        return deps
    members = (_find_children(body, "constructor_declaration")
               + [m for m in _find_children(body, "method_declaration")
                  if _has_inject_attr(m, src)])
    for member in members:
        plist = member.child_by_field_name("parameters")
        if not plist:
            continue
        for p in _find_children(plist, "parameter"):
            pt = p.child_by_field_name("type")
            tname = _type_name(pt, src) if pt else None
            if tname and tname not in seen:
                seen.add(tname)
                deps.append(tname)
    return deps


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


def _resolve_concrete(inv, src, symbols):
    """Argument-side concrete type for RegisterInstance: `new Foo(..)` then field/param symbol."""
    return _first_arg_new_type(inv, src) or symbols.get(_first_arg_identifier(inv, src), "") or ""


def _as_chain(inv, src, hops=8):
    """Exposed service from a trailing chain: `.As<IBar>()` / `.AsImplementedInterfaces()`.
    Walks UP through parents because `_detect_member` only ever sees one invocation at a
    time; the chained call is a member_access_expression on this invocation's own result.
    First `.As<T>()` wins -> always a single STRING (Chosen Approach decision 2)."""
    node = inv
    for _ in range(hops):
        ma = node.parent
        if ma is None or ma.type != "member_access_expression":
            return ""
        outer = ma.parent
        if outer is None or outer.type != "invocation_expression":
            return ""
        m, ta = _member_name_and_typearg(ma, src)
        if m == "As" and ta:
            return ta
        if m == "AsImplementedInterfaces":
            return "AsImplementedInterfaces"      # matches csharp-extractor.sh:379
        node = outer
    return ""


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
            chained = _as_chain(inv, src)
            if method == "RegisterInstance":
                concrete = _resolve_concrete(inv, src, symbols)
                if concrete:
                    reg = {"type": concrete,
                           "as": chained or (type_arg if type_arg and type_arg != concrete else ""),
                           "lifetime": ""}                    # lifetime enum: see Chosen Approach
                elif type_arg:
                    # ONLY place interface_only is ever set: RegisterInstance<IFoo>(opaqueExpr).
                    reg = {"type": type_arg, "as": chained, "lifetime": "",
                           "interface_only": True, "confidence": "INFERRED"}
                else:
                    reg = {"type": "", "as": chained, "lifetime": "",
                           "unresolved": True, "confidence": "AMBIGUOUS"}
            elif type_arg:
                # Register/RegisterComponent/RegisterEntryPoint/RegisterComponentInHierarchy:
                # the generic slot IS the concrete. Full-strength claim -> NO interface_only,
                # so INSTALLER_MISSING_CLASS keeps biting on Register<UnknownClass>(...).
                reg = {"type": type_arg, "as": chained, "lifetime": ""}
            else:
                reg = {"type": "", "as": chained, "lifetime": "",
                       "unresolved": True, "confidence": "AMBIGUOUS"}
            registrations.append(reg)   # never skip


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
    """Local variable symbol table for a method body.

    Returns `(syms, heuristic_syms)`:
      - `syms`: local name -> declared/inferred type name.
      - `heuristic_syms`: subset of `syms` keys whose type came from the
        RC3 `var x = Type.StaticMethod()` heuristic below — the declaring
        type of the invoked member, NOT necessarily the true return type
        (correct for factory/singleton idioms like `Type.FromJson`/
        `Type.Create`, wrong-but-plausible for e.g. `Mathf.Abs`). Callers
        use this set to mark downstream call-edge confidence as INFERRED
        instead of EXTRACTED.
    """
    syms = {}
    heuristic_syms = set()
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
            is_heuristic = False
            if not tname and is_var:
                init = next((c for c in decl.named_children if c.type == "object_creation_expression"), None)
                if init:
                    itnode = next((c for c in init.named_children if c.type in _TYPE_NODES), None)
                    tname = _type_name(itnode, src)
                else:
                    # RC3: `var x = Type.StaticMethod()` — receiver of the
                    # initializer invocation IS the declaring type when it's
                    # a PascalCase identifier (heuristic, not a true return type).
                    inv_init = next((c for c in decl.named_children
                                      if c.type == "invocation_expression"), None)
                    if inv_init:
                        func = inv_init.child_by_field_name("function")
                        if func is not None and func.type == "member_access_expression":
                            recv = func.child_by_field_name("expression")
                            if recv is not None and recv.type == "identifier":
                                tok = _node_text(recv, src)
                                if tok and tok[0].isupper():
                                    tname = tok
                                    is_heuristic = True
            if tname:
                name_txt = _node_text(nm, src)
                syms[name_txt] = tname
                if is_heuristic:
                    heuristic_syms.add(name_txt)
    return syms, heuristic_syms


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
            mbody_syms, _mbody_heuristic = _local_var_symbols(mbody, src)
            symbols.update(mbody_syms)
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
            # Direct base-type children only, normalized to their name — _walk on
            # "identifier" also pulled generic type ARGUMENTS (`Panel<IThing>` →
            # bogus "IThing") and qualified segments (`UnityEngine.MonoBehaviour`
            # → stray "UnityEngine").
            for bt in bases_node.named_children:
                if bt.type in _TYPE_NODES:
                    tn = _type_name(bt, src)
                    if tn:
                        base_types.append(tn)

        implements = [b for b in base_types if b.startswith("I") and len(b) > 1 and b[1].isupper()]
        is_mono = "MonoBehaviour" in base_types

        body = cls_node.child_by_field_name("body")
        methods = _extract_methods(body, src) if body else []
        registrations, pub_sub = _detect_vcontainer(cls_node, src)

        events_published = [p["event"] for p in pub_sub if p["action"] == "Publish"]
        events_subscribed = [p["event"] for p in pub_sub if p["action"] in ("Subscribe", "Unsubscribe")]

        partial_calls.extend(_extract_calls(cls_node, src, name, base_types, path))

        is_installer = name.endswith("Installer") or (name.endswith("Module") and is_static)
        is_scope = "LifetimeScope" in base_types
        entry = {"name": name, "file": path, "source_file": path, "registrations": registrations}
        if is_scope:
            code_parent = _detect_scope_parent_in_code(cls_node, src)
            if code_parent:
                entry["parent"] = code_parent
                entry["parent_source"] = "code"
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
            # field name -> declared type name (all fields, no attribute filter).
            # Persisted for graph-builder.resolve_call_targets' inherited-field
            # second-chance call resolution (Lever 1). Same map _extract_calls
            # already consumes in-process; here it is kept so the global builder
            # pass can walk base classes across files, which the per-file
            # extractor cannot.
            "field_types": _class_field_symbols(cls_node, src),
            "dependencies": _extract_dependencies(cls_node, src),
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
            for bt in sb_node.named_children:
                if bt.type in _TYPE_NODES:
                    tn = _type_name(bt, src)
                    if tn:
                        struct_bases.append(tn)
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
        iface_body = iface_node.child_by_field_name("body")
        interfaces.append({
            "name": name,
            "namespace": namespace,
            "file": path,
            "source_file": path,
            "line": iface_node.start_point[0] + 1,
            "implementers": [],
            # Interface members are bodyless method_declaration nodes — the same
            # shape _extract_methods already handles. Populating this lets
            # resolve_call_targets' method_match guard confirm interface-typed
            # calls (e.g. `_sound.Play` -> ISoundService.Play); an empty list
            # made the guard reject every interface-typed field call.
            "methods": _extract_methods(iface_body, src) if iface_body else [],
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
