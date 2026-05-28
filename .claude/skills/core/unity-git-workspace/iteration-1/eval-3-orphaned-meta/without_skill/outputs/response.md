# Orphaned .meta Dosyası — Baseline

Evet, bu bir sorundur.

Unity, her asset'e `Assets/` klasörü altındaki `.meta` dosyasında saklanan benzersiz bir GUID atar. Prefab, scene ve script referansları bu GUID'lere dayanır. `PlayerController.cs` silindi ama `.meta` dosyası kaldıysa:

- Unity, asset veritabanında hayalet bir giriş oluşturabilir
- Bu GUID'e atıfta bulunan scene veya prefab dosyaları "missing script" uyarısı gösterebilir

## Çözüm

```bash
git rm Assets/Scripts/Player/PlayerController.cs.meta
git commit -m "chore: remove orphaned meta file for deleted PlayerController"
```

Ya da Unity Editor'ı açıp Project penceresinde meta'nın olduğu klasörü yenilediğinizde Editor otomatik olarak orphaned .meta'yı temizleyebilir.

## Önlem

Bundan sonra dosya silme işlemlerini Unity Editor'ın Project penceresinden yapın — Editor, `.cs` ve `.cs.meta` dosyalarını birlikte siler.
