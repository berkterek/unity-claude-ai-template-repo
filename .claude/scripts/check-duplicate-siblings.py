#!/usr/bin/env python3
"""Find hand-duplicated sibling GameObjects in .prefab / .unity files.

Enforces the *detectable* half of unity-prefabs.md Card 5. Card 5's test has three
conditions -- same parent, same component set, edited together -- and only the first
two are machine-checkable. The third is human judgement, which is why a hit here is a
question for the gate, not a verdict.

Detection is STRUCTURAL, never name-based. An earlier version of this check lived in
Card 5 as a grep over `m_Name:` ending in a digit; it was measured and found blind to
`Heart (1)` / `Heart (2)` -- Unity's own default naming when you press Cmd+D in the
Hierarchy, i.e. the single most common way a duplicate is created. Do not reintroduce
a name-based test.

Usage:
    python3 .claude/scripts/check-duplicate-siblings.py [path ...]

With no arguments it scans every `_GameFolders` and `_Scenes` directory under the
current tree. Third-party asset folders are excluded -- vendor demo scenes are full of
legitimate duplication that nobody in this project is going to refactor.

Known limit: a GameObject's signature is its OWN components, never its subtree. Two
identical *branches* (a duplicated HeartRow, each with its own children) are therefore
not detected -- only the leaf-level duplication inside them is. Card 5's judgement call
still belongs to the reviewer; this script narrows where to look, it does not replace it.

Exit codes:
    0  no duplicate sibling groups
    1  at least one group found -- extract it to a prefab, or record a written
       justification at the gate. Never close a hit by editing this script.
"""

import collections
import pathlib
import re
import sys

# A GameObject whose ONLY component is a transform carries nothing to extract, so it can
# never be the subject of Card 5. Two cases land here and both must be excluded:
#   - class 4   Transform       the six mandated scene containers ([Setup] ... [VFX]);
#                               scene-hierarchy.md requires them AND forbids them from
#                               being prefabs, so they would be a permanent false positive
#   - class 224 RectTransform   empty UI grouping nodes (Header/Footer, Left/Right), which
#                               are ordinary layout structure, not duplicated content
# Measured: without the 224 case, two sibling grouping nodes are reported as a duplicate.
ORGANIZER_ONLY = ("4", "224")

EXCLUDED_PARTS = ("Library", "Packages", "Plugins", "_AssetFolders", "PackageCache")


def parse(text):
    """Return {gameobject_id: (name, [component_ids])}, {component_id: type}, {gameobject_id: parent_transform_id}."""
    gos, types, father = {}, {}, {}
    for block in re.split(r"\n--- ", text):
        head = re.match(r"!u!(\d+) &(\d+)", block)
        if not head:
            continue
        class_id, object_id = head.group(1), head.group(2)
        if class_id == "1":
            name = re.search(r"m_Name: (.+)", block)
            gos[object_id] = (
                name.group(1).strip() if name else "?",
                re.findall(r"component: \{fileID: (\d+)\}", block),
            )
            continue
        kind = class_id
        if class_id == "114":  # MonoBehaviour -- the script identity is what matters
            # m_EditorClassIdentifier is populated only for scripts compiled into a
            # package assembly; the project's OWN scripts (Assembly-CSharp) carry an
            # EMPTY one. Keying on it alone collapsed every project script to "114:",
            # so two siblings holding DIFFERENT scripts compared equal -- measured, and
            # invisible in a run whose hits happened to be package components (TMP, Image).
            # The m_Script guid is always present and always distinct; prefer it, and
            # keep the identifier only as a human-readable label.
            guid = re.search(r"m_Script: \{fileID: -?\d+, guid: ([0-9a-f]+)", block)
            ident = re.search(r"m_EditorClassIdentifier: (.+)", block)
            label = ident.group(1).strip().split(".")[-1] if ident else ""
            kind = "114:" + (guid.group(1) if guid else "?") + (":" + label if label else "")
        types[object_id] = kind
        go = re.search(r"m_GameObject: \{fileID: (\d+)\}", block)
        parent = re.search(r"m_Father: \{fileID: (\d+)\}", block)
        if go and parent:
            father[go.group(1)] = parent.group(1)
    return gos, types, father


def groups_in(path):
    gos, types, father = parse(path.read_text(errors="ignore"))
    signature = collections.defaultdict(list)
    for object_id, (name, components) in gos.items():
        component_set = tuple(sorted(types.get(c, "?") for c in components))
        if len(component_set) == 1 and component_set[0] in ORGANIZER_ONLY:
            continue
        signature[(father.get(object_id, "?"), component_set)].append(name)
    return [(sorted(names), key[1]) for key, names in sorted(signature.items()) if len(names) > 1]


def roots_from(argv):
    if argv:
        return [pathlib.Path(a) for a in argv]
    found = [
        d
        for d in pathlib.Path(".").rglob("*")
        if d.is_dir()
        and d.name in ("_GameFolders", "_Scenes")
        and not any(part in EXCLUDED_PARTS for part in d.parts)
    ]
    return found or [pathlib.Path(".")]


def main(argv):
    files = []
    for root in roots_from(argv):
        if root.is_file():
            files.append(root)
            continue
        for path in sorted(root.rglob("*")):
            if path.suffix in (".prefab", ".unity") and not any(
                part in EXCLUDED_PARTS for part in path.parts
            ):
                files.append(path)

    if not files:
        print("NO PREFAB OR SCENE FILES FOUND — this is NOT a pass. Check the path you passed.")
        return 1

    hits = 0
    for path in files:
        for names, component_set in groups_in(path):
            hits += 1
            print("%s\n    %s  [%s]" % (path, names, ",".join(component_set)))

    print("\nchecked: %d prefab/scene files (unity-prefabs.md Card 5, structural)" % len(files))
    print("duplicate sibling groups: %d" % hits)
    if hits:
        print(
            "\nEach group is a question, not a verdict: same parent and same component set are\n"
            "measurable, 'edited together' is not. Extract it to a prefab (plus a layout component\n"
            "on the parent — Card 5's GOTCHA), or record why it is not duplication."
        )
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
