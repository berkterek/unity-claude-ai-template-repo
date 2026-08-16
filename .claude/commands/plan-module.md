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

### Step 0 — Knowledge Graph Preload

Herhangi bir codebase taraması veya subagent spawn'ından önce, knowledge graph'ın bu modül planlamasını hızlandırıp hızlandıramayacağına karar ver.

`.claude/project-features.json` kontrol et:
- `.graph == true` VE `.claude/graph/graph.json` mevcut → graph yolu adayı.
- Aksi halde → `GRAPH_CONTEXT` boş bırak, Step 1'e geç (mevcut file-scan davranışı, değişmedi).

Aday ise, graph'ın **kullanılabilir** olduğunu doğrula (fresh VE non-empty):

```bash
python3 -c "
import json, os, time
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
n = len(cb.get('classes', []))
lb = '.claude/graph/.last-build'
age_h = (time.time() - os.path.getmtime(lb)) / 3600 if os.path.exists(lb) else 1e9
print('classes=%d age_h=%.1f' % (n, age_h))
"
```

- `classes == 0` ise (boş graph — örn. henüz oyun kodu olmayan taze bir template) → `GRAPH_CONTEXT` boş bırak, sessizce file scan'e düş. Uyarma — boş graph geçerli bir durumdur.
- `age_h > 24` ise (stale) → kullanıcıya bildir, sonra file scan'e düş:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated planning. Falling back to file scan.
  ```
- Aksi halde (fresh VE non-empty) → `GRAPH_CONTEXT`'i graph inventory'sinden oluştur:

```bash
python3 -c "
import json
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
classes = cb.get('classes', [])
interfaces = cb.get('interfaces', [])
events = cb.get('events', [])
installers = cb.get('vcontainer', {}).get('installers', [])
print('CLASSES (%d):' % len(classes))
for c in classes:
    print('  %s | mono=%s | deps=%s | pub=%s | sub=%s' % (
        c['name'], c.get('is_mono_behaviour', False),
        c.get('dependencies', []), c.get('events_published', []), c.get('events_subscribed', [])))
print('INTERFACES (%d):' % len(interfaces))
for i in interfaces: print('  %s' % i['name'])
print('EVENTS (%d):' % len(events))
for e in events: print('  %s' % e['name'])
print('INSTALLERS (%d):' % len(installers))
for inst in installers:
    regs = [r.get('type','') for r in inst.get('registrations', [])]
    print('  %s | registrations=%s' % (inst['name'], regs))
"
```

Bu çıktıyı `GRAPH_CONTEXT` olarak sakla ve Step 3'teki `lean-planner` subagent prompt'una göm. `GRAPH_CONTEXT` boşsa, planlama aşaması tıpkı öncesi gibi davranır — regresyon yok.

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

**Önce (BLOCKING):** spec/design/tasks yazıldıktan sonra, gate'i göstermeden önce çalıştır:

```bash
.claude/scripts/validate-plan-paths.sh <modül plan klasörü>
.claude/scripts/validate-plan-facts.sh <modül plan klasörü>
```

exit 2 → plan `rules/architecture.md` ile çelişiyor. Sessizce devam etme, klasörü de kendi kafana göre uydurma: çelişkiyi ARCHITECTURE_GATE bloğunun içinde göster, üç seçenekle (planı değiştir / `.claude/path-allowlist.txt` + `rules/architecture.md`'ye istisnayı yaz / dur). Kararı kullanıcı verir. `NO PATHS FOUND` pass değildir. Hook'un susması hiçbir zaman "doğrulandı" demek değildir — spec'e AC olarak "uyumlu, doğrulandı" yazmak için `checked:` satırı şart.

`validate-plan-facts.sh` exit 2 → en az bir task `Callers:`/`Wiring:` eksik ya da beyan ettiği kaynak plan içinde/diskte çözülmüyor. Sessizce devam etme: ihlali ARCHITECTURE_GATE bloğunda göster, planı düzelt ya da dur — kararı kullanıcı verir. `NO TASKS FOUND` pass değildir — script'in kendi ifadesiyle "this is NOT a pass"; elle doğrula.

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
- Aşağıdaki Knowledge Graph bloğu (Step 0'dan)
- Şablon formatı: `docs/modules/_templates/` altındaki spec/design/tasks şablonları

Prompt'a şu bloğu ekle:

```
## Knowledge Graph (mevcut class/interface/event/installer envanteri — dosya taramadan ÖNCE bunu sorgula)
[INSERT HERE: the GRAPH_CONTEXT output from the Step 0 preload step — if empty, write "No usable graph — scan source files directly."]
```

Talimat: Yukarıdaki graph inventory boş değilse, önce onu kullan — zaten var olan interface/class/installer/dependency'leri graph'tan oku, sadece belirli bir satır/detay için kaynak dosyayı aç. Graph boşsa (veya "No usable graph" yazıyorsa), önceki gibi mevcut codebase scan sonuçlarına dayan.

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
