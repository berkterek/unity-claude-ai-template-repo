---
name: save-load
description: SaveLoadSystem kullanım paterni — proje içindeki kayıt/yükleme implementasyonu, konum, namespace ve kod örnekleri
model-tier: normal
---

# SaveLoadSystem — Kullanım Paterni

## Konum
`Assets/_AssetFolders/_Framework/SaveLoadSystems/`
Assembly: `FrameworkSaveLoadSystems` | Namespace: `Framework.SaveLoadSystems`

## Yapı

```
ISaveLoadDal       → storage erişim soyutlaması (PlayerPrefs, cloud, db vb.)
ISaveLoadService   → oyun kodunun kullandığı üst seviye API
SaveLoadManager    → ISaveLoadService implementasyonu, ISaveLoadDal'a delege eder
LocalSaveLoadDal   → ISaveLoadDal implementasyonu, PlayerPrefs + Newtonsoft.Json kullanır
```

## VContainer Kaydı

```csharp
builder.Register<LocalSaveLoadDal>(Lifetime.Singleton).As<ISaveLoadDal>();
builder.Register<SaveLoadManager>(Lifetime.Singleton).As<ISaveLoadService>();
```

Oyun kodunda her zaman `ISaveLoadService` inject edilir — `SaveLoadManager` veya `LocalSaveLoadDal` doğrudan kullanılmaz.

## Plain C# Verisi Kaydetme / Yükleme

`LocalSaveLoadDal` plain C# nesneleri için Newtonsoft.Json kullanır:

```csharp
// Kaydet
_saveLoadService.SaveDataProcess("player_coins", 500);
_saveLoadService.SaveDataProcess("player_data", new PlayerData { Level = 3, Name = "Ali" });

// Yükle
int coins = _saveLoadService.LoadDataProcess<int>("player_coins");
PlayerData data = _saveLoadService.LoadDataProcess<PlayerData>("player_data");

// Key kontrolü
if (_saveLoadService.HasKeyAvailable("player_coins")) { }

// Silme
_saveLoadService.DeleteData("player_coins");
```

## Unity Object Kaydetme / Yükleme

Unity Object'leri (ScriptableObject vb.) için `JsonUtility` kullanılır:

```csharp
_saveLoadService.SaveUnityObjectProcess("config", myScriptableObject);
MyConfig loaded = _saveLoadService.LoadUnityObjectProcess<MyConfig>("config");
```

## Yeni Storage Backend Ekleme

`ISaveLoadDal`'ı implement eden yeni bir sınıf yaz (örn. `CloudSaveLoadDal`), VContainer kaydını güncelle. `SaveLoadManager` ve oyun kodu değişmez.

```csharp
public class CloudSaveLoadDal : ISaveLoadDal
{
    // ISaveLoadDal metodlarını cloud API ile implement et
}
```

## LogTag

SaveLoad operasyonları `LogTag.SaveLoad` tag'i ile loglanır. Debug sırasında açmak için:

```csharp
DLog.Enable(LogTag.SaveLoad);
```
