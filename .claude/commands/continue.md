# Continue Orchestration Agent

Kesilen bir orkestrasyon çalışmasını tam olarak kaldığı yerden devam ettirir.

## Initialization

1. `$ARGUMENTS`'ten tasks.md yolunu oku. Eksikse: "tasks.md yolu gerekli. Kullanım: /continue docs/modules/01-core-loop/tasks.md"
2. `docs/GDD.md` ve `docs/TDD.md`'yi bağlam için oku.
3. Belirtilen `tasks.md`'yi oku.
4. `docs/EVENTS.jsonl`'u oku (varsa) — gerçek durum kaynağı.

## Resume Process

### Step 1: Event Replay ile Durumu Belirle

`docs/EVENTS.jsonl` varsa, son olayları okuyarak hangi task'ların tamamlandığını anla:
- `TASK_COMPLETED` eventi olan task'lar → zaten bitti
- `ORCHESTRATION_PAUSED` eventi → checkpoint'te durdu
- `TASK_BLOCKED` eventi → bloke edilmiş task

tasks.md checkbox'larıyla karşılaştır: eğer events'te TASK_COMPLETED var ama checkbox `- [ ]` ise, checkbox'ı `- [x]` olarak güncelle.

### Step 2: Recovery Planı

tasks.md'deki duruma göre:
- `- [x]` checkbox → tamamlandı, atla
- `- [ ]` checkbox → bekliyor, çalıştır
- EVENTS.jsonl'da `TASK_BLOCKED` → bloğu raporla, kullanıcıdan çözüm iste

### Step 3: Kullanıcıya Raporla

```
## Devam Ediliyor

tasks.md: [path]
Tamamlandı: [N] task
Bekliyor: [M] task
Bloke: [K] task

Devam etmek için `go` yaz:
```

### Step 4: Devam Et

Kullanıcı onayından sonra `/orchestrate docs/modules/<n>-<name>/tasks.md` mantığıyla devam et:
- Tamamlanan task'ları (`[x]`) atla
- Bekleyen task'ları çalıştır
- orchestration-active.json oluştur:
  ```bash
  echo '{"started":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","module":"[modül adı]"}' > .claude/orchestration-active.json
  ```

## Kurallar
- Tamamlanmış task'ları yeniden çalıştırma
- Review adımını atlatma
- `EVENTS.jsonl` events'i tasks.md checkbox'larından daha güvenilirdir

$ARGUMENTS
