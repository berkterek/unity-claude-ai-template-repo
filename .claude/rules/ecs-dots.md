# ECS DOTS Rules

## 1. Entity Creation Rule

- Every entity is a **prefab**: defined in SubScene as Authoring GO + Baker, or instantiated from a prefab at runtime.
- `EntityManager.CreateEntity()` with no source prefab is **forbidden**.
- Entity prefabs live in SubScene as Authoring GameObjects; no directly baked entities in the scene.

---

## 2. Authoring & Baker Rule

Every entity has an **Authoring** MonoBehaviour and a matching **Baker** class.

- All inspector-configurable components are added through the Baker.
- Runtime-dependent data (values bound to runtime state, config from ScriptableObject) → added by the relevant **System**, not the Baker.

```csharp
public class EnemyAuthoring : MonoBehaviour
{
    public EnemyConfigSO Config;

    public class Baker : Baker<EnemyAuthoring>
    {
        public override void Bake(EnemyAuthoring authoring)
        {
            var entity = GetEntity(TransformUsageFlags.Dynamic);
            AddComponent(entity, new EnemyEntityTag());
            // Config data added by EnemyInitSystem, not here
        }
    }
}
```

---

## 3. Component Naming

| Type | Rule | Example |
|------|------|---------|
| `IComponentData` (data) | PascalCase, no suffix | `HealthData`, `MoveSpeed`, `EnemyStats` |
| `IComponentData` (tag) | PascalCase + `Tag` suffix | `EnemyEntityTag`, `DestroyEntityTag` |
| `IEnableableComponent` tag | Same: `Tag` suffix | `PauseStateTag`, `MoveStateTag` |
| `ICleanupComponentData` (value) | PascalCase + `CleanupData` suffix | `EnemyCleanupData`, `TowerBaseCleanupData` |
| Managed `ICleanupComponentData` (reference) | PascalCase + `Reference` suffix — **class** | `EnemyVisualReference` |
| Authoring | PascalCase + `Authoring` suffix | `EnemyAuthoring` |
| Baker | Inner class `Baker<T>` | `EnemyAuthoring.Baker` |
| `ISystem` (Burst) | PascalCase + `System` suffix | `EnemyMoveSystem` |
| `SystemBase` (bridge) | PascalCase + `BridgeSystem` suffix | `InputBridgeSystem` |

```csharp
public struct HealthData     : IComponentData { public int Current; public int Max; }
public struct EnemyEntityTag : IComponentData { }
public struct DestroyEntityTag : IComponentData, IEnableableComponent { }

public struct TowerBaseCleanupData : ICleanupComponentData { public float3 Position; }

// Managed — holds MonoBehaviour reference
public class EnemyVisualReference : ICleanupComponentData
{
    public EnemyVisualController Value;
}
```

---

## 4. Hybrid ECS ↔ OOP Linking

Use a **managed `ICleanupComponentData` class** to link an entity to its MonoBehaviour.

- It is a `class` (not struct) — lives on managed heap, can hold MonoBehaviour references.
- Inherits `ICleanupComponentData` — remains visible to systems after entity destruction until cleanup.
- Communication always goes through a System — the system reads the reference and calls the MonoBehaviour method.

```csharp
// 1 — Define managed reference component
public class TowerBaseVisualReference : ICleanupComponentData
{
    public TowerBaseProvider Value;
}

// 2 — Attach in Baker or init system
AddComponentObject(entity, new TowerBaseVisualReference { Value = provider });

// 3 — System reads it and calls the MonoBehaviour
protected override void OnUpdate()
{
    Entities.ForEach((TowerBaseVisualReference reference, in HealthData health) =>
    {
        reference.Value.UpdateHealthBar(health.Current, health.Max);
    }).WithoutBurst().Run();
}
```

---

## 5. ScriptableObject → Component Transfer

Enemy stats and config data live in ScriptableObjects. At runtime, a **System** reads the SO and copies values into entity components. The entity never holds a SO reference after init.

```csharp
public partial class EnemyInitSystem : SystemBase
{
    protected override void OnUpdate()
    {
        Entities
            .WithAll<EnemyEntityTag>()
            .WithNone<EnemyStats>()
            .ForEach((Entity e, in EnemyConfigReference configRef) =>
            {
                EntityManager.AddComponentData(e, new EnemyStats
                {
                    Health = configRef.Config.Health,
                    Speed  = configRef.Config.Speed
                });
            }).WithoutBurst().Run();
    }
}
```

---

## 6. Mono ↔ ECS Communication Rule

No class talks directly to `ISystem` (preserves Burst compatibility).

| Direction | Chain |
|-----------|-------|
| Mono → ECS | `Mono class` → `SystemBase` → `ISystem` |
| ECS → Mono | `ISystem` → `SystemBase` → `Mono class` |

`SystemBase` acts as the bridge layer. Burst-compiled `ISystem` code stays isolated; managed API calls happen on the `SystemBase` side.

---

## 7. System Update Order

Every system declares its group explicitly with `[UpdateInGroup]`, `[UpdateBefore]`, `[UpdateAfter]`.

| Order | Group | Use | Attribute |
|-------|-------|-----|-----------|
| 1 | `InitializationSystemGroup` | First-time config write to entity | `[UpdateInGroup(typeof(InitializationSystemGroup))]` |
| 2 | `SimulationSystemGroup` — before `TransformSystemGroup` | Movement, velocity, input | `[UpdateBefore(typeof(TransformSystemGroup))]` |
| 3 | `SimulationSystemGroup` — after `TransformSystemGroup` | Position query, range check, attack | `[UpdateAfter(typeof(TransformSystemGroup))]` |
| 4 | `SimulationSystemGroup` — after attack | Damage accept, `health <= 0` → enable `DestroyEntityTag` | `[UpdateAfter(typeof(AttackSystem))]` |
| 5 | `SimulationSystemGroup` — after damage | Bridge health change to OOP event | `[UpdateAfter(typeof(DamageAcceptSystem))]` |
| 6a | `LateSimulationSystemGroup` — before `DestroySystem` | Pre-destroy: add `ICleanupComponentData` | `[UpdateBefore(typeof(DestroySystem))]` |
| 6b | `LateSimulationSystemGroup` | Destroy entity, trigger animation | — |
| 7 | `LateSimulationSystemGroup` — after `DestroySystem` | Cleanup: `CleanupData` present + no `LocalTransform` → OOP bridge | `[UpdateAfter(typeof(DestroySystem))]` |

---

## 8. ISystem + IJobEntity Rule

`ISystem` (Burst-compiled) cannot use `foreach` directly. Use `IJobEntity` + `ScheduleParallel`.

| System type | Query method |
|-------------|-------------|
| `ISystem` (Burst) | `IJobEntity` + `ScheduleParallel` / `Schedule` |
| `SystemBase` (managed) | `foreach` + `SystemAPI.Query<>` or `Entities.ForEach` |

```csharp
[BurstCompile]
[UpdateInGroup(typeof(SimulationSystemGroup))]
[UpdateBefore(typeof(TransformSystemGroup))]
public partial struct EnemyMoveSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var job = new MoveJob { DeltaTime = SystemAPI.Time.DeltaTime };
        var handle = job.ScheduleParallel(state.Dependency);
        state.Dependency = handle;
        handle.Complete();
    }

    [BurstCompile]
    [WithDisabled(typeof(PauseStateTag))]
    partial struct MoveJob : IJobEntity
    {
        public float DeltaTime;

        void Execute(
            ref LocalTransform localTransform,
            in  MoveSpeedData  moveSpeed,
            in  TargetData     target,
            in  MoveStateTag   moveStateTag)
        {
            var direction = math.normalize(target.Position - localTransform.Position);
            localTransform.Position += DeltaTime * moveSpeed.Value * direction;
        }
    }
}
```

### IEnableableComponent Filtering in IJobEntity

| Condition | Method |
|-----------|--------|
| Component must be **enabled** | Add as `Execute` parameter: `in MoveStateTag moveStateTag` |
| Component must be **disabled** | Add attribute to job struct: `[WithDisabled(typeof(PauseStateTag))]` |

`[BurstCompile]` applies to both the system struct and the job struct.

---

## 9. Structural Change Rule

Entity creation, destruction, adding/removing components, and prefab instantiation during query iteration must use `EntityCommandBuffer`.

| Operation | Required method |
|-----------|----------------|
| `AddComponent`, `RemoveComponent`, `Instantiate`, `DestroyEntity` | `EntityCommandBuffer` |
| Enable / disable `IEnableableComponent` | `SystemAPI.SetComponentEnabled` or `EntityManager.SetComponentEnabled` |
| Data update only (`SetComponentData`, buffer content) | Direct write is fine |

```csharp
[UpdateInGroup(typeof(LateSimulationSystemGroup))]
[UpdateBefore(typeof(DestroySystem))]
public partial class TowerBasePreDestroySystem : SystemBase
{
    protected override void OnUpdate()
    {
        var ecb = new EntityCommandBuffer(Allocator.Temp);

        foreach (var (transform, entity) in SystemAPI.Query<RefRO<LocalTransform>>()
                     .WithAll<TowerBaseEntityTag, DestroyEntityTag>()
                     .WithNone<TowerBaseCleanupData>()
                     .WithEntityAccess())
        {
            if (!SystemAPI.IsComponentEnabled<DestroyEntityTag>(entity)) continue;

            ecb.AddComponent(entity, new TowerBaseCleanupData
            {
                Position = transform.ValueRO.Position
            });
        }

        ecb.Playback(EntityManager);
        ecb.Dispose();
    }
}
```

---

## 10. Folder Structure

```
_GameFolders/Scripts/Games/Ecs/
├── Authorings/    ← Authoring MonoBehaviours + Baker inner classes
├── Components/    ← IComponentData structs, tag components
└── Systems/       ← ISystem, SystemBase, bridge systems
```

ECS components and systems never go into `Abstracts/` or `Concretes/` — they stay in `Ecs/`.

---

## 11. Enum Base Type in ECS and IEvent Structs

Enums declared inside `IComponentData` structs or `IEvent` structs must inherit from `byte`.

**Why:** Each ECS component lives in a chunk. A default `int` enum costs 4 bytes; a `byte` enum costs 1 byte. In a struct with multiple fields this adds up quickly and reduces entities per chunk, hurting cache performance. `IEvent` structs benefit for the same reason — smaller allocation on publish.

```csharp
// BAD — default int base wastes 3 bytes per entity
public struct EnemyStateData : IComponentData
{
    public EnemyState State;
}

public enum EnemyState { Idle, Moving, Attacking }

// GOOD — byte base, 1 byte per entity
public struct EnemyStateData : IComponentData
{
    public EnemyState State;
}

public enum EnemyState : byte { Idle, Moving, Attacking }
```

**Rules:**
- All enums used inside `IComponentData` or `IEvent` structs → `: byte`
- If more than 255 values are genuinely needed → `: ushort`
- Enums in service classes, ScriptableObjects, or config data → no constraint (default `int` is fine)
- The `check-enum-byte-base.sh` hook warns when a non-byte enum is found in ECS or IEvent files
