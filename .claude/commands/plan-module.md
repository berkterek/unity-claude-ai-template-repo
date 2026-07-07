---
name: plan-module
description: Tek bir modülün spec+design+tasks üçlüsünü güncel codebase'e karşı just-in-time üretir. /roadmap tarafından belirlenen modül numarası ile çalışır.
---

# /plan-module — Modül Planlayıcı (Just-in-Time)

Tek bir modülün `docs/modules/<n>-<name>/` klasörünü oluşturur: `spec.md`, `design.md`, `tasks.md`.

## Kullanım

```
/plan-module 01
/plan-module 01-core-loop
```

## Kurallar

- Sadece belirtilen modülü planla — diğer modüllere dokunma
- `tasks.md` doğrudan `/orchestrate` girdisi olacak format: checkbox'lar + `[parallel_group:N]` + dosya yolları + code skeleton + acceptance criteria
- Mevcut codebase'i tara: hangi dosyalar zaten var, hangisi eksik? Var olanları "Add" yerine "Modify" olarak işaretle
- Eğer `docs/modules/<n>-<name>/` zaten varsa: "Bu modül zaten planlandı" diyerek dur — üzerine yazma

## Süreç

### Step 1 — Okuma

1. $ARGUMENTS'ten modül numarası/adını parse et
2. `docs/ROADMAP.md` oku — bu modülün adını, bağımlılıklarını ve önceliğini bul
3. `docs/GDD.md` oku — bu modülle ilgili bölümü bul
4. `docs/TDD.md` oku — bu modüle ait mimari kararları bul
5. Mevcut codebase'i tara: bu modülle ilgili mevcut .cs dosyalarını listele

Eğer modül zaten `docs/modules/<n>-<name>/` altında varsa:
```
Modül <n> zaten planlandı: docs/modules/<n>-<name>/
Mevcut planı güncellemek için /update-plan komutunu kullan.
```
diyerek dur.

### Step 2 — ARCHITECTURE_GATE

Kullanıcıya şu bilgileri göster ve onay iste:

```
## ARCHITECTURE_GATE — <n>-<name> Modülü

**GDD özeti:** [bu modül ne yapıyor]
**Önerilen yapı:**
- Abstracts: [interface listesi]
- Concretes: [class listesi]
- Module installer: [Domain]Module.cs
- Events: [event listesi]

**Onaylamak için `go`, değiştirmek için açıkla:**
```

Gate onaylanmadan (kullanıcı `go` yazmadan) bir sonraki adıma geçme.

### Step 3 — Planlama Subagent'ı

`lean-planner` subagent'ını spawn et (`model: sonnet`). Subagent'a şunu ver:
- Modülün GDD özeti
- TDD'deki ilgili mimari kararlar
- Mevcut codebase scan sonuçları
- Şablon formatı: `docs/modules/_templates/` altındaki spec/design/tasks şablonları

Subagent çıktısı olarak üç dokümanın taslağını al.

### Step 4 — REVIEWER

`reviewer` subagent'ı spawn et (`model: sonnet`). Şunları kontrol etmesini iste:
- `tasks.md`'deki tüm task'lar `/orchestrate` uyumlu mu? (checkbox + dosya yolu + acceptance)
- `parallel_group` annotations doğru mu?
- `spec.md` acceptance criteria'ları test edilebilir mi? (Given/When/Then formatı)
- `design.md` interface imzaları mevcut architecture kurallarına uygun mu?

### Step 5 — SAVE

Üç dosyayı `docs/modules/<n>-<name>/` altına kaydet:
- `spec.md`
- `design.md`
- `tasks.md`

`docs/ROADMAP.md`'daki ilgili satırı güncelle: Status → `⏳ Pending`, Plan sütununa link ekle.

Kullanıcıya göster:
```
✅ Modül <n>-<name> planlandı

docs/modules/<n>-<name>/spec.md
docs/modules/<n>-<name>/design.md
docs/modules/<n>-<name>/tasks.md

Sıradaki adım: `/orchestrate docs/modules/<n>-<name>/tasks.md`
```

$ARGUMENTS
