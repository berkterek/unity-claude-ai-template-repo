# Orphaned .meta Dosyası Sorunu

## Sorun Nedir?

Evet, bu bir sorundur. `PlayerController.cs` silindi ama `PlayerController.cs.meta` dosyası bırakıldı — bu bir **orphaned .meta** durumudur.

Unity, her asset için `.meta` dosyasındaki `guid:` değerini kullanarak referansları takip eder. Orphaned bir `.meta` dosyası şu sorunlara yol açar:

- Unity asset veritabanında sahte/hayalet bir giriş oluşturur
- Eğer başka bir prefab, scene veya script bu GUID'e referans veriyorsa, referans kırılır (missing script/missing asset hatası)
- Takım üyelerinde tutarsız asset database durumuna neden olur

---

## Ne Yapmalısın?

### 1. Orphaned .meta'yı doğrula

Depoda gerçekten orphaned bir `.meta` olup olmadığını kontrol et:

```bash
find Assets -name "*.meta" | while read meta; do
  asset="${meta%.meta}"
  [ ! -e "$asset" ] && echo "ORPHANED: $meta"
done
```

Bu komut `ORPHANED: Assets/Scripts/Player/PlayerController.cs.meta` çıktısını vermelidir.

### 2. Orphaned .meta dosyasını git'ten kaldır

```bash
git rm Assets/Scripts/Player/PlayerController.cs.meta
git commit -m "fix(player): remove orphaned meta file for deleted PlayerController"
```

### 3. Takım arkadaşınla durumu netleştir

`PlayerController.cs` kasıtlı mı silindi? Eğer evet:
- `.meta` dosyası da silinmeli — Unity Editor'da silme işlemi yapıldığında Editor her ikisini birlikte siler. El ile dosya sistemi üzerinden silme yapıldığında `.meta` unutulabiliyor.

Eğer yanlışlıkla silindi:
- `git log -- Assets/Scripts/Player/PlayerController.cs` ile son commit'i bul
- `git checkout <commit-hash> -- Assets/Scripts/Player/PlayerController.cs` ile geri yükle
- `.meta` dosyası zaten mevcut olduğu için GUID korunmuş olur — referanslar sağlam kalır

---

## Önlem: Bundan Sonra

Unity Editor'da dosya silme işlemi her zaman **Project window üzerinden** yapılmalı, asla dosya sistemi veya terminal üzerinden değil. Editor her iki dosyayı (asset + .meta) birlikte siler ve GUID tutarlılığını korur.

```
# YANLIS — .meta unutulur
rm Assets/Scripts/Player/PlayerController.cs

# DOGRU — Unity Editor'da: Project window → sag tik → Delete
# Veya git'te her ikisini birden sil:
git rm Assets/Scripts/Player/PlayerController.cs Assets/Scripts/Player/PlayerController.cs.meta
```
