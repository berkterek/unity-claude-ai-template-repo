# Pipeline Status Reporter

Proje pipeline'ının mevcut durumunu hızlıca gösterir.

## Process

1. Şu dosyaları oku (varsa):
   - `docs/GDD.md` — Oyun Tasarım Dokümanı
   - `docs/TDD.md` — Teknik Mimari
   - `docs/ROADMAP.md` — Modül yol haritası ve status rollup
   - `docs/modules/` — mevcut modüllerin tasks.md'lerini tara

2. Pipeline aşamasını belirle:
   - **Hiç doküman yok** → Pipeline başlamadı. `/game-idea` veya GDD oluştur.
   - **Yalnızca GDD** → GDD hazır. Sıradaki: `/architect`
   - **GDD + TDD** → Mimari hazır. Sıradaki: `/roadmap`
   - **GDD + TDD + ROADMAP** → Yol haritası hazır. Sıradaki: `/plan-module <n>`
   - **Modül planları var** → Her tasks.md'nin checkbox durumunu oku ve özetle.

3. `docs/ROADMAP.md` varsa modül tablosunu göster (mevcut status'larıyla).

4. Son 10 EVENTS.jsonl olayını göster (varsa):
   ```
   ### Son Olaylar
   - [10:35:00] ORCHESTRATION_COMPLETE — 01-core-loop
   - [10:34:00] TASK_COMPLETED — T003
   ...
   ```

5. Proje dosyalarını tara:
   - `.cs` dosya sayısı: `_GameFolders/Scripts/`
   - Test dosyası sayısı: `_GameFolders/Scripts/Tests/`
   - Prefab sayısı: `_GameFolders/Prefabs/`

## Çıktı Formatı

```
## Pipeline Status

**Proje:** [GDD'den oyun adı veya "Başlamadı"]
**Mevcut Aşama:** [aşama adı]
**Sıradaki Adım:** [çalıştırılacak komut]

### Dokümanlar
- [✅|❌] GDD  — docs/GDD.md
- [✅|❌] TDD  — docs/TDD.md
- [✅|❌] ROADMAP — docs/ROADMAP.md

### Modüller (ROADMAP özeti)
| # | Modül | Status |
|---|-------|--------|
| 01 | core-loop | ✅ Complete |
| 02 | audio | ⏳ Pending |

### Son Olaylar (EVENTS.jsonl)
[son 10 olay]

### Üretilen Varlıklar
- C# Scripts: [sayı]
- Test Dosyaları: [sayı]
- Prefablar: [sayı]
```

$ARGUMENTS
