# Unity Projesi için .gitattributes (Git LFS Dahil)

## Açıklama

Aşağıdaki `.gitattributes` dosyası Unity projeleri için standart bir yapı sunar:

- **Git LFS** ile büyük binary dosyalar (FBX, PNG, texture, audio, video) izlenir — Git geçmişini şişirmez
- **Text dosyaları** (C# scriptler, JSON, YAML) normal Git ile izlenir, CRLF/LF normalizasyonu yapılır
- **Unity YAML dosyaları** (`.unity`, `.prefab`, `.asset`, `.mat`) merge-friendly şekilde işaretlenir
- **Binary olarak sabit tutulan** dosyalar (`.dll`, `.exe`) yanlışlıkla diff'e girmesin diye `binary` olarak işaretlenir

---

## .gitattributes İçeriği

```gitattributes
# =====================================================================
# Unity .gitattributes — Git LFS + CRLF normalizasyonu
# =====================================================================

# ---------------------
# Default behavior
# ---------------------
* text=auto eol=lf

# ---------------------
# Unity YAML (merge-friendly)
# ---------------------
*.unity         merge=unityyamlmerge eol=lf
*.prefab        merge=unityyamlmerge eol=lf
*.asset         merge=unityyamlmerge eol=lf
*.mat           merge=unityyamlmerge eol=lf
*.meta          merge=unityyamlmerge eol=lf
*.controller    merge=unityyamlmerge eol=lf
*.anim          merge=unityyamlmerge eol=lf
*.overrideController merge=unityyamlmerge eol=lf
*.physicsMaterial    merge=unityyamlmerge eol=lf
*.physicsMaterial2D  merge=unityyamlmerge eol=lf
*.playable           merge=unityyamlmerge eol=lf
*.renderTexture      merge=unityyamlmerge eol=lf
*.lighting           merge=unityyamlmerge eol=lf
*.cubemap            merge=unityyamlmerge eol=lf
*.flare              merge=unityyamlmerge eol=lf
*.giparams           merge=unityyamlmerge eol=lf
*.inputactions       merge=unityyamlmerge eol=lf
*.signal             merge=unityyamlmerge eol=lf
*.spriteatlas        merge=unityyamlmerge eol=lf
*.terrainlayer       merge=unityyamlmerge eol=lf
*.mixer              merge=unityyamlmerge eol=lf
*.shadergraph        merge=unityyamlmerge eol=lf
*.shadersubgraph     merge=unityyamlmerge eol=lf

# ---------------------
# C# ve script dosyaları (text)
# ---------------------
*.cs            text eol=lf diff=csharp
*.shader        text eol=lf
*.cginc         text eol=lf
*.hlsl          text eol=lf
*.glsl          text eol=lf
*.compute       text eol=lf
*.asmdef        text eol=lf
*.asmref        text eol=lf
*.json          text eol=lf
*.xml           text eol=lf
*.txt           text eol=lf
*.md            text eol=lf
*.yml           text eol=lf
*.yaml          text eol=lf

# ---------------------
# LFS — 3D Model dosyaları
# ---------------------
*.fbx           filter=lfs diff=lfs merge=lfs -text
*.FBX           filter=lfs diff=lfs merge=lfs -text
*.obj           filter=lfs diff=lfs merge=lfs -text
*.OBJ           filter=lfs diff=lfs merge=lfs -text
*.blend         filter=lfs diff=lfs merge=lfs -text
*.dae           filter=lfs diff=lfs merge=lfs -text
*.3ds           filter=lfs diff=lfs merge=lfs -text
*.max           filter=lfs diff=lfs merge=lfs -text
*.ma            filter=lfs diff=lfs merge=lfs -text
*.mb            filter=lfs diff=lfs merge=lfs -text

# ---------------------
# LFS — Texture dosyaları
# ---------------------
*.png           filter=lfs diff=lfs merge=lfs -text
*.PNG           filter=lfs diff=lfs merge=lfs -text
*.jpg           filter=lfs diff=lfs merge=lfs -text
*.JPG           filter=lfs diff=lfs merge=lfs -text
*.jpeg          filter=lfs diff=lfs merge=lfs -text
*.tga           filter=lfs diff=lfs merge=lfs -text
*.TGA           filter=lfs diff=lfs merge=lfs -text
*.psd           filter=lfs diff=lfs merge=lfs -text
*.PSD           filter=lfs diff=lfs merge=lfs -text
*.tif           filter=lfs diff=lfs merge=lfs -text
*.tiff          filter=lfs diff=lfs merge=lfs -text
*.bmp           filter=lfs diff=lfs merge=lfs -text
*.exr           filter=lfs diff=lfs merge=lfs -text
*.hdr           filter=lfs diff=lfs merge=lfs -text
*.gif           filter=lfs diff=lfs merge=lfs -text
*.iff           filter=lfs diff=lfs merge=lfs -text
*.pict          filter=lfs diff=lfs merge=lfs -text
*.tpsheet       filter=lfs diff=lfs merge=lfs -text

# ---------------------
# LFS — Audio dosyaları
# ---------------------
*.mp3           filter=lfs diff=lfs merge=lfs -text
*.wav           filter=lfs diff=lfs merge=lfs -text
*.ogg           filter=lfs diff=lfs merge=lfs -text
*.aiff          filter=lfs diff=lfs merge=lfs -text
*.aif           filter=lfs diff=lfs merge=lfs -text
*.flac          filter=lfs diff=lfs merge=lfs -text
*.mid           filter=lfs diff=lfs merge=lfs -text
*.midi          filter=lfs diff=lfs merge=lfs -text

# ---------------------
# LFS — Video dosyaları
# ---------------------
*.mp4           filter=lfs diff=lfs merge=lfs -text
*.mov           filter=lfs diff=lfs merge=lfs -text
*.avi           filter=lfs diff=lfs merge=lfs -text
*.webm          filter=lfs diff=lfs merge=lfs -text
*.ogv           filter=lfs diff=lfs merge=lfs -text

# ---------------------
# LFS — Font dosyaları
# ---------------------
*.ttf           filter=lfs diff=lfs merge=lfs -text
*.otf           filter=lfs diff=lfs merge=lfs -text
*.woff          filter=lfs diff=lfs merge=lfs -text
*.woff2         filter=lfs diff=lfs merge=lfs -text

# ---------------------
# Binary — DLL ve kütüphaneler
# ---------------------
*.dll           binary
*.pdb           binary
*.so            binary
*.dylib         binary
*.a             binary
*.lib           binary
*.exe           binary
*.unitypackage  filter=lfs diff=lfs merge=lfs -text
*.apk           filter=lfs diff=lfs merge=lfs -text
*.ipa           filter=lfs diff=lfs merge=lfs -text

# ---------------------
# LFS — Diğer Unity binary asset'leri
# ---------------------
*.cubemap       filter=lfs diff=lfs merge=lfs -text
*.unitypackage  filter=lfs diff=lfs merge=lfs -text
*.bytes         filter=lfs diff=lfs merge=lfs -text
```

---

## Kurulum Adımları

### 1. Git LFS'i Yükle

```bash
# macOS (Homebrew)
brew install git-lfs

# Windows (Chocolatey)
choco install git-lfs

# veya resmi siteden: https://git-lfs.github.com/
```

### 2. LFS'i Repo için Aktif Et

```bash
git lfs install
```

### 3. .gitattributes Dosyasını Repoya Ekle

`.gitattributes` dosyasını repo köküne (`Assets/` ile aynı seviyeye) kaydet.

### 4. UnityYAMLMerge Aracını Kur (Opsiyonel ama Önerilir)

`.unity` ve `.prefab` merge çakışmalarını düzgün çözmek için:

```bash
# macOS — .gitconfig'e ekle:
git config --global merge.unityyamlmerge.name "Unity SmartMerge"
git config --global merge.unityyamlmerge.driver \
  "'/Applications/Unity/Hub/Editor/<VERSION>/Unity.app/Contents/Tools/UnityYAMLMerge' merge -p %O %B %A %A"
```

Unity versiyonunu kendi kurulum yolunla değiştir.

### 5. Mevcut Büyük Dosyaları LFS'e Taşı (Eğer Zaten Commit'lendilerse)

```bash
# Geçmişi yeniden yaz — dikkatli kullan, takımla koordinasyon gerektirir
git lfs migrate import --include="*.png,*.fbx,*.mp3" --everything
git push --force
```

---

## Önemli Notlar

| Konu | Açıklama |
|------|----------|
| `.meta` dosyaları | LFS'e almıyoruz — text olarak tutuyoruz. `.meta` dosyaları küçüktür ve Git geçmişinde okunabilir kalması önemlidir |
| `.dll` dosyaları | LFS yerine `binary` olarak işaretliyoruz. NSubstitute gibi eklentiler için idealdir; diff almak zaten anlamsız |
| GitHub LFS limiti | Ücretsiz hesapta 1 GB depolama + 1 GB/ay bant genişliği. Unity projeleri için GitHub LFS Data Pack satın almayı değerlendir |
| `.unity` ve `.prefab` | LFS'e almıyoruz — bu YAML dosyalarıdır, text olarak tutulur ve `unityyamlmerge` ile merge edilir |
