---
name: logging
description: DLog kullanım paterni — proje içindeki logging implementasyonu, konum, namespace ve kod örnekleri
model-tier: normal
---

# DLog — Kullanım Paterni

## Konum
`Assets/_AssetFolders/_Framework/Logging/`
Assembly: `FramworkLogging` | Namespace: `Framework.Logging`

## Yapı

```
LogTag    → enum, hangi sistemin log attığını belirtir
DLog      → static wrapper, [Conditional] ile production'da sıfır maliyet
```

## Mevcut LogTag'ler

```csharp
public enum LogTag
{
    General,   // genel amaçlı
    EventBus,  // EventBus subscribe/publish logları
    SaveLoad   // kayıt/yükleme operasyonları
}
```

Yeni bir sistem eklendiğinde `LogTag` enum'una o sisteme ait tag eklenir.

## Kullanım

```csharp
DLog.Log(LogTag.General, "Mesaj");
DLog.Warning(LogTag.SaveLoad, "Uyarı mesajı");
DLog.Error(LogTag.EventBus, "Hata mesajı");
```

## Tag Aktifleştirme / Deaktifleştirme

Varsayılan olarak sadece `LogTag.General` aktif. Diğer tag'leri runtime'da açıp kapatmak için:

```csharp
DLog.Enable(LogTag.EventBus);   // EventBus loglarını aç
DLog.Disable(LogTag.EventBus);  // EventBus loglarını kapat
```

Bu sayede sadece debug ettiğin sisteme ait logları görebilirsin.

## Önemli Davranış

- Tüm metodlar `[Conditional("UNITY_EDITOR")]` ve `[Conditional("DEVELOPMENT_BUILD")]` ile işaretli
- Production build'lerde (`DEVELOPMENT_BUILD` olmayan) tüm DLog çağrıları derleme sırasında kaldırılır — runtime maliyeti sıfır
- `Debug.Log` yerine doğrudan `DLog` kullanılır, production'da log kalmaz
