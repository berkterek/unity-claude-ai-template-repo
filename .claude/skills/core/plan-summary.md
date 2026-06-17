---
name: plan-summary
description: Plan dosyasını okuyup 3 bölümlü insan dilinde özet üretir — ne yapıyoruz, nasıl, sonunda ne görürüz. Gate yok, agent spawn yok.
---

# Plan Summary

Verilen plan dosyasını okuyup sabit 3 bölümlü özet üret. Bu skill'i çalıştırmak demek:

1. `<file>` parametresini oku
2. Dosya yoksa: `"Dosya bulunamadı: <path>. Önce /create-plan çalıştırın."` yaz ve dur
3. Dosyada task yoksa: `"Plan dosyası task içermiyor. /update-plan ile içerik ekleyin."` yaz ve dur
4. Aşağıdaki formatta özet üret — başka bir şey yazma

## Çıktı Formatı (değiştirme)

```
## Plan Özeti — <dosya adı>

### Ne yapıyoruz?
[1-2 cümle. Projenin hangi parçasına dokunuyoruz ve amacı ne. Teknik detay değil.]

### Nasıl yapıyoruz?
[Bullet list. Her task için 1 satır, insan dilinde. "AudioInstaller'a Register<T> ekle" değil → "Ses sistemi bağımlılık enjeksiyonuna bağlanacak".]

### Sonunda ne göreceğiz?
[Observable çıktılar. Her madde gözlemlenebilir bir sonuç. "kod yazılacak" değil → "Oyunu çalıştırdığında ses duyulacak". Format: "X çalışacak / Y Inspector'da görünecek / Z testi geçecek".]
```

## Kurallar

- Sadece plan dosyasını oku — kaynak kod dosyalarını açma
- Özet bölümlerinin dışına hiçbir şey yazma (giriş cümlesi, açıklama, öneri yok)
- Sonuç bölümündeki her madde mutlaka gözlemlenebilir olmalı
- Tone: sade Türkçe, teknik jargon minimum
