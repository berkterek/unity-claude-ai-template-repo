# Complexity Scoring Expansion Design

**Date:** 2026-05-08  
**Status:** Approved

---

## Purpose

`fix` ve `implement` komutlarında bulunan complexity scoring sistemini 4 pipeline komutuna daha eklemek: `orchestrate`, `scene-setup`, `migrate`, `add-feature`.

Her komut complexity score'a göre agent seçimini ve pipeline derinliğini ayarlar. Agent seçimi aynı zamanda hedef kodun türüne göre de şekillenir: pure C# → `coder`, Unity/Mixed → `unity-coder`.

---

## Kapsam Dışı

- `fix-deep` — zaten her zaman max evidence pipeline, scoring anlamsız
- `create-prefab-scene` — sabit legacy migration flow, scoring anlamsız

---

## Ortak Scoring Bloğu

Tüm 4 komuta `## Step 0 — Complexity Scoring` olarak eklenir. `fix.md` / `implement.md`'deki blokla birebir aynı format:

```markdown
## Step 0 — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing).

| Mode | Effect |
|------|--------|
| `solo` | Reviewer ve unity-developer yok — coder → committer only |
| `lean` | Standart pipeline |
| `full` | unity-developer her zaman aktif |

Before spawning any agents, score the task complexity on a 0.0–1.0 scale:

| Score | Label | Signals |
|-------|-------|---------|
| 0.0–0.3 | Simple | Tek dosya, yeni interface yok, event yok |
| 0.4–0.6 | Medium | 2–4 dosya, yeni interface veya event bus |
| 0.7–1.0 | Complex | Yeni modül, ECS, Addressables, cross-system events |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
Complexity: [score] — [Label]
Rationale: [one sentence]
Pipeline: [which variant]
```

---

## Agent Routing Kuralı (Tüm Komutlar)

Her komut coder spawn etmeden önce bu kararı verir:

| Hedef | Agent (Simple) | Agent (Medium/Complex) |
|-------|----------------|------------------------|
| `_Framework/`, `Abstracts/`, pure C# (no Unity API) | **coder** | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring, Unity lifecycle | **unity-coder-lite** | **unity-coder** |
| Mixed (both) | **unity-coder-lite** | **unity-coder** |

---

## Komuta Özel Pipeline Değişimleri

### `orchestrate`

| Score | Coder | Post-task Review |
|-------|-------|-----------------|
| Simple | coder / unity-coder-lite | unity-reviewer |
| Medium | coder / unity-coder | unity-reviewer |
| Complex | coder / unity-coder | unity-reviewer → unity-developer |

`full` modunda unity-developer her zaman aktif (score'dan bağımsız).

### `scene-setup`

Scene setup her zaman Unity/Mixed hedef — pure C# agent kullanılmaz.

| Score | Coder | Review |
|-------|-------|--------|
| Simple | unity-coder-lite | unity-reviewer |
| Medium | unity-coder | unity-reviewer |
| Complex | unity-coder | unity-reviewer → unity-developer |

### `migrate`

| Score | Pipeline |
|-------|----------|
| Simple | migrator/unity-migrator → reviewer |
| Medium | test guard → migrator/unity-migrator → reviewer |
| Complex | test guard → migrator/unity-migrator → unity-reviewer → unity-developer |

**Migrator routing:**
- Pure C# pattern migration → `migrator`
- Unity-specific migration (coroutine→UniTask, singleton→VContainer, legacy input) → `unity-migrator`

### `add-feature`

| Score | Interview | Coder | Review |
|-------|-----------|-------|--------|
| Simple | 3 soru (kısa) | coder / unity-coder-lite | unity-reviewer |
| Medium | deep-interview tam | coder / unity-coder | unity-reviewer |
| Complex | deep-interview tam | coder / unity-coder | unity-reviewer → unity-developer |

`full` modunda unity-developer her zaman aktif.

---

## Uygulama Noktaları

Her komutta scoring bloğu pipeline'ın en başına (`## Step 0`) eklenir. Mevcut step numaraları 1'er artırılır.

| Komut | Mevcut ilk step | Yeni ilk step |
|-------|----------------|---------------|
| `orchestrate` | Step 1 | Step 1 → Step 2 (scoring Step 0) |
| `scene-setup` | Step 1 | Step 1 → Step 2 (scoring Step 0) |
| `migrate` | Step 1 | Step 1 → Step 2 (scoring Step 0) |
| `add-feature` | Step 1 | Step 1 → Step 2 (scoring Step 0) |
