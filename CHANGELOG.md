# Activity Tracker - Degisiklik Gunlugu

## v1.1.0 — 2026-02-09

### Kritik Hata Duzeltmesi: Arka Plan Muzik Sure Takibi

**Sorun:** Kullanici Spotify veya Apple Music'te muzik acip baska bir uygulamaya (ornegin Figma) gectiginde, muzik uygulamasinin suresi donuyordu. Uygulama sadece onde (frontmost) olan uygulamayi takip ettigi icin, arka planda calisan muzik suresi kaydedilmiyordu.

**Kok neden:** `WindowMonitor.poll()` her 2 saniyede `NSWorkspace.shared.frontmostApplication` ile SADECE one cikmis uygulamayi takip ediyordu. Bu tasarim geregi dogruydu ancak kullanicinin beklentisi arka planda muzik calarken de sure birikmesiydi.

**Cozum:** `BackgroundProcessMonitor` (Terminal arka plan islemleri icin zaten mevcut) desenini muzik uygulamalari icin kopyaladik.

---

### Yeni Dosya

#### `Sources/ActivityTracker/Core/BackgroundMusicMonitor.swift`

Arka planda calisan muzik uygulamalarini izleyen yeni monitor sinifi.

- **Izlenen uygulamalar:** Spotify (`com.spotify.client`), Apple Music (`com.apple.Music`)
- **Throttle:** 8 saniyede bir AppleScript sorgusu (sistem yuku minimumda)
- **Cift sayim onleme:** Onde olan uygulama ise atlar (foreground merger halleder)
- **Guvenlk kontrolleri:**
  - Uygulama calismiyorsa atlar (`NSWorkspace.shared.runningApplications` kontrol — AppleScript uygulamayi acmaz)
  - Muzik duraklatilmissa/durdurulmussa atlar (`player state is playing` kontrol)
- **Kayit:** `extraInfo: "Background Listening"` etiketi ile DB'ye yazilir
- **Temizlik:** Duran uygulamalarin merger'lari flush edilip hafizadan silinir
- **Bagimsiz merger:** Her muzik uygulamasi icin ayri `HeartbeatMerger` (Spotify + Apple Music ayni anda calabilir)

### Degistirilen Dosya

#### `Sources/ActivityTracker/Core/WindowMonitor.swift` (5 nokta)

| Satir | Degisiklik | Aciklama |
|-------|-----------|----------|
| 9 | `private var musicMonitor: BackgroundMusicMonitor?` | Yeni property eklendi |
| 36 | `self.musicMonitor = BackgroundMusicMonitor(store: store)` | init'te olusturma |
| 146 | `musicMonitor?.check(frontmostBundleId:interval:)` | Her poll'da cagirilir |
| 74 | `musicMonitor?.stop()` | Durdurulurken temizlik |
| 85 | `musicMonitor?.flushAll()` | Duraklatilirken flush |

### Degistirilmeyen (Dogrulanan) Dosyalar

Asagidaki dosyalar incelendi ve **dogru calistigi dogrulandi**, degisiklik yapilmadi:

| Dosya | Durum | Aciklama |
|-------|-------|----------|
| `HeartbeatMerger.swift` | Dogru | Medya uygulamalari icin pencere basligi degisikliklerini gormezden geliyor (`hasPrefix("virtual.")`, Spotify, Music). `accumulatedSeconds += interval` dogru artiyor. `periodicFlush()` her 30sn, uygulama degisiminde aninda `flush()`. `updateDuration` SET operasyonu (INCREMENT degil). |
| `ActivityStore.swift` | Dogru | Minimum sure filtresi yok, tum kayitlar dahil. INSERT/UPDATE islemleri dogru. `queryDay` tum `extraInfo` degerlerini (`WindowKey`) ayriyor. |
| `ActivityRecord.swift` | Dogru | `extraInfo` alani mevcut, "Background Listening" etiketi icin yeterli. |
| `AppDetailExtractor.swift` | Dogru | Spotify/Apple Music icin `extractSpotifyDetails()` ve `extractAppleMusicDetails()` onde olan uygulama icin "Now Playing" etiketi ile calisiyordu. Bu fonksiyonlar foreground takibi icin aynen kaliyor. |
| `IdleDetector.swift` | Dogru | `CGEventSource.secondsSinceLastEventType` ile 10dk idle tespiti. `WindowMonitor`'da `isCurrentPassiveMedia` kontrolu ile muzik/video uygulamalari ondeyken idle pause atlaniyordu. |
| `BackgroundProcessMonitor.swift` | Dogru | Terminal arka plan islemleri icin mevcut desen. Yeni `BackgroundMusicMonitor` bu deseni birebir takip ediyor. |

---

### Edge Case Davranislari

| Senaryo | Beklenen Davranis |
|---------|-------------------|
| Kullanici Spotify'a gecer (onde) | Background monitor Spotify'i atlar, foreground merger devralir |
| Kullanici Spotify'dan baska uygulamaya gecer | Foreground flush, ~8sn icinde background monitor devralir |
| Spotify durdurulur (pause) | `isPlaying` false → merger flush edilir, temizlenir |
| Spotify kapatilir (quit) | `runningApplications` icermez → atlanir, merger flush edilir |
| Sistem idle (10dk) | `poll()` durur → ne foreground ne background heartbeat uretilir |
| Uyku/uyanma | `pause()` → `flushAll()`, uyaninca poll tekrar baslar |
| Spotify + Apple Music ayni anda | Ikisi de bagimsiz izlenir (ayri merger'lar) |
| Rapor olusturma | "Background Listening" etiketli kayitlar raporda gorunur |
| "Now Playing" vs "Background Listening" | Onde: "Now Playing", arkada: "Background Listening" — karistirmaz |

---

### Mimari Ozet

```
poll() [her 2sn]
  |
  +-- Foreground: NSWorkspace.frontmostApplication
  |     +-- AppDetailExtractor (Spotify ondeyse "Now Playing")
  |     +-- HeartbeatMerger (foreground)
  |
  +-- BackgroundProcessMonitor [6sn throttle]
  |     +-- Terminal tab'lari (bg process)
  |
  +-- BackgroundMusicMonitor [8sn throttle]  ← YENi
        +-- Spotify: calisiyor mu? caliyor mu?
        +-- Apple Music: calisiyor mu? caliyor mu?
        +-- Evet → HeartbeatMerger (background, "Background Listening")
        +-- Hayir → flush & temizle
```

### Dogrulama Adimlari

1. `swift build -c release` — Basarili
2. Binary `/Applications/Activity Tracker.app/Contents/MacOS/` icine kopyalandi
3. Test plani:
   - Spotify ac, sarki cal, Figma'ya gec, 30+ saniye bekle
   - Rapor olustur → "Background Listening" etiketli Spotify kaydi gorunmeli
   - Spotify'a geri don → "Now Playing" etiketi ile foreground kaydi baslamali
   - Spotify'i durdur → background kaydi bitmeli

---

### Onceki Oturumlardan Mevcut Ozellikler (Referans)

Bu oturumdan once zaten implement edilmis olan ozellikler:

- **Akilli site ayirma:** YouTube, GitHub, ChatGPT, Claude, X (Twitter), Notion, Linear tarayici icinden ayri uygulama olarak izleniyor (`virtual.*` bundle ID'leri)
- **Terminal arka plan izleme:** `BackgroundProcessMonitor` ile derleme, git, npm gibi islemler izleniyor
- **Safari/Chrome URL takibi:** AppleScript ile aktif sekme URL ve basligi aliniyor
- **Idle ve uyku tespiti:** 10dk hareketsizlikte otomatik duraklama, ekran kilidi/uyku algilama
- **Pasif medya muafiyeti:** YouTube/Spotify/Music ondeyken idle detection duraklama tetiklemez
- **HeartbeatMerger birlestirme:** Medya uygulamalarinda sarki degistikce yeni kayit acilmaz, sure biriktirilir
