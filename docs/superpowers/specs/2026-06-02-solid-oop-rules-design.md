# SOLID & OOP Rules Design

**Date:** 2026-06-02  
**Scope:** `.claude/rules/solid-oop.md` — yeni kural dosyası  
**Target:** MonoBehaviour sınıfları ve normal C# sınıfları

---

## Problem

`.claude/rules/` altında SOLID prensiplerine dair explicit kural yok. Mevcut kurallar teknik pattern'lere (VContainer, UniTask, InputSystem) odaklanıyor ama şu ihlaller tekrar ediyor:

1. **God Class (SRP)** — bir class çok fazla sorumluluk taşıyor
2. **Concrete dependency (DIP)** — interface yerine concrete class'a bağımlılık
3. **OCP ihlali** — yeni feature için mevcut class değiştiriliyor

---

## Yaklaşım

Tek dosya: `solid-oop.md`  
İki bölüm: MonoBehaviour kuralları + Normal C# kuralları  
CLAUDE.md'ye `@` ile eklenir.

---

## Bölüm 1 — MonoBehaviour Kuralları

**Temel kural:** MonoBehaviour yalnızca **View** veya **Provider** rolü üstlenebilir.

| Rol | Ne yapar | Ne yapmaz |
|---|---|---|
| **View** | UI günceller, input okur, animasyon tetikler | Business logic, hesaplama, state yönetimi |
| **Provider** | Unity API'yi (Physics, Transform, AudioSource) soyutlar | Servis koordinasyonu, event publishing |

**Sınırlar:**
- Max ~100 satır — aşılırsa sınıf iki role ayrılıyor demektir
- `Update()`/`FixedUpdate()` içinde business logic yok — sadece `ReadValue()`, `SetMoveInput()` gibi ince çağrılar
- `Awake()`/`Start()` içinde initialization logic yok — VContainer `Initialize()` bunu üstlenir
- Hiç `new Service()` yok — her dependency `[Inject]` ile gelir

**Forbidden:**
```csharp
// BAD — MonoBehaviour hem hesaplıyor hem UI güncelliyor hem event yayıyor
private void Update()
{
    _score += Time.deltaTime * _multiplier; // business logic
    _label.text = _score.ToString();        // UI
    if (_score > 100) _eventBus.Publish(...); // event
}

// GOOD — sadece service'i çağırıyor
private void Update()
{
    _scoreService.Tick(Time.deltaTime);
}
```

---

## Bölüm 2 — Normal C# Class Kuralları (SRP)

**Temel kural:** Her class tek bir cümleyle açıklanabilmeli — ve cümle `AND` içermemeli.

```
✓ "AudioService sesleri çalar."
✓ "ScoreModel skoru takip eder."
✗ "PlayerService hareketi hesaplar VE skoru günceller VE event yayar."
         → 3 sorumluluk = 3 farklı class
```

**Sorumluluk testi:**

| Soru | Kötü işaret |
|---|---|
| Bu class'ı tek cümleyle açıklayabilir miyim? | Açıklayamazsan SRP ihlali |
| Cümle AND içeriyor mu? | İçeriyorsa böl |
| Bu class neden değişir? | Birden fazla nedeni varsa böl |

**OCP — Open/Closed Principle:**
```csharp
// BAD — her yeni enemy türü bu switch'i değiştiriyor
public void Attack(EnemyType type)
{
    if (type == EnemyType.Fast) { ... }
    else if (type == EnemyType.Tank) { ... }
}

// GOOD — yeni enemy = yeni class, mevcut kod değişmez
public interface IEnemy { void Attack(); }
public sealed class FastEnemy : IEnemy { public void Attack() { ... } }
public sealed class TankEnemy : IEnemy { public void Attack() { ... } }
```

**DIP — Dependency Inversion Principle:**
```csharp
// BAD
public sealed class PlayerService
{
    private readonly AudioService _audio; // concrete
}

// GOOD
public sealed class PlayerService
{
    private readonly IAudioService _audio; // interface
}
```

---

## Bölüm 3 — Forbidden Patterns Özet

| Forbidden | Neden | Doğrusu |
|---|---|---|
| MonoBehaviour'da business logic | SRP ihlali | Service'e taşı |
| `Update()` içinde hesaplama | SRP + performance | Service'de, View sadece çağırır |
| `new Service()` MonoBehaviour içinde | DIP ihlali | `[Inject]` kullan |
| Constructor'da concrete parametre | DIP ihlali | Interface parametre al |
| `if/else if` chain ile tip kontrolü | OCP ihlali | Polymorphism kullan |
| AND içeren class sorumluluğu | SRP ihlali | İki class'a böl |
| `Awake()`/`Start()` içinde init logic | VContainer sırasını bozar | `Initialize()` kullan |

---

## Implementation Plan

1. `solid-oop.md` dosyasını `.claude/rules/` altına yaz
2. CLAUDE.md rules tablosuna ekle ve `@` referansı ekle
