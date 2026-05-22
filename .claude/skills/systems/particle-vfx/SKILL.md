---
name: particle-vfx
description: "Unity particle effect authoring — ParticleSystem module configuration (Emission, Shape, Renderer, Trails, Collision, Sub Emitters), URP particle shader selection, material placement under Arts/Materials/VFX/, prefab structure under _GameFolders/Prefabs/VFX/, scene hierarchy placement under [VFX] container, pooling pattern, and VContainer/UniTask/IEventBus integration. Use this skill whenever building, configuring, or wiring up any particle effect, VFX system, explosion, trail, smoke, fire, hit effect, or spawn effect in Unity."
globs: ["**/*VFX*.cs", "**/*Effect*.cs", "**/*Particle*.cs", "**/*Explosion*.cs", "**/*Trail*.cs", "**/*Prefabs/VFX/**"]
---

# Unity Particle VFX

## Folder & Asset Conventions

```
Arts/
└── Materials/
    └── VFX/              ← ALL particle materials here — never inside Prefabs/
        ├── Explosion.mat
        ├── Smoke.mat
        └── HitSpark.mat

_GameFolders/
└── Prefabs/
    └── VFX/              ← ALL particle prefabs here
        ├── ExplosionVFX.prefab
        ├── SmokeTrail.prefab
        └── HitSpark.prefab
```

Scene placement: every VFX prefab instance goes under the `[VFX]` container — never at root.

---

## URP Shader Selection

Always use URP particle shaders. Built-in / Legacy particle shaders = magenta in URP.

| Use case | Shader |
|----------|--------|
| Lit particle (receives light) | `Universal Render Pipeline/Particles/Lit` |
| Mobile performance (no lighting) | `Universal Render Pipeline/Particles/Simple Lit` |
| Additive glow, fire, sparks | `Universal Render Pipeline/Particles/Unlit` |
| Soft particles (depth fade) | `Universal Render Pipeline/Particles/Unlit` + enable Soft Particles in material |

Enable **GPU Instancing** on every particle material — it batches draw calls significantly.

---

## Prefab Structure — Logic / Visual Separation

```
ExplosionVFX.prefab           ← Root: VFXController.cs + VFXEvents.cs (logic only)
├── Core/                     ← ParticleSystem (main burst)
├── Sparks/                   ← Sub-emitter or child PS
├── Smoke/                    ← Child PS
└── Light/                    ← Point Light (optional)
```

- Root holds the controller script and any injected MonoBehaviours
- Root has **no** ParticleSystem component — visual child nodes only
- Each child ParticleSystem is its own GameObject
- Never put logic scripts on the visual child nodes

---

## Key ParticleSystem Module Configs

### Emission
```
Rate over Time: 0          ← for one-shot bursts, use Bursts instead
Bursts: Count=50, Time=0   ← fires 50 particles instantly at t=0
```

### Shape
```
Shape: Sphere / Cone / Mesh
Radius: match visual intent
Randomize Direction: 0.3–0.8 for natural spread
```

### Renderer
```
Render Mode: Billboard (default) / Mesh (3D debris)
Material: Arts/Materials/VFX/<name>.mat (URP Particles shader)
Order in Layer: 0 (increase for UI-overlapping VFX)
Enable GPU Instancing: ✓
```

### Trails
```
Mode: Particles — each particle spawns a trail
Lifetime: 0.3–0.5 (shorter = snappier)
Width over Trail: AnimationCurve tapering to 0
Material: separate trail material (Unlit, soft particles)
```

### Collision
```
Type: World
Mode: 3D
Lifetime Loss: 0.5        ← particle loses half life on collision
Bounce: 0.1–0.3
Send Collision Messages: ✓  ← enables OnParticleCollision callback
```

### Sub Emitters
```
Birth: spawn child PS when particle is born (e.g. trail head)
Death: spawn burst when particle dies (e.g. small spark on impact)
```

---

## Controller Script Pattern

```csharp
namespace Game.Concretes.VFX
{
    public sealed class VFXController : MonoBehaviour
    {
        #region Fields

        [SerializeField] private ParticleSystem[] _systems;
        private IEventBus _eventBus;

        #endregion

        #region Constructor

        [Inject]
        public void Construct(IEventBus eventBus)
        {
            _eventBus = eventBus;
        }

        #endregion

        #region Public Methods

        public void Play()
        {
            foreach (var ps in _systems)
                ps.Play();
        }

        public void Stop()
        {
            foreach (var ps in _systems)
                ps.Stop(true, ParticleSystemStopBehavior.StopEmitting);
        }

        #endregion
    }
}
```

- Inject `IEventBus` only when this VFX needs to publish events (hit feedback, combo triggers)
- `_systems` is assigned via `[SerializeField]` — drag child ParticleSystems in Inspector
- No `GetComponentsInChildren` in Awake — use serialized references

---

## Pooling Pattern (NON-NEGOTIABLE)

Never `Instantiate` / `Destroy` VFX prefabs at runtime. Use a pool.

```csharp
namespace Game.Concretes.VFX
{
    public sealed class VFXPool : IVFXPool, IDisposable
    {
        #region Fields

        private readonly IObjectResolver _container;
        private readonly VFXController _prefab;
        private readonly Queue<VFXController> _pool = new();
        private const int INITIAL_SIZE = 10;
        private const int MAX_SIZE = 50;

        #endregion

        #region Constructor

        public VFXPool(IObjectResolver container, VFXController prefab)
        {
            _container = container;
            _prefab = prefab;
            Warmup();
        }

        #endregion

        #region Public Methods

        public VFXController Get()
        {
            var vfx = _pool.Count > 0 ? _pool.Dequeue() : CreateNew();
            vfx.gameObject.SetActive(true);
            return vfx;
        }

        public void Return(VFXController vfx)
        {
            if (_pool.Count >= MAX_SIZE)
            {
                UnityEngine.Object.Destroy(vfx.gameObject);
                return;
            }

            vfx.Stop();
            vfx.gameObject.SetActive(false);
            _pool.Enqueue(vfx);
        }

        public void Dispose()
        {
            while (_pool.Count > 0)
                UnityEngine.Object.Destroy(_pool.Dequeue().gameObject);
        }

        #endregion

        #region Private Methods

        private void Warmup()
        {
            for (int i = 0; i < INITIAL_SIZE; i++)
                _pool.Enqueue(CreateNew());
        }

        private VFXController CreateNew()
        {
            var instance = _container.Instantiate(_prefab);
            instance.gameObject.SetActive(false);
            return instance;
        }

        #endregion
    }
}
```

**Rules:**
- `SetActive(false)` to return to pool — never `Destroy` a pooled VFX
- `Destroy` only when pool exceeds `MAX_SIZE` (capacity trim)
- `Dispose()` destroys all pooled instances during manager shutdown
- Warmup creates `INITIAL_SIZE` instances at startup to avoid first-frame spike

---

## Auto-Return Pattern (UniTask)

VFX that plays once and auto-returns to pool:

```csharp
public async UniTaskVoid PlayAndReturnAsync(VFXController vfx, IVFXPool pool, CancellationToken ct)
{
    vfx.Play();
    var duration = vfx.GetComponent<ParticleSystem>().main.duration;
    await UniTask.Delay(TimeSpan.FromSeconds(duration), cancellationToken: ct);

    if (ct.IsCancellationRequested) return;
    pool.Return(vfx);
}
```

- `UniTaskVoid` for fire-and-forget
- Always check cancellation before returning — the pool may have been disposed

---

## VContainer Registration

```csharp
public sealed class VFXInstaller : ModuleInstaller
{
    [SerializeField] private VFXController _explosionPrefab;
    [SerializeField] private VFXController _hitSparkPrefab;

    public override void Install(IContainerBuilder builder)
    {
        builder.Register<VFXPool>(Lifetime.Singleton)
            .WithParameter(_explosionPrefab)
            .As<IVFXPool>();
    }
}
```

---

## Event-Driven Playback

Trigger VFX from IEventBus events — never call VFX methods directly from gameplay code:

```csharp
public sealed class VFXService : IVFXService, IInitializable, IDisposable
{
    private readonly IEventBus _eventBus;
    private readonly IVFXPool _pool;

    public VFXService(IEventBus eventBus, IVFXPool pool)
    {
        _eventBus = eventBus;
        _pool = pool;
    }

    public void Initialize()
    {
        _eventBus.Subscribe<EnemyDiedEvent>(OnEnemyDied);
        _eventBus.Subscribe<ProjectileHitEvent>(OnProjectileHit);
    }

    public void Dispose()
    {
        _eventBus.Unsubscribe<EnemyDiedEvent>(OnEnemyDied);
        _eventBus.Unsubscribe<ProjectileHitEvent>(OnProjectileHit);
    }

    private void OnEnemyDied(EnemyDiedEvent e)
    {
        var vfx = _pool.Get();
        vfx.transform.position = e.Position;
        vfx.Play();
    }

    private void OnProjectileHit(ProjectileHitEvent e)
    {
        var vfx = _pool.Get();
        vfx.transform.position = e.HitPoint;
        vfx.transform.rotation = Quaternion.LookRotation(e.HitNormal);
        vfx.Play();
    }
}
```

---

## Performance Rules

| Rule | Why |
|------|-----|
| GPU Instancing on all particle materials | Batches draw calls significantly |
| Max particle count ≤ 500 per system | Exceeding this spikes CPU (transform updates) |
| Use Burst-mode ParticleSystem (Jobs) | Enable in Particle System settings → Job System |
| Texture atlasing for particle sprites | Reduces material swaps |
| Disable `Receive Shadows` and `Cast Shadows` on Renderer module | Unnecessary cost for transparent particles |
| No `Camera.main` access in particle callbacks | Cache camera reference via `[SerializeField]` |
| `Stop(true, StopEmitting)` not `Stop(true, StopEmittingAndClear)` | Lets existing particles finish — cleaner visually |

---

## MCP Workflow (via unity-particle-designer agent)

When creating VFX via MCP:

1. **Create material** — `execute_code` → `new Material(Shader.Find("Universal Render Pipeline/Particles/Unlit"))`; save to `Arts/Materials/VFX/`
2. **Create prefab** — `manage_gameobject` → create root with VFXController; add child with ParticleSystem
3. **Configure modules** — `execute_code` → read `ParticleSystem.main`, `.emission`, `.shape`, `.renderer` and set values
4. **Save prefab** — `execute_code` → `PrefabUtility.SaveAsPrefabAsset()` to `_GameFolders/Prefabs/VFX/`
5. **Place in scene** — `manage_gameobject` → instantiate under `[VFX]` container
6. **Verify** — `get_logs` for any errors; check Particle System preview in Scene view
