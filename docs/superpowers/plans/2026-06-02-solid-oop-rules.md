# SOLID & OOP Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `.claude/rules/solid-oop.md` kural dosyasını oluştur ve CLAUDE.md'ye kaydet.

**Architecture:** Tek dosya, iki bölüm — MonoBehaviour (View/Provider sınırları) ve normal C# (SRP/OCP/DIP). CLAUDE.md rules tablosuna eklenir.

**Tech Stack:** Markdown, Unity C#

---

### Task 1: solid-oop.md Kural Dosyasını Oluştur

**Files:**
- Create: `.claude/rules/solid-oop.md`

- [ ] **Step 1: Dosyayı oluştur**

`.claude/rules/solid-oop.md` içeriği:

```markdown
# SOLID & OOP Rules (NON-NEGOTIABLE)

## MonoBehaviour — Rol Sınırları

MonoBehaviour yalnızca **View** veya **Provider** rolü üstlenebilir.

| Rol | Ne yapar | Ne yapmaz |
|---|---|---|
| **View** | UI günceller, input okur, animasyon tetikler | Business logic, hesaplama, state yönetimi |
| **Provider** | Unity API'yi (Physics, Transform, AudioSource) soyutlar | Servis koordinasyonu, event publishing |

### Sınırlar

- Max ~100 satır — aşılırsa sınıf iki role ayrılıyor demektir
- `Update()`/`FixedUpdate()` içinde business logic yok — sadece `ReadValue()`, `SetMoveInput()` gibi ince çağrılar
- `Awake()`/`Start()` içinde initialization logic yok — VContainer `Initialize()` bunu üstlenir
- Hiç `new Service()` yok — her dependency `[Inject]` ile gelir

### Forbidden

```csharp
// BAD — MonoBehaviour hem hesaplıyor hem UI güncelliyor hem event yayıyor
private void Update()
{
    _score += Time.deltaTime * _multiplier; // business logic — buraya ait değil
    _label.text = _score.ToString();        // servis çıktısını göster, hesaplama yok
    if (_score > 100) _eventBus.Publish(new ScoreThresholdEvent()); // yayma service'in işi
}

// GOOD — View sadece service'i çağırıyor
private void Update()
{
    _scoreService.Tick(Time.deltaTime);
}

// GOOD — Provider Unity API'yi soyutluyor
public sealed class BasicAudioProvider : MonoBehaviour, IAudioProvider
{
    [SerializeField] private AudioSource _source;

    public void Play(AudioClip clip) => _source.PlayOneShot(clip);
}
```

---

## Normal C# Class — SRP (Single Responsibility Principle)

**Temel kural:** Her class tek bir cümleyle açıklanabilmeli — ve cümle `AND` içermemeli.

```
✓ "AudioService sesleri çalar."
✓ "ScoreModel skoru takip eder."
✗ "PlayerService hareketi hesaplar VE skoru günceller VE event yayar."
         → 3 sorumluluk = 3 farklı class
```

### Sorumluluk Testi — Kod Yazmadan Önce Sor

| Soru | Kötü işaret |
|---|---|
| Bu class'ı tek cümleyle açıklayabilir miyim? | Açıklayamazsan SRP ihlali |
| Cümle AND içeriyor mu? | İçeriyorsa böl |
| Bu class neden değişir? | Birden fazla nedeni varsa böl |

---

## OCP (Open/Closed Principle)

Yeni davranış eklemek mevcut class'ı değiştirmemeli.

```csharp
// BAD — her yeni enemy türü bu switch'i değiştiriyor (OCP ihlali)
public void ProcessEnemy(EnemyType type)
{
    if (type == EnemyType.Fast) { /* ... */ }
    else if (type == EnemyType.Tank) { /* ... */ }
}

// GOOD — yeni enemy = yeni class, mevcut kod değişmez
public interface IEnemy
{
    void Attack();
}

public sealed class FastEnemy : IEnemy
{
    public void Attack() { /* hızlı saldırı */ }
}

public sealed class TankEnemy : IEnemy
{
    public void Attack() { /* ağır saldırı */ }
}
```

---

## DIP (Dependency Inversion Principle)

Constructor sadece interface alır, concrete almaz.

```csharp
// BAD — concrete'e bağımlı
public sealed class PlayerService
{
    private readonly AudioService _audio; // concrete — DIP ihlali

    public PlayerService(AudioService audio) => _audio = audio;
}

// GOOD — interface'e bağımlı
public sealed class PlayerService
{
    private readonly IAudioService _audio;

    public PlayerService(IAudioService audio) => _audio = audio;
}
```

---

## Forbidden Patterns Özet

| Forbidden | Neden | Doğrusu |
|---|---|---|
| MonoBehaviour'da business logic | SRP ihlali | Service'e taşı |
| `Update()` içinde hesaplama | SRP + performance | Service'de, View sadece çağırır |
| `new Service()` MonoBehaviour içinde | DIP ihlali | `[Inject]` kullan |
| Constructor'da concrete parametre | DIP ihlali | Interface parametre al |
| `if/else if` chain ile tip kontrolü | OCP ihlali | Polymorphism kullan |
| AND içeren class sorumluluğu | SRP ihlali | İki class'a böl |
| `Awake()`/`Start()` içinde init logic | VContainer sırasını bozar | `Initialize()` kullan |
```

- [ ] **Step 2: Commit**

```bash
git add .claude/rules/solid-oop.md
git commit -m "feat(rules): add solid-oop.md — SRP/OCP/DIP rules for MonoBehaviour and C# classes"
```

---

### Task 2: CLAUDE.md Rules Tablosuna Ekle

**Files:**
- Modify: `.claude/CLAUDE.md` — satır 103'ten sonra yeni satır ekle

- [ ] **Step 1: Rules tablosuna satır ekle**

`.claude/CLAUDE.md` satır 103 (`bootstrap-pattern.md` satırı) sonrasına ekle:

```
| `solid-oop.md` | MonoBehaviour rol sınırları (View/Provider only, ~100 satır max); SRP tek-cümle testi (AND içermemeli); OCP polymorphism kuralı; DIP constructor-interface kuralı |
```

- [ ] **Step 2: Commit**

```bash
git add .claude/CLAUDE.md
git commit -m "docs(claude-md): register solid-oop.md in rules table"
```
