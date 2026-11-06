# members_docs — expected extraction for Members.cs

Line numbers are 1-based, taken from `cat -n Members.cs`. Convention (pinned): `line`/`end_line` are the
tree-sitter declaration node's start/end line, so the node INCLUDES its attribute list — `Reset.line` is the
`[ContextMenu("Reset")]` line (40), not the `private void Reset()` line (41). `end_line` is the line of the
closing brace / semicolon of the declaration. `#if` / `#endif` lines are not part of any member range.

`signature`: modifiers + return type + name + parameter list, attributes excluded, whitespace collapsed to
single spaces (a multi-line parameter list becomes one line, spacing otherwise untouched), body / `=>` part /
`;` excluded. NOTE: `_flatten_one_line` cuts at the first `(` and must NOT be used for this.

## IShape (interface) — line 5, end_line 9
- properties: `Area` float, line 7, end_line 7, accessors [get], is_expression_bodied False

## Members (class) — line 11, end_line 63
Methods (constructor `Members()` at 26-29 must NOT appear):
| name | line | end_line | signature |
|---|---|---|---|
| Sum | 31 | 31 | `public int Sum(int x, int y)` |
| Combine | 33 | 38 | `public static int Combine(int left, int right)` |
| Reset | 40 | 45 | `private void Reset()` |
| EditorOnly (`#if UNITY_EDITOR`) | 48 | 51 | `private void EditorOnly()` |

Properties:
| name | type | line | end_line | accessibility | accessors | is_expression_bodied |
|---|---|---|---|---|---|---|
| Count | int | 18 | 18 | public | [get, set] | False |
| Name | string | 19 | 19 | public | [get] | True |
| Value | int | 20 | 24 | public | [get, set] | False |

Fields (one entry per declarator; `is_static` for the const is not pinned):
| name | type | line | end_line | accessibility | is_static | is_const | is_readonly | is_event |
|---|---|---|---|---|---|---|---|---|
| MAX_COUNT | int | 13 | 13 | public | (not pinned) | True | False | False |
| Label | string | 14 | 14 | private | True | False | True | False |
| _a | int | 15 | 15 | private | False | False | False | False |
| _b | int | 15 | 15 | private | False | False | False | False |
| Changed | Action | 16 | 16 | public | False | False | False | True |

`field_types` (unchanged by Task 3): `{MAX_COUNT: int, Label: string, _a: int, _b: int}`.

## Inner (nested class) — own class record, line 54, end_line 62
- methods: `InnerMethod` 59-61, `public void InnerMethod()`
- properties: `Hidden` int 57-57, public, [get], expression-bodied
- fields: `_hidden` int 56-56, private
- none of these appear in `Members`.

## ContextMenuAttribute (class) — line 65, end_line 70
- methods: none (constructor excluded), properties: none, fields: none.

## Class order from the extractor
Members, Inner, ContextMenuAttribute (so CLI `classes[0]` is Members, but tests look up by name).

## Docs.cs (Task 4) — XML doc comments → `doc` key
Records get `doc = {summary, remarks}` with only non-empty parts; no `doc` key at all when there is no attached
`///` block (never an empty object). Text: tags stripped, `<see cref="X"/>` / `<paramref name="x"/>` → the name,
whitespace collapsed, each part capped at DOC_CAP=300 chars + `…`.

| Record | summary | remarks |
|---|---|---|
| interface IDocService | Contract for a doc-carrying service. | – |
| IDocService.Total | Current total. | – |
| class Docs | Holds documented members across several lines. | Implements IDocService for the fixture. |
| field `_total` | Backing value for Total. | – |
| property Docs.Total | Current total. | – |
| method Add | Adds amount to the total. | Side effect: raises nothing. |
| method Long | 300 chars + `…` (len <= 301) | – (no remarks key) |
| method Attributed | Attribute sits between doc and method. | – |
| PlainComment (`//`), Detached (blank line between), Undocumented | no `doc` key | |

Attachment facts (tree-sitter-c-sharp, probed): every `///` line is its own `comment` sibling in the enclosing
`declaration_list`; a declaration's `prev_sibling` is the last `comment` line. Attached only if that comment's end
row + 1 == declaration start row (Detached has a one-row gap). Attribute lists are children INSIDE the declaration
node (start row = attribute row), so the doc comment is still `prev_sibling` (Attributed: comment row 48, decl row 49).

Plan acceptance: `python3 .claude/graph/extractors/csharp_extractor.py --changed-files <Docs.cs>` stdout contains
exactly **8** occurrences of `"summary"` (one per documented record above: IDocService, IDocService.Total, Docs,
_total, Docs.Total, Add, Long, Attributed).
