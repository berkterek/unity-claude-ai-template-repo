# Commit Gruplandırma ve Mesajı

## Bu 3 dosya tek bir commit'e gitmeli

`IAudioService.cs`, `AudioService.cs` ve `AudioInstaller.cs` birbirinden bağımsız commit'e bölünmemelidir çünkü:

- Üçü birlikte tek bir modülü (Audio) oluşturur
- `AudioInstaller` zaten `AudioService`'i kayıt eder, `AudioService` da `IAudioService`'i implement eder — biri olmadan diğerleri derlenmez
- Bu proje mimarisinde bir modül: interface (Abstracts/) + service + installer (Concretes/) üçlüsünden oluşur

## Dosyaları Grupla (stage)

```bash
git add Assets/_GameFolders/Scripts/Games/Abstracts/Audio/IAudioService.cs
git add Assets/_GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs
git add Assets/_GameFolders/Scripts/Games/Concretes/Audio/AudioInstaller.cs
# .meta dosyaları da varsa ekle
git add Assets/_GameFolders/Scripts/Games/Abstracts/Audio/IAudioService.cs.meta
git add Assets/_GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs.meta
git add Assets/_GameFolders/Scripts/Games/Concretes/Audio/AudioInstaller.cs.meta
```

## Commit Mesajı

```
feat(audio): add IAudioService interface, AudioService, and AudioInstaller

Implements the audio module following the project's ModuleInstaller pattern.
IAudioService defines the public contract, AudioService is the sealed
implementation, and AudioInstaller registers the service via VContainer.
```

Kısa versiyonu yeterliyse:

```
feat(audio): add audio module (IAudioService, AudioService, AudioInstaller)
```

## Neden bu format?

- `feat(audio):` — Conventional Commits formatı, projede bu format kullanılıyor (bkz. son commit'ler: `feat(planning):`, `feat(rules):`, `feat(pipeline):`)
- Başlık kısa (70 karakter altı)
- Body neden yapıldığını açıklıyor, neyin eklendiğini değil
- Tüm modül birlikte commit'leniyor: derleme bütünlüğü korunuyor
