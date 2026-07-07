---
name: roadmap
description: GDD + TDD + mevcut modülleri okuyarak docs/ROADMAP.md modül tablosunu oluşturur veya günceller. Her modül için bağımlılık sırası, öncelik ve status belirlenir. /plan-module için girdi görevi görür.
---

# /roadmap — Modül Yol Haritası Üretici

GDD + TDD + mevcut `docs/modules/` içeriğini okuyarak `docs/ROADMAP.md` dosyasını yazar.

## Kullanım

```
/roadmap
```

## Süreç

### Step 1 — Okuma

Şu dosyaları sırayla oku:
1. `docs/GDD.md` — tam oyun tasarım dokümanı (varsa)
2. `docs/TDD.md` — teknik mimari (varsa)
3. `docs/ROADMAP.md` — mevcut roadmap (varsa; olmayabilir)
4. `docs/modules/` altındaki tüm modülleri tara:
   - Her `docs/modules/<n>-<name>/tasks.md` içindeki Status satırını oku
   - Mevcut modüllerin listesini çıkar

### Step 2 — Gap Analizi

GDD'deki oyun sistemleri ile `docs/modules/` altındaki mevcut modülleri karşılaştır:
- Hangi sistemlerin planı var? (modül klasörü mevcut)
- Hangi sistemlerin planı yok? (GDD'de var ama modül klasörü yok)
- Bağımlılık sırası: Hangi modül hangi modülün önünde gelmeli?

### Step 3 — ROADMAP.md Yaz

`docs/ROADMAP.md` dosyasını yaz (varsa güncelle, yoksa oluştur):

```markdown
# ROADMAP

> Son güncelleme: [tarih]
> Kaynak: GDD + TDD gap analizi

## Modül Tablosu

| # | Modül | Bağımlı | Öncelik | Status | Plan |
|---|-------|---------|---------|--------|------|
| 01 | core-loop | — | P1 | ⏳ Pending | [plan](modules/01-core-loop/tasks.md) |
| 02 | audio | core-loop | P2 | ⏳ Pending | [plan](modules/02-audio/tasks.md) |

> Status: ⏳ Pending / 🔄 In Progress / ✅ Complete / 🚫 Blocked

## Sıradaki Adım

`/plan-module 01` — core-loop modülünü planla
```

### Step 4 — Özet Yaz

Kullanıcıya şunu göster:
- Kaç modül bulundu (GDD'den)
- Kaç modülün planı zaten var
- Kaç modülün planı eksik
- Önerilen sıradaki komut: `/plan-module <n>`

$ARGUMENTS
