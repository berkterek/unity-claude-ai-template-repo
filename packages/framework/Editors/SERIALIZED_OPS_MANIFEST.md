# Serialized Ops — manifest format

Input format for the Editor tool that writes serialized properties into prefabs and assets.
This file is the contract. The source is not the documentation.

## Running it

1. Write the manifest to `Temp/serialized-ops.json` (project root, not under `Assets/`).
2. Trigger the menu item `Tools/Framework/Apply Serialized Ops`.
   From an agent: MCP `execute_menu_item` with that exact path.
3. Read `Temp/serialized-ops-result.json`.

The result file is **deleted before every run**, so its presence means this run produced it.
Its absence after a run means the tool never reached the write — treat that as a failure,
not as "no output". Do not parse the console; the log is a human summary of the same data.

## Envelope

```json
{ "version": 1, "ops": [ /* … */ ] }
```

`version` is required and must be exactly `1`. Any other value refuses the **whole** manifest
— no op runs, `aborted` is true, `statuses` is empty. Unparseable JSON does the same.
A missing or non-array `ops` also aborts.

## Fields shared by every op

| Field | Required | Meaning |
|---|---|---|
| `op` | yes | `setValue`, `setRef` or `addComponent` |
| `asset` | yes | Project-relative path, e.g. `Assets/_GameFolders/Prefabs/Items/Apple.prefab` |
| `object` | no | `/`-separated transform path **relative to the prefab root**, passed to `Transform.Find`. `"Body"` and `"Body/Mesh"` both work. **Omit the field for the root** — not `""`, not `"/"`. Ignored for a non-prefab asset. |
| `component` | no | Component type on that transform. Omit to target the GameObject itself. Short name (`BoxCollider`) or full name (`UnityEngine.BoxCollider`); an ambiguous short name fails the op rather than picking one. |

Ops are grouped by `asset`, so each asset is opened and saved once regardless of how many ops
target it. Within one asset they run in listed order, and each op's write lands before the
next op reads — so resizing an array and then filling the new element in one manifest works.

## `setValue`

| Field | Required | Meaning |
|---|---|---|
| `property` | yes | Serialized property path (see **Property paths**) |
| `value` | yes | Scalar matching the property's type |

Supported property types: float, integer, boolean, string, enum, Vector2, Vector3, Color, and
array length (an `Array.size` path — its own type, see **Property paths**).
Anything else fails the op with the type named.

Enums take an **integer index**, never a name — enum display order can differ from declared
values, so a name would have to be guessed. A string is rejected, not interpreted.

Vectors and colors are objects: `{"x":0,"y":1,"z":2}`, `{"r":1,"g":0,"b":0,"a":1}` (`a`
defaults to 1).

## `setRef`

| Field | Required | Meaning |
|---|---|---|
| `property` | yes | Must be an object-reference property; a non-reference fails the op |
| `ref` | yes | Object describing what to point at |

`ref` takes the same `asset` / `object` / `component` shape as an op. `asset` is required.
With no `object` and no `component`, the asset itself is the reference (a texture, a material,
a ScriptableObject, a prefab root asset).

**Pointing into the prefab being edited** — a self-reference, e.g. a component on a child
referring to something on the root — is detected by `ref.asset` equalling the op's `asset`,
and resolves against the copy currently open. Any other `ref.asset` resolves against the
asset on disk. This distinction is load-bearing: a reference to a temporarily opened copy of
a *different* prefab dies when that copy unloads and reads back empty.

There is no way to clear a reference to None. Add one when a case needs it.

## `addComponent`

| Field | Required | Meaning |
|---|---|---|
| `type` | yes | Component type name, same matching rules as `component` |

Must target a GameObject, so do not pass `component`. A type already present is a **success
no-op**, not an error, which makes a manifest safe to re-run.

## Property paths

`property` is Unity's own serialized path, the same string the Inspector debug view shows.

| Target | Path |
|---|---|
| Plain field | `_moveSpeed` |
| Nested field | `_settings._radius` |
| Array element's field | `_boosters.Array.data[0]._prefab` |
| Array length | `_boosters.Array.size` |

Growing an array is a `setValue` on `Array.size`. That path is **not** an integer property —
Unity gives array length its own property type — so the tool handles it as a named case. An
earlier version of this file claimed it was an integer and the tool matched that claim; both
were wrong, and array resize silently failed the op until it was measured against a real
prefab. Supported property types above are the whole list; nothing falls through by analogy.

> **Unity fills a grown array with copies of the last element, not with defaults.** After a
> resize, write every field of the new element explicitly. Skipping one leaves the previous
> element's value in place, silently and with no error anywhere.

## Result

```json
{
  "Success": false,
  "Aborted": false,
  "AbortReason": null,
  "Statuses": [
    { "Index": 0, "Op": "setValue", "Asset": "…", "Property": "m_IsTrigger",
      "Success": true, "Message": "set to True" }
  ]
}
```

`Index` is the op's position in the request array, so a status always maps back to the op
that produced it even when ops were regrouped by asset.

`Success` at the top level is true only when nothing aborted and **every** status succeeded.
An empty `ops` array is not a success.

A failing op does not stop the others: the rest of the manifest still runs, and each failure
carries its own reason. An aborted manifest is the opposite — nothing ran at all.

Every op is re-read from a fresh load of the saved asset before it is reported. A write that
reported success but did not persist is rewritten as a failure with a `read-back failed:`
message. That case is the entire reason this tool exists, so never treat it as a warning.
