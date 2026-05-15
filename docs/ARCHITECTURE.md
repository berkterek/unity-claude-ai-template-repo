# Architecture Diagrams

Visual reference for the Unity Claude AI Template architecture. All diagrams reflect the conventions enforced by hooks and rules in `.claude/`.

---

## Pipeline — Command Flow

```mermaid
graph TD
    User(["Developer"])

    subgraph Design["Phase 1-2 — Design & Planning"]
        GI["/game-idea\nGDD"]
        AR["/architect\nTDD"]
        PW["/plan-workflow\nWORKFLOW.md"]
        DR["/dry-run\nPreview"]
        GI --> AR --> PW --> DR
    end

    subgraph Setup["Phase 3 — Project Setup"]
        SP["/setup-project\nFolders · asmdefs · Base classes"]
    end

    subgraph Impl["Phase 4 — Implementation"]
        ORC["/orchestrate\nWORKFLOW.md executor"]
        IMP["/implement\nSingle task TDD pipeline"]
        FIX["/fix\nBug fix pipeline"]
        FXD["/fix-deep\nEvidence-first fix"]
    end

    subgraph Quality["Phase 5 — Quality"]
        QA["/qa\nralph → silent-failure-hunt → validate"]
        RL["/ralph\nVerify-fix loop"]
        VL["/validate\nPhase exit criteria"]
        RC["/review-code\nManual review"]
    end

    subgraph Docs["Phase 6 — Docs & Learning"]
        LRN["/learn\nskills/learned/"]
        CU["/catch-up\nCATCH_UP.md"]
        SC["/smart-commit\nSemantic commits"]
    end

    User --> Design --> Setup --> Impl --> Quality --> Docs
```

---

## Agent Pipeline — /implement & /fix

```mermaid
graph TD
    GATE["SCOPE_GATE\nhuman: go / stop"]
    TW["tester\nWrite test first"]
    CODER["unity-coder / unity-coder-lite\nImplementation"]
    VER["unity-verifier\nCompile + Tests via MCP"]
    REV{"Reviewer\nCodex → unity-reviewer"}
    SFH["silent-failure-hunt\nSwallowed exceptions audit"]
    DEV["unity-developer\nComplex tasks score ≥ 0.7"]
    COMMIT_GATE["COMMIT_GATE\nhuman: go / stop"]
    CMT["committer\nSemantic git commit"]

    GATE --> TW --> CODER --> VER
    VER -->|VALIDATED| REV
    VER -->|FAILED| CODER
    REV -->|APPROVED| SFH
    REV -->|CHANGES NEEDED| CODER
    SFH --> DEV --> COMMIT_GATE --> CMT
```

---

## VContainer Scope Hierarchy

```mermaid
graph TD
    BS["Bootstrap.unity\nBuild index 0"]
    AS["AppScope\nLifetimeScope — DontDestroyOnLoad"]
    AI["AppInstaller\nModuleInstaller list"]
    EB["EventBus\nIEventBus — Singleton"]
    EBA["EventBusAccessor\nStatic bridge for ECS"]

    MS["MenuScope\nMenu Scene"]
    GS["GameScope\nGame Scene"]

    M1["AudioInstaller\n→ IAudioService"]
    M2["StoreInstaller\n→ IStoreService"]
    MN["...ModuleInstaller\n→ IXxxService"]

    BS --> AS
    AS --> AI
    AI --> M1 & M2 & MN
    AS --> EB --> EBA
    AS --> MS
    AS --> GS
```

---

## Architecture Layers

```mermaid
graph TD
    subgraph Framework["_Framework/ — Never references _GameFolders or other project folders"]
        IEB["IEventBus / EventBus"]
        EBA2["EventBusAccessor"]
        LOG["Logging"]
        SLS["SaveLoadSystems"]
    end

    subgraph Abstracts["Games/Abstracts/ — Interfaces & Contracts"]
        ISvc["IXxxService"]
        ICfg["XxxConfiguration\nScriptableObject"]
        IEvt["XxxEvents\nIEvent structs"]
    end

    subgraph Concretes["Games/Concretes/ — Unity API boundary"]
        Svc["XxxService\nsealed, pure C#"]
        Prv["XxxProvider\nMonoBehaviour — Unity API here"]
        Ins["XxxInstaller\nVContainer registration"]
    end

    subgraph ECS["Games/Ecs/"]
        Auth["XxxAuthoring + Baker"]
        Comp["XxxData / XxxTag\nIComponentData"]
        Sys["XxxSystem\nISystem + IJobEntity"]
        BSys["XxxBridgeSystem\nSystemBase"]
    end

    subgraph Tests["Tests/"]
        EMT["ProjectNameEditModeTest\nNUnit + NSubstitute"]
        PMT["ProjectNamePlayModeTest\nPlay Mode scene tests"]
    end

    Framework --> Abstracts --> Concretes
    Abstracts --> Tests
    ECS --> EBA2
    EBA2 --> IEB
```

---

## Hook Flow — Every Write/Edit

```mermaid
graph LR
    W["Write / Edit\n.cs file"]

    subgraph Blocking["Blocking — exit 2"]
        B1["gateguard\nFile must be read before write"]
        B2["guard-critical-files\nAppScope · InputView · Installer"]
        B3["check-input-system\nLegacy Input.GetKey / GetAxis"]
        B4["check-vcontainer-singleton\nStatic singleton patterns"]
        B5["guard-editor-runtime\nUnguarded UnityEditor namespace"]
        B6["check-pure-csharp\nUnityEngine in _Framework"]
        B7["check-no-runtime-instantiate\nnew GameObject()"]
        B8["check-config-protection\n.asmdef · settings.json"]
    end

    subgraph Warning["Warning — exit 0"]
        W1["check-no-hotpath-expensive-calls\nGetComponent · Camera.main in Update"]
        W2["check-no-linq-hotpath\nLINQ in Update / FixedUpdate"]
        W3["check-getcomponent-in-awake\nPrefer SerializeField assignment"]
        W4["check-naming-conventions\nPascalCase · _camelCase"]
        W5["check-async-void\nasync void outside lifecycle"]
        W6["check-unitask-cancellation\nMissing CancellationToken"]
        W7["check-null-propagation\n?. or is null on Unity objects"]
    end

    W --> Blocking
    W --> Warning
```
