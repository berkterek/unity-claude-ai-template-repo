---
name: shader-graph
description: "ShaderGraph JSON format reference — node templates, edge wiring, UUID generation, and ready-to-write .shadergraph patterns for common URP effects."
globs: ["**/*.shadergraph", "**/*.shadersubgraph"]
---

# ShaderGraph Skill

## When to Use This Skill

Load this skill when working with ShaderGraph (complexity score > 0.6 or user explicitly requests visual node editing).

> `unity-shader-dev` is an **agent** name — NOT a skill. Do not invoke `Skill("unity-shader-dev")`. The correct skill names are `shader-graph` and `urp-pipeline`.

---

## .shadergraph File Format

ShaderGraph files are JSON assets. Unity imports them as shader assets on `AssetDatabase.Refresh()`.

### Minimal Valid Structure

```json
{
  "m_SGVersion": 3,
  "m_Type": "UnityEditor.ShaderGraph.GraphData",
  "m_ObjectId": "<GUID-A>",
  "m_Properties": [],
  "m_Keywords": [],
  "m_Dropdowns": [],
  "m_CategoryData": [],
  "m_Nodes": [ <nodes> ],
  "m_GroupDatas": [],
  "m_StickyNoteDatas": [],
  "m_Edges": [ <edges> ],
  "m_VertexContext": { <vertex-context> },
  "m_FragmentContext": { <fragment-context> },
  "m_PreviewData": { "serializedMesh": { "mesh": { "fileID": 0 } }, "preventRotation": false },
  "m_Path": "Shader Graphs",
  "m_GraphPrecision": 1,
  "m_PreviewMode": 2,
  "m_OutputNode": { "m_Id": "" },
  "m_ActiveTargets": [ <urp-target> ]
}
```

### UUID Generation Rule

Every node, property, edge, and the graph root needs a unique `m_ObjectId`. Use this format:

```
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx   (32 hex chars, no dashes)
```

Generate sequentially for predictability: `a0000000000000000000000000000001`, `a0000000000000000000000000000002`, etc. Unity accepts any valid hex string — uniqueness within the file is what matters.

### URP Active Target

Always include this in `m_ActiveTargets` for URP compatibility:

```json
{
  "m_Id": "<GUID-target>"
},
{
  "m_Type": "UnityEditor.Rendering.Universal.UniversalTarget",
  "m_ObjectId": "<GUID-target>",
  "m_ActiveSubTarget": { "m_Id": "<GUID-subtarget>" },
  "m_AllowMaterialOverride": false,
  "m_SurfaceType": 0,
  "m_ZWriteControl": 0,
  "m_ZTestMode": 4,
  "m_AlphaMode": 0,
  "m_RenderFace": 2,
  "m_AlphaClip": false,
  "m_CastShadows": true,
  "m_ReceiveShadows": true,
  "m_CustomGUITagString": "",
  "m_OverrideEnabled": false,
  "m_OverrideShaderGUI": { "m_TypeString": "" }
}
```

### Vertex Context

```json
"m_VertexContext": {
  "m_Position": { "x": 0, "y": 0 },
  "m_Blocks": [
    { "m_Id": "<GUID-vpos>" },
    { "m_Id": "<GUID-vnorm>" },
    { "m_Id": "<GUID-vtan>" }
  ]
}
```

### Fragment Context

```json
"m_FragmentContext": {
  "m_Position": { "x": 400, "y": 0 },
  "m_Blocks": [
    { "m_Id": "<GUID-fbasecolor>" },
    { "m_Id": "<GUID-fnormal>" },
    { "m_Id": "<GUID-fmetallic>" },
    { "m_Id": "<GUID-fsmoothness>" },
    { "m_Id": "<GUID-femission>" },
    { "m_Id": "<GUID-falpha>" }
  ]
}
```

---

## Node Templates

### Property — Texture2D

```json
{
  "m_Id": "<GUID-prop-tex>"
},
{
  "m_Type": "UnityEditor.ShaderGraph.Texture2DShaderProperty",
  "m_ObjectId": "<GUID-prop-tex>",
  "m_Guid": { "m_GuidSerialized": "<GUID-prop-tex-inner>" },
  "m_Name": "BaseMap",
  "m_DefaultRefNameVersion": 1,
  "m_RefNameGeneratedByDisplayName": "BaseMap",
  "m_DefaultReferenceName": "_BaseMap",
  "m_OverrideReferenceName": "",
  "m_GeneratePropertyBlock": true,
  "m_UseCustomSlotLabel": false,
  "m_CustomSlotLabel": "",
  "m_DismissedVersion": 0,
  "m_Precision": 0,
  "overrideHLSLDeclaration": false,
  "hlslDeclarationOverride": 0,
  "m_Hidden": false,
  "m_Value": { "m_SerializedTexture": { "texture": { "fileID": 0 } }, "m_Guid": "" },
  "m_Modifiable": true,
  "m_DefaultType": 0
}
```

### Property — Float (Range)

```json
{
  "m_Type": "UnityEditor.ShaderGraph.Vector1ShaderProperty",
  "m_ObjectId": "<GUID-prop-float>",
  "m_Guid": { "m_GuidSerialized": "<GUID-prop-float-inner>" },
  "m_Name": "DissolveAmount",
  "m_DefaultReferenceName": "_DissolveAmount",
  "m_GeneratePropertyBlock": true,
  "m_Precision": 0,
  "m_Hidden": false,
  "m_Value": 0.0,
  "m_FloatType": 1,
  "m_RangeValues": { "x": 0.0, "y": 1.0 }
}
```

### Property — Color

```json
{
  "m_Type": "UnityEditor.ShaderGraph.ColorShaderProperty",
  "m_ObjectId": "<GUID-prop-color>",
  "m_Guid": { "m_GuidSerialized": "<GUID-prop-color-inner>" },
  "m_Name": "EdgeColor",
  "m_DefaultReferenceName": "_EdgeColor",
  "m_GeneratePropertyBlock": true,
  "m_Precision": 0,
  "m_Hidden": false,
  "m_Value": { "r": 1.0, "g": 0.5, "b": 0.0, "a": 1.0 },
  "m_ColorMode": 0
}
```

### Node — Sample Texture 2D

```json
{
  "m_Type": "UnityEditor.ShaderGraph.SampleTexture2DNode",
  "m_ObjectId": "<GUID-node-tex>",
  "m_Group": { "m_Id": "" },
  "m_Name": "Sample Texture 2D",
  "m_DrawState": {
    "m_Expanded": true,
    "m_Position": { "serializedVersion": "2", "x": -200, "y": 0, "width": 200, "height": 180 }
  },
  "m_Slots": [
    { "m_Id": "<GUID-slot-tex-in>" },
    { "m_Id": "<GUID-slot-uv>" },
    { "m_Id": "<GUID-slot-rgba>" },
    { "m_Id": "<GUID-slot-r>" },
    { "m_Id": "<GUID-slot-g>" },
    { "m_Id": "<GUID-slot-b>" },
    { "m_Id": "<GUID-slot-a>" }
  ],
  "synonyms": ["texture", "sample", "tex"],
  "m_Precision": 0,
  "m_TextureType": 0,
  "m_NormalMapSpace": 0,
  "m_EnableGlobalMipBias": true,
  "m_MipSamplingMode": 0
}
```

### Node — Multiply

```json
{
  "m_Type": "UnityEditor.ShaderGraph.MultiplyNode",
  "m_ObjectId": "<GUID-node-mul>",
  "m_Group": { "m_Id": "" },
  "m_Name": "Multiply",
  "m_DrawState": {
    "m_Expanded": true,
    "m_Position": { "serializedVersion": "2", "x": 50, "y": 0, "width": 130, "height": 120 }
  },
  "m_Slots": [
    { "m_Id": "<GUID-slot-mul-a>" },
    { "m_Id": "<GUID-slot-mul-b>" },
    { "m_Id": "<GUID-slot-mul-out>" }
  ],
  "synonyms": ["multiplication", "times", "x"],
  "m_Precision": 0
}
```

### Node — Step

```json
{
  "m_Type": "UnityEditor.ShaderGraph.StepNode",
  "m_ObjectId": "<GUID-node-step>",
  "m_Name": "Step",
  "m_DrawState": {
    "m_Expanded": true,
    "m_Position": { "serializedVersion": "2", "x": 50, "y": 0, "width": 130, "height": 120 }
  },
  "m_Slots": [
    { "m_Id": "<GUID-slot-step-edge>" },
    { "m_Id": "<GUID-slot-step-in>" },
    { "m_Id": "<GUID-slot-step-out>" }
  ],
  "m_Precision": 0
}
```

### Node — Fresnel Effect

```json
{
  "m_Type": "UnityEditor.ShaderGraph.FresnelEffectNode",
  "m_ObjectId": "<GUID-node-fresnel>",
  "m_Name": "Fresnel Effect",
  "m_DrawState": {
    "m_Expanded": true,
    "m_Position": { "serializedVersion": "2", "x": -100, "y": 0, "width": 170, "height": 150 }
  },
  "m_Slots": [
    { "m_Id": "<GUID-slot-fresnel-normal>" },
    { "m_Id": "<GUID-slot-fresnel-view>" },
    { "m_Id": "<GUID-slot-fresnel-power>" },
    { "m_Id": "<GUID-slot-fresnel-out>" }
  ],
  "m_Precision": 0
}
```

### Node — Time

```json
{
  "m_Type": "UnityEditor.ShaderGraph.TimeNode",
  "m_ObjectId": "<GUID-node-time>",
  "m_Name": "Time",
  "m_DrawState": {
    "m_Expanded": true,
    "m_Position": { "serializedVersion": "2", "x": -300, "y": 0, "width": 130, "height": 120 }
  },
  "m_Slots": [
    { "m_Id": "<GUID-slot-time-out>" },
    { "m_Id": "<GUID-slot-time-sin>" },
    { "m_Id": "<GUID-slot-time-cos>" },
    { "m_Id": "<GUID-slot-time-dt>" },
    { "m_Id": "<GUID-slot-time-smooth>" }
  ],
  "m_Precision": 0
}
```

### Node — Add

```json
{
  "m_Type": "UnityEditor.ShaderGraph.AddNode",
  "m_ObjectId": "<GUID-node-add>",
  "m_Name": "Add",
  "m_DrawState": {
    "m_Expanded": true,
    "m_Position": { "serializedVersion": "2", "x": 50, "y": 0, "width": 130, "height": 120 }
  },
  "m_Slots": [
    { "m_Id": "<GUID-slot-add-a>" },
    { "m_Id": "<GUID-slot-add-b>" },
    { "m_Id": "<GUID-slot-add-out>" }
  ],
  "m_Precision": 0
}
```

### Node — Gradient Noise

```json
{
  "m_Type": "UnityEditor.ShaderGraph.GradientNoiseNode",
  "m_ObjectId": "<GUID-node-noise>",
  "m_Name": "Gradient Noise",
  "m_DrawState": {
    "m_Expanded": true,
    "m_Position": { "serializedVersion": "2", "x": -200, "y": 0, "width": 170, "height": 150 }
  },
  "m_Slots": [
    { "m_Id": "<GUID-slot-noise-uv>" },
    { "m_Id": "<GUID-slot-noise-scale>" },
    { "m_Id": "<GUID-slot-noise-out>" },
    { "m_Id": "<GUID-slot-noise-hash>" }
  ],
  "m_Precision": 0
}
```

---

## Edge Wiring Format

An edge connects an output slot of one node to an input slot of another:

```json
{
  "m_OutputSlot": {
    "m_Node": { "m_Id": "<GUID-source-node>" },
    "m_SlotId": 0
  },
  "m_InputSlot": {
    "m_Node": { "m_Id": "<GUID-target-node>" },
    "m_SlotId": 0
  }
}
```

### Slot ID Convention (common nodes)

| Node | Slot ID | Direction |
|------|---------|-----------|
| SampleTexture2D | 0 = Texture input | In |
| SampleTexture2D | 1 = UV input | In |
| SampleTexture2D | 2 = RGBA output | Out |
| SampleTexture2D | 3/4/5/6 = R/G/B/A | Out |
| Multiply | 0 = A input | In |
| Multiply | 1 = B input | In |
| Multiply | 2 = Out | Out |
| Add | 0 = A input | In |
| Add | 1 = B input | In |
| Add | 2 = Out | Out |
| Step | 0 = Edge input | In |
| Step | 1 = In input | In |
| Step | 2 = Out | Out |
| FresnelEffect | 0 = Normal | In |
| FresnelEffect | 1 = View Dir | In |
| FresnelEffect | 2 = Power | In |
| FresnelEffect | 3 = Out | Out |
| Time | 0 = Time out | Out |
| GradientNoise | 0 = UV input | In |
| GradientNoise | 1 = Scale input | In |
| GradientNoise | 2 = Out | Out |

---

## Common Effect Recipes

### Dissolve with Edge Glow

**Nodes:** GradientNoise → Step (dissolve mask) → Multiply (alpha) + SmoothStep (edge) → Emission

**Node chain:**
```
[GradientNoise] --Out--> [Step] --Out--> [Alpha output]
                              \
                        [SmoothStep] --Out--> [Multiply] --Out--> [Emission output]
                              |
                        [EdgeColor property]
```

**Properties needed:** `_DissolveAmount` (float 0-1), `_EdgeWidth` (float 0-0.1), `_EdgeColor` (color), `_BaseMap` (texture)

---

### Rim / Fresnel Light

**Nodes:** FresnelEffect → Multiply (color) → Add to Emission

**Node chain:**
```
[FresnelEffect] --Out--> [Multiply] --Out--> [Add] --Out--> [Emission output]
                              |                    |
                        [RimColor prop]      [BaseColor * BaseMap]
```

**Properties needed:** `_RimColor` (color), `_RimPower` (float 1-8), `_BaseMap` (texture)

---

### UV Scroll (Water / Lava)

**Nodes:** Time → Multiply (speed) → Add to UV → SampleTexture2D

**Node chain:**
```
[Time] --Out--> [Multiply] --Out--> [Add] --Out--> [SampleTexture2D UV input]
                    |                    |
              [ScrollSpeed prop]   [original UV]
```

**Properties needed:** `_MainTex` (texture), `_ScrollSpeed` (float), `_BaseColor` (color)

---

### Toon / Cel Shading

**Nodes:** NdotL (dot of Normal + Main Light Dir) → Step (quantize) → Multiply (base color)

**Properties needed:** `_BaseMap` (texture), `_ShadowColor` (color), `_Steps` (float 2-8)

---

## MCP Integration After Writing File

After writing the `.shadergraph` file with the Write tool:

```csharp
// Step 1 — import the asset
AssetDatabase.Refresh();
AssetDatabase.ImportAsset("Assets/_GameFolders/Arts/Shaders/MyEffect.shadergraph");

// Step 2 — create material
var shader = Shader.Find("Shader Graphs/MyEffect");
var mat = new Material(shader);
AssetDatabase.CreateAsset(mat, "Assets/Arts/Materials/<Domain>/MyEffect.mat");

// Step 3 — assign to renderer (optional)
// via manage_components MCP tool
```

Run via MCP `execute_code`. If `Shader.Find` returns null, call `AssetDatabase.Refresh()` again and retry.

---

## Performance Notes

- Set graph Precision to **Half** in Graph Settings for mobile
- Avoid branching — use `lerp`/`step` instead of `if`
- Keep texture samples ≤ 3 per fragment for mobile
- Preview node count in shader inspector after import — aim under 100 instructions for mobile fragment

## Common Hallucinations — DO NOT

- Do not assume Unity 2022.3 ships with graph templates — `shadergraph_create_graph` falls back to blank graph creation
- Do not talk about "editing by node name" — implementations use serialized `nodeId` and `slotId`
- Do not recommend mutating Master Stack, Target, Context, Block, or SubGraph output structure programmatically — not supported
- For `PropertyNode`: create the blackboard property first; the node binds a real property object, not just a string
- `AppendVectorNode` is Unity 6 only — do not recommend for 2022.3 targets

## Cross-Version Node Whitelist (safe for 2022.3 + Unity 6)

28 nodes validated across both versions:

| Category | Nodes |
|----------|-------|
| Math | `Add`, `Subtract`, `Multiply`, `Divide`, `Power`, `Lerp`, `Step`, `Smoothstep`, `Remap`, `Saturate`, `Clamp`, `Abs`, `Negate` |
| Vector | `Split`, `Combine`, `Normalize`, `Dot`, `Cross`, `Length` |
| UV | `Tiling and Offset`, `Rotate` |
| Texture | `Sample Texture 2D`, `Sample Texture 2D Array` |
| Geometry | `Normal Vector`, `Position` (Object/World/Screen) |
| Utility | `Fresnel Effect`, `Custom Function` |
