# UI RectTransform Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** UI GameObject'lerin prefab kaydedilmeden önce RectTransform'a sahip olduğunu garantilemek için `unity-ui-builder`, `unity-ugui` ve `unity-setup` agent/skill dosyalarına zorunlu guard kuralları eklemek.

**Architecture:** Üç mevcut dosyaya ekleme yapılır — yeni dosya oluşturulmaz. Her dosyaya (1) UI GO discriminator kuralı, (2) zorunlu `manage_components` adımı, (3) prefab öncesi `execute_code` doğrulaması eklenir.

**Tech Stack:** Markdown (agent/skill dosyaları), Unity MCP (`manage_gameobject`, `manage_components`, `execute_code`, `manage_prefabs`)

---

## File Map

| Dosya | Değişiklik |
|-------|-----------|
| `.claude/agents/unity-ui-builder.md` | Step 2 sonrasına `## RectTransform Guard (NON-NEGOTIABLE)` bloğu eklenir (satır 69 civarı) |
| `.claude/skills/core/unity-ugui.md` | Canvas Setup bölümünden sonra `## Pre-Prefab Checklist (NON-NEGOTIABLE)` eklenir (satır 98 civarı) |
| `.claude/agents/unity-setup.md` | Prefab checklist'e (satır 87–93) 3 UI-spesifik madde eklenir |

---

### Task 1: `unity-ui-builder.md` — RectTransform Guard bloğu ekle

**Files:**
- Modify: `.claude/agents/unity-ui-builder.md` (satır 69 sonrasına ekle)

- [ ] **Step 1: Mevcut dosyayı oku ve ekleme noktasını bul**

  `.claude/agents/unity-ui-builder.md` dosyasını oku. Satır 69'daki şu satırı bul:

  ```
  Place the Canvas prefab under `[UI]` container per scene-hierarchy rules.
  ```

- [ ] **Step 2: RectTransform Guard bloğunu ekle**

  Yukarıdaki satırın hemen altına şu bloğu ekle:

  ```markdown

  ## RectTransform Guard (NON-NEGOTIABLE)

  ### UI GO Discriminator

  Bir GO'nun UI GO olduğunu iki sinyalle belirle:

  **PRIMARY (deterministik) — `parentPath`:**
  `parentPath` bir Canvas'ı veya Canvas child'ını işaret ediyorsa → UI GO → RectTransform zorunlu.

  **SECONDARY (destekleyici, parentPath belirsizse) — component adı:**
  Şu component'lerden biri ekleniyorsa → UI GO → RectTransform zorunlu:
  `Image`, `RawImage`, `Button`, `Toggle`, `Slider`, `TextMeshProUGUI`, `ScrollRect`, `InputField`, `CanvasGroup`

  > `TextMeshPro` (3D, UGUI suffix'i olmayan) UI sinyali DEĞİLDİR.

  ### Zorunlu 3 Adım — Her UI GO İçin

  **Adım A — Canvas parentPath ile oluştur (ZORUNLU)**
  ```
  manage_gameobject create "SettingsButton"
    parentPath: "Canvas/SettingsPanel"   ← Canvas path — Unity otomatik RectTransform atar
  ```
  Hiçbir zaman GO'yu scene root'ta oluşturup sonra reparent etme.

  **Adım B — `manage_components` ile RectTransform özelliklerini set et**
  ```
  manage_components set_property
    target: "Canvas/SettingsPanel/SettingsButton"
    component: "RectTransform"
    property: "anchorMin"
    value: [0, 0]
  ```
  Bu adım RectTransform'un varlığını onaylar. Eğer Unity hata dönerse GO'da plain Transform var demektir — prefab kaydetme, önce düzelt.

  **Adım C — Prefab kaydetmeden önce `execute_code` ile doğrula**
  ```csharp
  // GO adını ve path'ini kendi senaryona göre değiştir
  var go = GameObject.Find("SettingsPanel/SettingsButton");
  var rt = go != null ? go.GetComponent<RectTransform>() : null;
  if (rt == null)
      Debug.LogError("[RectTransformGuard] RectTransform bulunamadı — prefab kaydetme!");
  else
      Debug.Log("[RectTransformGuard] OK — RectTransform onaylandı.");
  ```
  Console'da `LogError` görünürse → `manage_prefabs` çağrısını durdur, GO'yu düzelt.
  ```

- [ ] **Step 3: Değişikliği doğrula**

  Dosyayı tekrar oku, `## RectTransform Guard` başlığının satır 70–71 civarında göründüğünü ve discriminator + 3 adımın eksiksiz olduğunu doğrula.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/unity-ui-builder.md
  git commit -m "feat(agents): add RectTransform guard to unity-ui-builder"
  ```

---

### Task 2: `unity-ugui.md` — Pre-Prefab Checklist ekle

**Files:**
- Modify: `.claude/skills/core/unity-ugui.md` (Canvas Setup bölümünden sonra)

- [ ] **Step 1: Mevcut dosyayı oku ve ekleme noktasını bul**

  `.claude/skills/core/unity-ugui.md` dosyasını oku. Şu satırı bul (yaklaşık satır 98):

  ```markdown
  ### CanvasScaler (always)
  ```

  Bu satırın ÖNÜNE (yani `## 2. Canvas Setup via MCP` bölümünün sonuna) ekleme yapılacak. Tam olarak bu satırı bul:

  ```
  ---

  ## 3. Canvas Split Strategy
  ```

- [ ] **Step 2: Pre-Prefab Checklist'i ekle**

  `## 3. Canvas Split Strategy` başlığından ÖNCE şu bloğu ekle:

  ```markdown
  ---

  ## Pre-Prefab Checklist (NON-NEGOTIABLE)

  Herhangi bir UI GO'yu prefab olarak kaydetmeden önce üç koşulun tamamı sağlanmış olmalı:

  - [ ] GO, Canvas veya Canvas child'ına `parentPath` ile oluşturuldu
  - [ ] `manage_components` ile RectTransform özelliği set edildi (hatasız tamamlandı)
  - [ ] `execute_code` ile `GetComponent<RectTransform>()` doğrulandı (LogError yok)

  ### UI GO Discriminator

  | Sinyal | Tür | UI GO mu? |
  |--------|-----|-----------|
  | `parentPath` → Canvas veya Canvas child | PRIMARY | Evet — RectTransform zorunlu |
  | Component: `Image`, `RawImage`, `Button`, `Toggle`, `Slider` | SECONDARY | Evet — RectTransform zorunlu |
  | Component: `TextMeshProUGUI`, `ScrollRect`, `InputField`, `CanvasGroup` | SECONDARY | Evet — RectTransform zorunlu |
  | Component: `TextMeshPro` (3D, UGUI suffix'siz) | — | **Hayır** — UI sinyali değil |
  | `parentPath` → `[Services]`, `[Setup]`, `[Characters]`, `[VFX]` container | — | **Hayır** — normal GO |

  > PRIMARY sinyal her zaman önce kontrol edilir. SECONDARY yalnızca parentPath belirsizse kullanılır.

  ```

- [ ] **Step 3: Değişikliği doğrula**

  Dosyayı oku, `## Pre-Prefab Checklist` bölümünün `## 3. Canvas Split Strategy`'den önce göründüğünü ve tablonun doğru formatlandığını kontrol et.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/skills/core/unity-ugui.md
  git commit -m "feat(skills): add pre-prefab RectTransform checklist to unity-ugui"
  ```

---

### Task 3: `unity-setup.md` — Prefab checklist'e UI maddeleri ekle

**Files:**
- Modify: `.claude/agents/unity-setup.md` (satır 87–93 arası checklist)

- [ ] **Step 1: Mevcut checklist'i oku**

  `.claude/agents/unity-setup.md` dosyasını oku. Şu bloğu bul (satır 87–93):

  ```markdown
  **Checklist before marking prefab creation complete:**
  - [ ] Prefab lives under `_GameFolders/Prefabs/<Domain>/`
  - [ ] Root holds logic/physics components only
  - [ ] `Body` child holds all Renderer/Animator/VFX components
  - [ ] Canvas prefabs are Prefab Variants of BaseCanvas (not standalone)
  - [ ] If 2+ prefabs share the same component set → Base + Variant used
  - [ ] Default values match ScriptableObject configs
  ```

- [ ] **Step 2: UI-spesifik maddeleri ekle**

  `- [ ] Default values match ScriptableObject configs` satırının hemen altına şu üç maddeyi ekle:

  ```markdown
  - [ ] **UI prefabs only:** GO, Canvas veya Canvas child `parentPath` ile oluşturuldu (scene root'ta oluşturup reparent edilmedi)
  - [ ] **UI prefabs only:** `manage_components` RectTransform özelliği hatasız set edildi
  - [ ] **UI prefabs only:** `execute_code` RectTransform guard geçti — `Debug.LogError` yok
  ```

- [ ] **Step 3: Değişikliği doğrula**

  Dosyayı oku, checklist'in artık 9 madde içerdiğini ve son 3 maddenin `**UI prefabs only:**` etiketiyle başladığını doğrula.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/unity-setup.md
  git commit -m "feat(agents): add UI RectTransform guard items to unity-setup prefab checklist"
  ```

---

## Self-Review

**Spec coverage:**
- [x] Discriminator (parentPath primary, component secondary, TextMeshPro istisnası) → Task 1 + Task 2
- [x] Zorunlu manage_components adımı → Task 1 Adım B
- [x] execute_code pre-save doğrulaması → Task 1 Adım C
- [x] unity-ugui.md checklist → Task 2
- [x] unity-setup.md checklist güncellemesi → Task 3

**Placeholder scan:** Yok — tüm adımlarda concrete içerik var.

**Type consistency:** Tüm görseller tutarlı — `manage_gameobject`, `manage_components`, `execute_code`, `manage_prefabs` isimleri üç task boyunca aynı.
