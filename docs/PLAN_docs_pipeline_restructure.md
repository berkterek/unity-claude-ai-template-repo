# PLAN — Docs Pipeline Restructure (GDD → TDD → Plan akışının yeniden tasarımı)

> **Status:** Proposal — araştırma + tartışma aşaması, henüz uygulanmadı
> **Date:** 2026-07-07
> **Scope:** `docs/` doküman yapısı + `/plan-workflow`, `/game-plan`, `/status`, `/continue`, `/orchestrate` ve bağlı komutlar
> **Karar:** Bu doküman onaylanmadan hiçbir komut/agent dosyası değiştirilmeyecek

---

## 1. Problem Tanımı

Mevcut akış:

```
/game-idea → docs/GDD.md
/architect → docs/TDD.md
/plan-workflow → docs/WORKFLOW.md        ← yatay fazlı iskelet planı
/orchestrate → docs/PROGRESS.md + EVENTS.jsonl
/game-plan → docs/0_MasterPlan.md + docs/1_X.md, 2_Y.md, ...   ← ikinci planlama turu
```

### Tespit edilen sorunlar

1. **İki rakip planlama sistemi.** `WORKFLOW.md` yatay fazlarla planlar (tüm infra → tüm pure C# → tüm testler → integration → scene). `/game-plan` dikey modüllerle planlar ("Modül 1 = oynanabilir core loop"). İkisi de `/orchestrate`'e beslenir ama kesitleri çelişir. İskeletin "yetersiz" hissedilmesinin kök nedeni bu: WORKFLOW fazlarının hiçbirinin sonunda oynanabilir bir şey yoktur, bu yüzden ikinci bir plan turu (`/game-plan`) ile yamalanır.
2. **Status 4 ayrı yerde:** `PROGRESS.md`, `EVENTS.jsonl`, `0_MasterPlan.md` tablosu, her modül planının kendi Status tablosu. Drift kaçınılmaz; `/continue` zaten "PROGRESS.md stale olabilir, events authoritative" diye uzlaştırma mantığı taşımak zorunda kalmış.
3. **Tüm modül planları önden, tek seferde üretiliyor.** `/game-plan` Step 4 bütün modül planlarını paralel spawn ile aynı anda yazar. Modül 1 implement edilir edilmez 3-4-5. planların code skeleton'ları bayatlar — artık var olmayan varsayımlara dayanır.
4. **Düz `docs/` içinde numaralı dosyalar** (`1_X.md`, `2_Y.md`): yeniden sıralama acısı; spec (ne/neden), design (nasıl) ve tasks (adımlar) tek dosyada iç içe.
5. **TDD monolit:** modül seviyesi detay da TDD'de, bu yüzden her plan turu TDD'nin tamamını yeniden okuyup gap analizi yapmak zorunda.

---

## 2. Araştırma Bulguları (örnek repolar)

### 2.1 GitHub Spec Kit — `specs/NNN-feature/` üçlüsü

- Akış: `/specify → /plan → /tasks → implement`. Her faz bir Markdown artefaktı üretir, bir sonrakini besler.
- Yapı: feature başına klasör → `spec.md` + `plan.md` + `tasks.md`; proje geneli `constitution.md` (bizim CLAUDE.md + rules/ karşılığı).
- **spec.md**: user story'ler **öncelikli ve bağımsız test edilebilir** (P1 tek başına MVP olmalı), Given/When/Then acceptance senaryoları, FR-001 numaralı gereksinimler, `[NEEDS CLARIFICATION]` işaretleme kuralı, ölçülebilir Success Criteria.
- **tasks.md**: görevler **user story bazında gruplanır**; küçük bir "Foundational (Blocking Prerequisites)" fazı tüm story'leri bloklar, sonrası story bazında bağımsız ilerler. `[P]` işareti = paralel çalıştırılabilir (bizim `parallel_group` karşılığı). Her story sonunda "Checkpoint: bu story tek başına çalışır durumda" doğrulaması.
- Kritik içgörü: **"Foundation" ayrı bir plan dokümanı değil, ilk tasks.md içinde küçük bir bloklayıcı fazdır.** İskelet için ayrı bir WORKFLOW.md üretmek yerine, foundation minimum tutulup ilk dikey dilimin içine gömülür.

### 2.2 Kiro (AWS) — `.kiro/specs/<feature>/` + steering

- Feature başına: `requirements.md` (EARS notasyonuyla test edilebilir gereksinimler) + `design.md` (mimari, sequence diyagramları) + `tasks.md` (takip edilebilir görevler).
- Proje geneli **steering** dosyaları: `product.md`, `tech.md`, `structure.md` — her konuşmaya otomatik dahil edilir. Bizim karşılığımız: GDD (product), TDD (tech), CLAUDE.md + rules (structure).
- Bugfix için ayrı hafif varyant (`bugfix.md`) — her iş aynı ağırlıkta şablon gerektirmez.

### 2.3 BMAD Method — sharding

- Brief → PRD (epic/story hiyerarşisi gömülü) → Architecture → PRD'nin **epic bazında shard'lanması** → her story dosyası self-contained (dev agent'a gereken tüm bağlam içinde).
- Gerekçe: "telephone game" etkisini kırmak — dev agent'ın context'ine tüm PRD değil, sadece kendi story'sinin tam bağlamı girer.
- Status story dosyasının kendi içinde yaşar; ayrıca merkezi bir progress dosyası yoktur.

### 2.4 Ortak payda (üç sistemin de yaptığı)

| İlke | Spec Kit | Kiro | BMAD |
|------|----------|------|------|
| Feature/modül başına dikey dilim klasörü | ✅ | ✅ | ✅ (shard) |
| Sabit dosya üçlüsü (ne / nasıl / adımlar) | ✅ | ✅ | ~ (story içinde) |
| Status tek yerde (tasks checkbox) | ✅ | ✅ | ✅ |
| Plan **just-in-time** üretilir, hepsi önden değil | ✅ | ✅ | ✅ |
| Proje geneli steering ayrı, ince | constitution | product/tech/structure | PRD+Arch |
| İlk dilim = tek başına çalışan MVP | ✅ (P1 story) | ✅ | ✅ (Epic 1) |

Mevcut yapımız bu altı ilkenin **hiçbirine tam uymuyor**; en yakın olduğumuz yer `/game-plan`'in modül kavramı — ama o da hepsini önden üretiyor ve status'u çoğaltıyor.

---

## 3. Hedef Yapı (öneri)

```
docs/
├── GDD.md                        ← kalır (product steering; /game-idea, /refine-gdd)
├── TDD.md                        ← kalır ama İNCELİR: stack, convention, scope tree,
│                                    asmdef haritası. Modül-detayı design.md'lere taşınır.
├── ROADMAP.md                    ← YENİ — 0_MasterPlan + WORKFLOW.md'nin yerine geçer:
│                                    modül tablosu, bağımlılık sırası, TEK status rollup
├── modules/
│   ├── 01-core-loop/
│   │   ├── spec.md               ← ne/neden: GDD kesiti, user story (P1/P2), acceptance
│   │   ├── design.md             ← nasıl: interface'ler, file map, installer/scope wiring,
│   │   │                            test-type kararları, TDD'ye referans
│   │   └── tasks.md              ← /orchestrate girdisi: checkbox + parallel_group +
│   │                                task başına dosya yolları + code skeleton
│   ├── 02-<sonraki>/             ← SADECE sırası geldiğinde üretilir (just-in-time)
│   └── ...
├── decisions/                    ← ADR'ler (mevcut, değişmez)
├── EVENTS.jsonl                  ← kalır — makine gerçeği (crash recovery, /continue)
└── (PROGRESS.md)                 ← KALKAR — insan gerçeği tasks.md + ROADMAP rollup olur
```

### Status modeli (tek kaynak ilkesi)

| Soru | Kaynak |
|------|--------|
| Bu task bitti mi? | İlgili modülün `tasks.md` checkbox'ı |
| Bu modül ne durumda? | `ROADMAP.md` tablosundaki tek satır (⏳/🔄/✅/🚫) |
| Orkestrasyon nerede kaldı? (crash recovery) | `EVENTS.jsonl` (zaten authoritative) |
| Geçmişte ne oldu? | git log + EVENTS.jsonl |

`PROGRESS.md` tamamen kalkar. `/continue`'daki "events authoritative, PROGRESS stale olabilir" uzlaştırma mantığı sadeleşir: events → tasks.md checkbox senkronu.

### Foundation nereye gidiyor? (WORKFLOW.md'nin cevapladığı soru)

Spec Kit modeli benimsenir: **ayrı iskelet planı yok.** `01-core-loop/tasks.md` içinde küçük bir "Phase 0 — Foundational (Blocking)" bölümü olur: EventBus, AppScope/AppInstaller, temel asmdef'ler — yalnızca core loop'un ihtiyaç duyduğu minimum. Sonraki modüller kendi foundation ihtiyaçlarını kendi tasks.md'lerine ekler. `/plan-workflow`'un 7 yatay fazı (tüm infra → tüm logic → ...) tamamen emekli olur.

---

## 4. Şablon Taslakları (Unity/repo kurallarına uyarlanmış)

### 4.1 `spec.md`

```markdown
# Spec: [Modül Adı]
> Status: Draft | Approved      ← onaylanmadan design üretilmez (Director gate mantığı)
> GDD ref: [GDD bölüm linki]

## Player Stories (öncelikli, bağımsız test edilebilir)
### PS1 — [başlık] (P1)
Independent Test: [bu story tek başına nasıl doğrulanır — Editor'de ne oynanır]
Acceptance: Given/When/Then maddeleri
### PS2 — ... (P2)

## Functional Requirements
- FR-001: Sistem ... yapmalı
- FR-00x: ... [NEEDS CLARIFICATION: ...]   ← belirsizlik gizlenmez, işaretlenir

## Out of Scope
## Assumptions
```

### 4.2 `design.md`

```markdown
# Design: [Modül Adı]
> Spec: spec.md | TDD ref: [bölüm]

## Yeni/Değişen Sözleşmeler
- Game.Abstracts.<Domain>: interface imzaları (contract doc kurallı — precondition/postcondition)
## Module Wiring
- [Domain]Installer kayıtları, AppInstaller.asset sırası, GameScope RegisterComponent listesi
## Events
- [Domain]Events.cs: readonly struct listesi (past tense + Event)
## File Map
| Dosya | Add/Modify | Not |
## Test Type Kararları
| Sınıf | EditMode / PlayMode-Programmatic / PlayMode-Scene / NoTest |
## Riskler / Açık Sorular
```

### 4.3 `tasks.md`

```markdown
# Tasks: [Modül Adı]
> Design: design.md | Status: ⏳/🔄/✅   ← modülün TEK status alanı burada + ROADMAP'e yansır

## Phase 0 — Foundational (Blocking)        ← sadece bu modülün gerektirdiği altyapı
- [ ] T001 ... (dosya yolları)
## Phase 1 — PS1 (P1) 🎯 oynanabilir dilim
- [ ] T002 [pg:1] Game/Abstracts/... interface
- [ ] T003 [pg:1] test (test-type-router kararına göre)
- [ ] T004 ...    ← her task: dosya yolu + kısa code skeleton + acceptance
**Checkpoint:** PS1 Independent Test geçer — Editor'de doğrulanır
## Phase 2 — PS2 (P2)
...
```

Mevcut `/create-plan` çıktı kalitesi (numbered steps, code skeleton, acceptance, parallel_group) korunur — sadece konumu ve üretim zamanı değişir. `parallel_group` formatı `/orchestrate` uyumluluğu için aynen kalır.

---

## 5. Komut Eşlemesi (eski → yeni)

| Eski | Yeni | Not |
|------|------|-----|
| `/game-idea` | değişmez | GDD üretimi aynı |
| `/architect` | **inceltilir** | Çıktı: slim TDD (stack/convention/scope tree). Modül detayı üretmez |
| `/plan-workflow` | **SİLİNİR** | Yatay faz modeli emekli; foundation tasks.md Phase 0'a gömülür |
| `/game-plan` | **ikiye bölünür** | `/roadmap`: bir kere — gap analizi (graph-first) + modül listesi + ROADMAP.md. `/plan-module <n>`: tek modülün spec+design+tasks üçlüsünü güncel codebase'e karşı üretir |
| `/create-plan`, `/update-plan` | değişmez | Modül-dışı ad-hoc işler için kalır (`docs/plans/` konvansiyonu) |
| `/orchestrate` | girdi değişir | `WORKFLOW.md` yerine `docs/modules/<n>/tasks.md`; PROGRESS yazmak yerine checkbox işaretler + ROADMAP satırını günceller; EVENTS.jsonl aynı |
| `/status` | sadeleşir | ROADMAP tablosu + aktif modülün tasks.md özeti |
| `/continue` | sadeleşir | EVENTS.jsonl → tasks.md senkronu (PROGRESS rebuild mantığı silinir) |
| `/refine-gdd`, `/refine-tdd` | küçük güncelleme | "PROGRESS.md oku" adımları ROADMAP/tasks.md okumaya döner |

### Etki alanı (değişecek dosyalar — grep ile doğrulandı)

- **PROGRESS.md referansı olan:** `commands/`: orchestrate, continue, status, validate, qa, learn, catch-up, refine-tdd; `agents/committer.md`
- **WORKFLOW.md / 0_MasterPlan referansı olan:** `commands/`: orchestrate, search, qa, game-plan, plan-workflow, refine-gdd, refine-tdd, catch-up, validate, status, dry-run, continue; `agents/committer.md`; `docs/`: commands.md, architecture-summary.md, orchestrate-rules.md; `skills/core/planning-and-task-breakdown.md`
- **CLAUDE.md**: komut tablosu + Session Start bölümü
- Toplam ~20 dosya. Tek oturumluk iş değil — aşağıdaki fazlama şart.

---

## 6. Migrasyon — Temiz Kesim (clean cut, karar: 2026-07-07)

> Karar: Kademeli geçiş / çift-girdi dönemi YOK. Bu repo bir template ve devam eden gerçek bir
> orkestrasyon koşusu bulunmuyor; eski yapıları taşımak yerine tek seferde silip yenisini koyuyoruz.

Tek oturumda, şu sırayla:

1. **Yeni sistemi yaz:** `docs/modules/` şablonları (spec/design/tasks), `/roadmap` ve `/plan-module` komutları, ROADMAP.md şablonu.
2. **`/orchestrate`'i dönüştür:** girdi `docs/modules/<n>/tasks.md`; PROGRESS.md yazımı yerine checkbox işaretleme + ROADMAP satır güncellemesi; EVENTS.jsonl aynen kalır. WORKFLOW.md desteği tamamen kaldırılır.
3. **Eskiyi sil:** `/plan-workflow` ve `/game-plan` komut dosyaları silinir; `docs/WORKFLOW.md` `docs/archive/`e taşınır.
4. **Referans temizliği:** PROGRESS/WORKFLOW/0_MasterPlan geçen ~20 dosya (bölüm 5'teki liste) tek geçişte güncellenir: continue, status, validate, qa, learn, catch-up, search, dry-run, refine-gdd, refine-tdd, committer, commands.md, architecture-summary.md, orchestrate-rules.md, planning-and-task-breakdown skill, CLAUDE.md.
5. **Smoke-test:** sahte bir mini modül (`docs/modules/00-smoke/`) ile `/roadmap` → `/plan-module` → `/orchestrate` (dry-run) zinciri doğrulanır; testten sonra 00-smoke silinir.

Geri dönüş yolu: temiz kesim tek commit'te yapılmaz — adım 1-2 / adım 3-4 / adım 5 ayrı commit'ler olur; bozulma çıkarsa `git revert` yeterli.

---

## 7. Bilinen Zayıflıklar / Riskler

1. **Upfront görünürlük kaybı:** tüm modül planlarını önden görmek artık mümkün değil — ROADMAP satır seviyesinde kalır. Bilinçli tercih: bayat detaylı plan < taze tek plan.
2. **Migrasyon genişliği:** ~20 dosya tek geçişte değişecek; ayrı commit'ler + git revert geri dönüş yolu (bölüm 6).
3. **`/orchestrate` regresyon riski:** temiz kesimde eski format fallback'i yok — parallel_group parse'ı, guard-gate ve EVENTS akışı bölüm 6 adım 5'teki smoke-test ile doğrulanmadan iş bitmiş sayılmaz.
4. **Spec onay gate'i disiplin ister:** spec.md `Approved` olmadan design üretilmemesi kuralı hook ile mi (yeni bir check script) yoksa komut içi gate ile mi zorlanacak — açık soru.

## 8. Açık Sorular (tartışılacak)

- [ ] `docs/modules/` mi `.claude/specs/` mi? (Kiro `.kiro/specs/` kullanıyor; öneri: `docs/modules/` — insan tarafından okunan her şey docs/ altında kalsın)
- [ ] Bugfix/mini işler için Kiro tarzı hafif varyant gerekli mi, yoksa mevcut `/create-plan --lean` yeterli mi? (öneri: yeterli)
- [ ] ROADMAP.md güncellemesini committer mı yapmalı, orchestrate phase-gate mi? (öneri: phase-gate — committer'ın "docs go last" kuralıyla uyumlu)
- [ ] Slim TDD'ye geçişte mevcut TDD şablonundan neler kesilecek — `/architect` revizyonu ayrı bir plan mı olmalı?

## 9. Kaynaklar

- Spec Kit: https://github.com/github/spec-kit — şablonlar: `templates/spec-template.md`, `plan-template.md`, `tasks-template.md` (birebir incelendi)
- Spec Kit SDD metodolojisi: https://github.com/github/spec-kit/blob/main/spec-driven.md
- Kiro Specs: https://kiro.dev/docs/specs/ ve https://kiro.dev/docs/specs/best-practices/
- BMAD Method: https://github.com/bmad-code-org/BMAD-METHOD
- Karşılaştırma: https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html
