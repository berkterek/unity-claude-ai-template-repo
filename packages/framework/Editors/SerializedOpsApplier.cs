using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using UnityEditor;
using UnityEngine;

namespace Framework.Editors
{
    /// <summary>
    /// Applies a versioned JSON manifest of serialized-property operations to prefabs and assets.
    /// Domain-free by contract: no game type name may appear in this file.
    /// </summary>
    public static class SerializedOpsApplier
    {
        #region Fields

        private const int SUPPORTED_VERSION = 1;
        private const string LOG_PREFIX = "[SerializedOps]";

        #endregion

        #region Public Methods

        public static SerializedOpsResult Apply(string json)
        {
            var result = new SerializedOpsResult();

            JObject manifest;
            try
            {
                manifest = JObject.Parse(json);
            }
            catch (JsonException e)
            {
                return Abort(result, $"manifest is not valid JSON: {e.Message}");
            }

            int? version = manifest.Value<int?>("version");
            if (version == null) return Abort(result, "manifest has no 'version' field");
            if (version.Value != SUPPORTED_VERSION)
                return Abort(result, $"unknown manifest version {version.Value} (supported: {SUPPORTED_VERSION})");

            if (!(manifest["ops"] is JArray ops)) return Abort(result, "manifest has no 'ops' array");

            foreach (var group in GroupByAsset(ops, result))
            {
                ApplyToAsset(group.Key, group.Value, result);
            }

            AssetDatabase.Refresh();

            result.Success = !result.Aborted && result.Statuses.Count > 0 && result.Statuses.All(s => s.Success);
            return result;
        }

        #endregion

        #region Private Methods — orchestration

        private static Dictionary<string, List<IndexedOp>> GroupByAsset(JArray ops, SerializedOpsResult result)
        {
            var groups = new Dictionary<string, List<IndexedOp>>(StringComparer.Ordinal);

            for (int i = 0; i < ops.Count; i++)
            {
                if (!(ops[i] is JObject op))
                {
                    Fail(result, i, null, null, null, "op is not a JSON object");
                    continue;
                }

                string asset = op.Value<string>("asset");
                if (string.IsNullOrEmpty(asset))
                {
                    Fail(result, i, op.Value<string>("op"), null, op.Value<string>("property"),
                        "required field 'asset' is missing");
                    continue;
                }

                if (!groups.TryGetValue(asset, out var list))
                {
                    list = new List<IndexedOp>();
                    groups[asset] = list;
                }

                list.Add(new IndexedOp { Index = i, Op = op });
            }

            return groups;
        }

        private static void ApplyToAsset(string assetPath, List<IndexedOp> ops, SerializedOpsResult result)
        {
            if (assetPath.EndsWith(".prefab", StringComparison.OrdinalIgnoreCase))
            {
                ApplyToPrefab(assetPath, ops, result);
                return;
            }

            ApplyToPlainAsset(assetPath, ops, result);
        }

        private static void ApplyToPrefab(string assetPath, List<IndexedOp> ops, SerializedOpsResult result)
        {
            if (AssetDatabase.LoadAssetAtPath<GameObject>(assetPath) == null)
            {
                FailAll(result, ops, $"no prefab at '{assetPath}'");
                return;
            }

            GameObject root = null;
            var applied = new List<IndexedOp>();

            try
            {
                root = PrefabUtility.LoadPrefabContents(assetPath);
                foreach (var entry in ops)
                {
                    if (ApplyOne(root, assetPath, entry, result)) applied.Add(entry);
                }

                PrefabUtility.SaveAsPrefabAsset(root, assetPath);
            }
            finally
            {
                if (root != null) PrefabUtility.UnloadPrefabContents(root);
            }

            VerifyPrefab(assetPath, applied, result);
        }

        private static void ApplyToPlainAsset(string assetPath, List<IndexedOp> ops, SerializedOpsResult result)
        {
            var asset = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(assetPath);
            if (asset == null)
            {
                FailAll(result, ops, $"no asset at '{assetPath}'");
                return;
            }

            var applied = new List<IndexedOp>();
            foreach (var entry in ops)
            {
                if (ApplyOne(null, assetPath, entry, result)) applied.Add(entry);
            }

            EditorUtility.SetDirty(asset);
            AssetDatabase.SaveAssets();

            VerifyPlainAsset(assetPath, applied, result);
        }

        #endregion

        #region Private Methods — per-op dispatch

        /// <summary>Returns true when the op reported success and is therefore worth verifying.</summary>
        private static bool ApplyOne(GameObject prefabRoot, string assetPath, IndexedOp entry, SerializedOpsResult result)
        {
            JObject op = entry.Op;
            string kind = op.Value<string>("op");

            if (string.IsNullOrEmpty(kind))
                return Fail(result, entry.Index, null, assetPath, null, "required field 'op' is missing");

            UnityEngine.Object target = ResolveTarget(prefabRoot, assetPath, op, out string targetError);
            if (target == null)
                return Fail(result, entry.Index, kind, assetPath, op.Value<string>("property"), targetError);

            switch (kind)
            {
                case "addComponent":
                    return ApplyAddComponent(target, assetPath, entry, result);
                case "setRef":
                    return ApplySetRef(target, prefabRoot, assetPath, entry, result);
                case "setValue":
                    return ApplySetValue(target, assetPath, entry, result);
                default:
                    return Fail(result, entry.Index, kind, assetPath, op.Value<string>("property"),
                        $"unknown op kind '{kind}' (supported: setRef, setValue, addComponent)");
            }
        }

        private static bool ApplyAddComponent(UnityEngine.Object target, string assetPath, IndexedOp entry,
            SerializedOpsResult result)
        {
            string typeName = entry.Op.Value<string>("type");
            if (string.IsNullOrEmpty(typeName))
                return Fail(result, entry.Index, "addComponent", assetPath, null, "required field 'type' is missing");

            if (!(target is GameObject go))
                return Fail(result, entry.Index, "addComponent", assetPath, null,
                    "addComponent target must be a GameObject — remove 'component' from the op");

            Type type = ResolveComponentType(typeName, out string typeError);
            if (type == null) return Fail(result, entry.Index, "addComponent", assetPath, null, typeError);

            if (go.GetComponent(type) != null)
                return Pass(result, entry.Index, "addComponent", assetPath, null, $"'{typeName}' already present — no-op");

            go.AddComponent(type);
            return Pass(result, entry.Index, "addComponent", assetPath, null, $"added '{typeName}'");
        }

        private static bool ApplySetValue(UnityEngine.Object target, string assetPath, IndexedOp entry,
            SerializedOpsResult result)
        {
            string path = entry.Op.Value<string>("property");
            if (string.IsNullOrEmpty(path))
                return Fail(result, entry.Index, "setValue", assetPath, null, "required field 'property' is missing");

            JToken value = entry.Op["value"];
            if (value == null)
                return Fail(result, entry.Index, "setValue", assetPath, path, "required field 'value' is missing");

            var so = new SerializedObject(target);
            SerializedProperty property = so.FindProperty(path);
            if (property == null)
                return Fail(result, entry.Index, "setValue", assetPath, path,
                    $"no SerializedProperty '{path}' on {target.GetType().Name}");

            if (!WriteScalar(property, value, out string writeError))
                return Fail(result, entry.Index, "setValue", assetPath, path, writeError);

            so.ApplyModifiedPropertiesWithoutUndo();
            return Pass(result, entry.Index, "setValue", assetPath, path, $"set to {value}");
        }

        private static bool ApplySetRef(UnityEngine.Object target, GameObject prefabRoot, string assetPath,
            IndexedOp entry, SerializedOpsResult result)
        {
            string path = entry.Op.Value<string>("property");
            if (string.IsNullOrEmpty(path))
                return Fail(result, entry.Index, "setRef", assetPath, null, "required field 'property' is missing");

            if (!(entry.Op["ref"] is JObject refSpec))
                return Fail(result, entry.Index, "setRef", assetPath, path, "required field 'ref' is missing");

            UnityEngine.Object value = ResolveRef(refSpec, prefabRoot, assetPath, out string refError);
            if (value == null) return Fail(result, entry.Index, "setRef", assetPath, path, refError);

            var so = new SerializedObject(target);
            SerializedProperty property = so.FindProperty(path);
            if (property == null)
                return Fail(result, entry.Index, "setRef", assetPath, path,
                    $"no SerializedProperty '{path}' on {target.GetType().Name}");

            if (property.propertyType != SerializedPropertyType.ObjectReference)
                return Fail(result, entry.Index, "setRef", assetPath, path,
                    $"property is {property.propertyType}, not an ObjectReference — use setValue");

            property.objectReferenceValue = value;
            so.ApplyModifiedPropertiesWithoutUndo();
            return Pass(result, entry.Index, "setRef", assetPath, path, $"set to '{value.name}' ({value.GetType().Name})");
        }

        #endregion

        #region Private Methods — resolution

        /// <summary>
        /// Resolves the object an op acts on. Inside a prefab: optional 'object' is a '/'-separated
        /// transform path relative to the root (absent = root), optional 'component' names the component
        /// type on that transform (absent = the GameObject itself). For a plain asset both are ignored.
        /// </summary>
        private static UnityEngine.Object ResolveTarget(GameObject prefabRoot, string assetPath, JObject op,
            out string error)
        {
            error = null;

            if (prefabRoot == null)
            {
                var asset = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(assetPath);
                if (asset == null) error = $"no asset at '{assetPath}'";
                return asset;
            }

            GameObject go = ResolveChild(prefabRoot, op.Value<string>("object"), out error);
            if (go == null) return null;

            string componentName = op.Value<string>("component");
            if (string.IsNullOrEmpty(componentName)) return go;

            Type type = ResolveComponentType(componentName, out error);
            if (type == null) return null;

            Component component = go.GetComponent(type);
            if (component == null)
                error = $"'{go.name}' has no component '{componentName}'";
            return component;
        }

        private static GameObject ResolveChild(GameObject root, string objectPath, out string error)
        {
            error = null;
            if (string.IsNullOrEmpty(objectPath)) return root;

            Transform found = root.transform.Find(objectPath);
            if (found == null)
            {
                error = $"no transform at path '{objectPath}' under '{root.name}'";
                return null;
            }

            return found.gameObject;
        }

        /// <summary>
        /// Resolves a reference target. Always against the ASSET, never against the LoadPrefabContents
        /// copy — that copy dies at UnloadPrefabContents and the stored reference would read back as None.
        /// The one exception is a self-reference into the prefab currently open, which must resolve
        /// against the open root because the saved prefab contains exactly those objects.
        /// </summary>
        private static UnityEngine.Object ResolveRef(JObject refSpec, GameObject prefabRoot, string groupAssetPath,
            out string error)
        {
            error = null;

            string refAssetPath = refSpec.Value<string>("asset");
            if (string.IsNullOrEmpty(refAssetPath))
            {
                error = "ref is missing required field 'asset'";
                return null;
            }

            bool isSelfReference = prefabRoot != null
                                   && string.Equals(refAssetPath, groupAssetPath, StringComparison.Ordinal);

            GameObject refRoot;
            if (isSelfReference)
            {
                refRoot = prefabRoot;
            }
            else
            {
                var refAsset = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(refAssetPath);
                if (refAsset == null)
                {
                    error = $"ref asset not found at '{refAssetPath}'";
                    return null;
                }

                string refObject = refSpec.Value<string>("object");
                string refComponent = refSpec.Value<string>("component");
                if (string.IsNullOrEmpty(refObject) && string.IsNullOrEmpty(refComponent)) return refAsset;

                refRoot = refAsset as GameObject;
                if (refRoot == null)
                {
                    error = $"ref asset '{refAssetPath}' is not a prefab, so 'object'/'component' cannot apply";
                    return null;
                }
            }

            GameObject refGo = ResolveChild(refRoot, refSpec.Value<string>("object"), out error);
            if (refGo == null) return null;

            string componentName = refSpec.Value<string>("component");
            if (string.IsNullOrEmpty(componentName)) return refGo;

            Type type = ResolveComponentType(componentName, out error);
            if (type == null) return null;

            Component component = refGo.GetComponent(type);
            if (component == null)
                error = $"ref object '{refGo.name}' has no component '{componentName}'";
            return component;
        }

        /// <summary>Matches on Name or FullName; an ambiguous short name is an error, never a first-match pick.</summary>
        private static Type ResolveComponentType(string typeName, out string error)
        {
            error = null;

            if (string.IsNullOrEmpty(typeName))
            {
                error = "component type name is empty";
                return null;
            }

            var matches = TypeCache.GetTypesDerivedFrom<Component>()
                .Where(t => t.FullName == typeName || t.Name == typeName)
                .Distinct()
                .ToList();

            var exact = matches.Where(t => t.FullName == typeName).ToList();
            if (exact.Count == 1) return exact[0];

            if (matches.Count == 0)
            {
                error = $"no Component type named '{typeName}'";
                return null;
            }

            if (matches.Count > 1)
            {
                error = $"ambiguous component type '{typeName}' — matches {string.Join(", ", matches.Select(t => t.FullName))}. Use the full name.";
                return null;
            }

            return matches[0];
        }

        #endregion

        #region Private Methods — scalar write / compare

        private static bool WriteScalar(SerializedProperty property, JToken value, out string error)
        {
            error = null;

            switch (property.propertyType)
            {
                case SerializedPropertyType.Float:
                    property.floatValue = value.Value<float>();
                    return true;
                case SerializedPropertyType.Integer:
                    property.intValue = value.Value<int>();
                    return true;
                case SerializedPropertyType.ArraySize:
                    // An 'x.Array.size' path is NOT Integer — Unity gives it its own property type, and
                    // leaving it to the default branch is what made array resize impossible. Growing an
                    // array fills the new slots with copies of the last element, never with defaults,
                    // so a caller must write every field of a new element explicitly.
                    property.intValue = value.Value<int>();
                    return true;
                case SerializedPropertyType.Boolean:
                    property.boolValue = value.Value<bool>();
                    return true;
                case SerializedPropertyType.String:
                    property.stringValue = value.Value<string>();
                    return true;
                case SerializedPropertyType.Enum:
                    // Integer index only. A string name is rejected, not guessed: enumNames is display
                    // order and can differ from the declared value.
                    if (value.Type != JTokenType.Integer)
                    {
                        error = "enum value must be an integer index, not a name";
                        return false;
                    }
                    property.enumValueIndex = value.Value<int>();
                    return true;
                case SerializedPropertyType.Vector2:
                    property.vector2Value = ReadVector2(value);
                    return true;
                case SerializedPropertyType.Vector3:
                    property.vector3Value = ReadVector3(value);
                    return true;
                case SerializedPropertyType.Color:
                    property.colorValue = ReadColor(value);
                    return true;
                default:
                    error = $"unsupported property type {property.propertyType} for setValue";
                    return false;
            }
        }

        private static bool ScalarMatches(SerializedProperty property, JToken value)
        {
            switch (property.propertyType)
            {
                case SerializedPropertyType.Float:
                    return Mathf.Approximately(property.floatValue, value.Value<float>());
                case SerializedPropertyType.Integer:
                case SerializedPropertyType.ArraySize:
                    return property.intValue == value.Value<int>();
                case SerializedPropertyType.Boolean:
                    return property.boolValue == value.Value<bool>();
                case SerializedPropertyType.String:
                    return property.stringValue == value.Value<string>();
                case SerializedPropertyType.Enum:
                    return property.enumValueIndex == value.Value<int>();
                case SerializedPropertyType.Vector2:
                    return property.vector2Value == ReadVector2(value);
                case SerializedPropertyType.Vector3:
                    return property.vector3Value == ReadVector3(value);
                case SerializedPropertyType.Color:
                    return property.colorValue == ReadColor(value);
                default:
                    return false;
            }
        }

        private static Vector2 ReadVector2(JToken t) =>
            new Vector2(t.Value<float>("x"), t.Value<float>("y"));

        private static Vector3 ReadVector3(JToken t) =>
            new Vector3(t.Value<float>("x"), t.Value<float>("y"), t.Value<float>("z"));

        private static Color ReadColor(JToken t) =>
            new Color(t.Value<float>("r"), t.Value<float>("g"), t.Value<float>("b"),
                t["a"] == null ? 1f : t.Value<float>("a"));

        #endregion

        #region Private Methods — read-back verification

        /// <summary>
        /// Re-reads each applied op from a FRESH load of the saved asset. An op that reported success
        /// but did not persist is the exact bug this tool exists to make impossible, so a mismatch
        /// flips the already-recorded status to failed.
        /// </summary>
        private static void VerifyPrefab(string assetPath, List<IndexedOp> applied, SerializedOpsResult result)
        {
            if (applied.Count == 0) return;

            AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceUpdate);
            var saved = AssetDatabase.LoadAssetAtPath<GameObject>(assetPath);
            if (saved == null)
            {
                foreach (var entry in applied)
                    FailAfterReadBack(result, entry.Index, $"read-back failed: prefab '{assetPath}' did not reload");
                return;
            }

            foreach (var entry in applied) VerifyOne(saved, assetPath, entry, result);
        }

        private static void VerifyPlainAsset(string assetPath, List<IndexedOp> applied, SerializedOpsResult result)
        {
            if (applied.Count == 0) return;

            AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceUpdate);
            var saved = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(assetPath);
            if (saved == null)
            {
                foreach (var entry in applied)
                    FailAfterReadBack(result, entry.Index, $"read-back failed: asset '{assetPath}' did not reload");
                return;
            }

            foreach (var entry in applied) VerifyOne(null, assetPath, entry, result);
        }

        private static void VerifyOne(GameObject savedRoot, string assetPath, IndexedOp entry, SerializedOpsResult result)
        {
            JObject op = entry.Op;
            string kind = op.Value<string>("op");

            UnityEngine.Object target = ResolveTarget(savedRoot, assetPath, op, out string targetError);
            if (target == null)
            {
                FailAfterReadBack(result, entry.Index, $"read-back failed: {targetError}");
                return;
            }

            if (kind == "addComponent")
            {
                // ResolveTarget already proved the GameObject survives; re-check the component itself.
                Type type = ResolveComponentType(op.Value<string>("type"), out string typeError);
                if (type == null)
                {
                    FailAfterReadBack(result, entry.Index, $"read-back failed: {typeError}");
                    return;
                }

                if (!(target is GameObject go) || go.GetComponent(type) == null)
                    FailAfterReadBack(result, entry.Index, "read-back failed: component is absent after save");
                return;
            }

            string path = op.Value<string>("property");
            SerializedProperty property = new SerializedObject(target).FindProperty(path);
            if (property == null)
            {
                FailAfterReadBack(result, entry.Index, $"read-back failed: property '{path}' is absent after save");
                return;
            }

            if (kind == "setRef")
            {
                if (property.objectReferenceValue == null)
                    FailAfterReadBack(result, entry.Index, "read-back failed: reference is None after save");
                return;
            }

            if (!ScalarMatches(property, op["value"]))
                FailAfterReadBack(result, entry.Index, "read-back failed: value did not persist");
        }

        #endregion

        #region Private Methods — status bookkeeping

        private static SerializedOpsResult Abort(SerializedOpsResult result, string reason)
        {
            result.Aborted = true;
            result.AbortReason = reason;
            result.Success = false;
            Debug.LogError($"{LOG_PREFIX} Manifest aborted — {reason}");
            return result;
        }

        private static bool Pass(SerializedOpsResult result, int index, string op, string asset, string property,
            string message)
        {
            result.Statuses.Add(new SerializedOpStatus
            {
                Index = index, Op = op, Asset = asset, Property = property, Success = true, Message = message
            });
            return true;
        }

        private static bool Fail(SerializedOpsResult result, int index, string op, string asset, string property,
            string reason)
        {
            result.Statuses.Add(new SerializedOpStatus
            {
                Index = index, Op = op, Asset = asset, Property = property, Success = false, Message = reason
            });
            Debug.LogError($"{LOG_PREFIX} op {index} ({op ?? "?"}) on '{asset ?? "?"}' failed — {reason}");
            return false;
        }

        private static void FailAll(SerializedOpsResult result, List<IndexedOp> ops, string reason)
        {
            foreach (var entry in ops)
            {
                Fail(result, entry.Index, entry.Op.Value<string>("op"), entry.Op.Value<string>("asset"),
                    entry.Op.Value<string>("property"), reason);
            }
        }

        /// <summary>
        /// Turns an op that already reported success into a failure, because the read-back proved it
        /// did not persist. There is no partial state: the op is simply failed, and its recorded status
        /// is rewritten rather than appended to, since the success entry was written before the save.
        /// </summary>
        private static void FailAfterReadBack(SerializedOpsResult result, int index, string reason)
        {
            SerializedOpStatus status = result.Statuses.FirstOrDefault(s => s.Index == index);
            if (status != null)
            {
                status.Success = false;
                status.Message = reason;
            }

            Debug.LogError($"{LOG_PREFIX} op {index} — {reason}");
        }

        #endregion

        #region Nested Types

        private struct IndexedOp
        {
            public int Index;
            public JObject Op;
        }

        #endregion
    }
}
