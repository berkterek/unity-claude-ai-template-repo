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
