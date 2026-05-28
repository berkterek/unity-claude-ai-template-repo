# Commit Gruplandırma: AudioService Modülü

## Kaç commit gerekiyor?

Bu üç dosya tek bir atomic commit'e girer — hepsi aynı `audio` modülünün parçası ve aralarında bağımlılık var (`AudioService`, `IAudioService`'i implement ediyor; `AudioInstaller` ikisini de kullanıyor).

## Hangi dosyalar eklenmeli?

Her `.cs` dosyasının yanında bir `.meta` dosyası olması **zorunlu** — her ikisi aynı commit'e girer:

```
IAudioService.cs
IAudioService.cs.meta
AudioService.cs
AudioService.cs.meta
AudioInstaller.cs
AudioInstaller.cs.meta
```

Gerçek yollar mimariye göre:
```
_GameFolders/Scripts/Games/Abstracts/Audio/IAudioService.cs
_GameFolders/Scripts/Games/Abstracts/Audio/IAudioService.cs.meta
_GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs
_GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs.meta
_GameFolders/Scripts/Games/Concretes/Audio/AudioInstaller.cs
_GameFolders/Scripts/Games/Concretes/Audio/AudioInstaller.cs.meta
```

## Git komutları

```bash
# Asla git add -A ya da git add . kullanma — her dosyayı ayrı ayrı ekle
git add _GameFolders/Scripts/Games/Abstracts/Audio/IAudioService.cs \
        _GameFolders/Scripts/Games/Abstracts/Audio/IAudioService.cs.meta \
        _GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs \
        _GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs.meta \
        _GameFolders/Scripts/Games/Concretes/Audio/AudioInstaller.cs \
        _GameFolders/Scripts/Games/Concretes/Audio/AudioInstaller.cs.meta

git commit -m "feat(audio): add AudioService with IAudioService interface and installer"
```

## Commit message analizi

| Alan | Değer | Neden |
|------|-------|-------|
| type | `feat` | Yeni bir gameplay/servis sistemi ekleniyor |
| scope | `audio` | Modül adı — domain tabanlı scope kullanılır |
| description | `add AudioService with IAudioService interface and installer` | Imperative mood, 3 bileşeni tek cümlede özetliyor |

### Neden `infra` değil `feat`?

`infra` tipi assembly definition, project config ve bootstrap layer değişiklikleri içindir. `AudioService` bir gameplay sistemi — `feat` doğru seçim.

### Neden tek commit?

Skill'in Commit Grouping Strategy'sine göre sıra:
1. Assembly definitions → ayrı commit (varsa)
2. **Interfaces (`Abstracts/`)** → bu commit
3. **Core logic (`Concretes/`)** → bu commit
4. Tests → ayrı commit (test dosyaları varsa)

`IAudioService`, `AudioService`, ve `AudioInstaller` aynı sistem sınırında yer aldığı ve birbiri olmadan anlam taşımadığı için tek commit'e girer. Eğer testler de yazıldıysa onlar **ayrı** bir `test(audio)` commit'i olmalı.

## Eğer testler de varsa — iki ayrı commit

```bash
# Commit 1 — implementation
git add [yukarıdaki 6 dosya]
git commit -m "feat(audio): add AudioService with IAudioService interface and installer"

# Commit 2 — tests
git add _GameFolders/Scripts/Tests/.../AudioServiceTests.cs \
        _GameFolders/Scripts/Tests/.../AudioServiceTests.cs.meta
git commit -m "test(audio): add unit tests for AudioService"
```
