# CursorMeterFS — CLAUDE.md

macOS menu bar uygulaması: **Codex / Claude / Cursor** kotalarını sekmeli popover'da
gerçek zamanlı izler. CodexBar (kardeş proje) mimarisinin hafif portu.
**Admin yetkisi gerektirmez** — tüm veriler kullanıcı-home dosyaları veya login keychain'den.

## Çoklu Sağlayıcı Veri Kaynakları (hepsi admin-siz)

| Sağlayıcı | Kimlik | Kota API | Offline fallback |
|-----------|--------|----------|------------------|
| Cursor | `state.vscdb` (read-only) | `cursor.com/api/*` | — |
| Codex | `~/.codex/auth.json` | `chatgpt.com/backend-api/wham/usage` | `~/.codex/sessions/**` son `token_count.rate_limits` |
| Claude | `~/.claude/.credentials.json` → Keychain `Claude Code-credentials` | `api.anthropic.com/api/oauth/usage` (`anthropic-beta: oauth-2025-04-20`) | — |

Mimari kural (CodexBar'dan): **sağlayıcılar veri döndürür (`ProviderSnapshot`), UI'ı app sahiplenir.**
Şeritler DİNAMİK: API ne döndürürse render edilir (Claude `limits[]` weekly_scoped → "<model> only";
Codex `additional_rate_limits[]`) — model adları asla hardcode edilmez.
Cost (USD) tahmini: yerel JSONL token sayımı × `CostPricing` tablosu (network yok).
Token yenileme yalnız BELLEKTE tutulur — `auth.json`/`.credentials.json`'a asla yazılmaz.

---

## Teknik Temel (Doğrulanmış)

### Cursor Local Auth — state.vscdb
Cursor, kimlik bilgilerini lokal SQLite'ta saklar:
```
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
  Tablo : ItemTable
  Key   : cursorAuth/accessToken    → JWT (424 karakter)
           cursorAuth/refreshToken   → JWT
           cursorAuth/cachedEmail    → kullanıcı e-postası
           cursorAuth/stripeMembershipType → plan tier ("pro", "ultra" vb.)
```

### Session Token Türetme
```
sub = JWT.payload.sub          // örn. "auth0|abc123user"
userId = sub.split("|").last   // "abc123user"
sessionToken = "\(userId)%3A%3A\(accessToken)"
Cookie header: WorkosCursorSessionToken=<sessionToken>
```

### API Endpoint'leri (resmi değil — değişebilir)
| Endpoint | Method | Ne Döner |
|----------|--------|---------|
| `cursor.com/api/usage?user=<userId>` | GET | `numRequests`, `maxRequestUsage` (dinamik kota!), `startOfMonth` |
| `cursor.com/api/dashboard/get-monthly-invoice` | POST `{month,year,includeUsageEvents:true}` | Usage event'leri (model, token, maliyet) |
| `cursor.com/api/dashboard/get-hard-limit` | POST | Harcama limiti |
| `cursor.com/api/dashboard/get-usage-based-premium-requests` | POST | On-demand açık mı |

**Önemli:** `maxRequestUsage` her zaman API'den gelir, **asla hardcode edilmez**.
Pro'da 1000, Ultra'da farklı, yarın değişebilir — her zaman API değerini kullan.

---

## Güvenlik Sözleşmesi — Zorunlu

```
✅ state.vscdb  → SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX (asla yazma)
✅ auth.json / .credentials.json → salt-okunur; yenilenen token yalnız bellekte
✅ Keychain     → yalnız okuma: "Claude Code-credentials" (login keychain)
✅ Ağ           → yalnız https://cursor.com, chatgpt.com, auth.openai.com,
                  api.anthropic.com (her istekte url.host doğrulanır, ATS HTTPS-only)
✅ Log          → token/email asla yazdırılmaz; debug'da sadece uzunluk gösterilir
✅ Export       → ~/.cursormeterfs/usage.json içinde secret YOK (sadece yüzde/sayı)
✅ XSS          → WebView yok; tüm string'ler SwiftUI Text ile (otomatik escape)
✅ Credential   → kod içinde hardcoded credential yasak; .env / Keychain kullan
```

---

## Mimari

```
Menu bar (NSStatusItem) ← AppKit
Popover / Settings      ← SwiftUI (NSHostingController içinde)
State                   ← UsageStore (@MainActor ObservableObject)
Auth                    ← CursorTokenReader → KeychainService
API                     ← CursorAPIClient (actor, retry/backoff)
SQLite                  ← libsqlite3 (sistem, ekstra bağımlılık yok)
```

### Veri Akışı (her refresh)
```
1. KeychainService.load(.sessionToken)  → hızlı yol
   VEYA CursorTokenReader.readCredentials()  → SQLite okuma → Keychain'e yaz
2. TeamResolver.resolveTeamId()        → team planı için teamId
3. CursorAPIClient.fetchUsage()        → numRequests + maxRequestUsage (dinamik!)
4. CursorAPIClient.fetchMonthlyInvoice() → usage events (son N request)
5. CursorAPIClient.fetchHardLimit()    → spending limit
6. UsageStore state güncel → NSStatusItem ikonu + popover yeniden çizilir
7. Eşik aşıldıysa NotificationService bildirim gönderir
8. exportEnabled ise UsageExporter ~/.cursormeterfs/usage.json yazar (secret'sız)
```

### Token Yenileme
```
401 alındıysa → Keychain'i temizle → state.vscdb'den taze oku → tekrar dene
3 başarısız denemeden sonra → loggedOut state → kullanıcıya "Cursor'a giriş yap" göster
```

---

## Klasör Yapısı

```
CursorMeterFS/
  App/
    CursorMeterFSApp.swift      @main, LSUIElement=YES ile dock'tan gizli
    AppDelegate.swift         NSStatusItem, NSPopover, Settings window, Combine
  Models/
    Provider.swift            .codex/.claude/.cursor — displayName/ikon/brandColor
    ProviderSnapshot.swift    RateWindow/NamedRateWindow/UsagePace/ProviderUIState
    Plan.swift                Cursor plan tier'ları (yalnız Cursor sağlayıcısı)
    UsageData.swift           Cursor detayları (on-demand kart, export)
    UsageEvent.swift          model/token/cost + displayModelName normalizasyonu
    UsageStatus.swift         .safe/.warning/.critical  +  from(fraction:thresholds:)
  Services/
    Providers/
      ProviderClient.swift        protokol: fetch() -> ProviderSnapshot
      CursorProviderClient.swift  eski refresh gövdesi (state.vscdb + cursor.com)
      CodexProviderClient.swift   wham/usage + session-log fallback
      ClaudeProviderClient.swift  oauth/usage + dinamik limits[] şeritleri
      Codex/                      CodexAuthReader/CodexAPIClient/CodexSessionLogReader
      Claude/                     ClaudeCredentialsReader/ClaudeAPIClient
    Cost/
      CostPricing.swift           model→fiyat tablosu (tahmini USD)
      CostScanner.swift           JSONL token sayımı, mtime-cache'li (actor)
    JWT.swift                 base64url decode, sub claim, exp check
    CursorTokenReader.swift   state.vscdb read-only, userId çıkarımı, session token
    KeychainService.swift     Security framework (Cursor legacy)
    CursorAPIClient.swift     actor; host doğrulama; Cookie header; retry/backoff
    TeamResolver.swift        team plan teamId cache
    UsageStore.swift          @MainActor; providerStates dict; withTaskGroup fan-out;
                              adaptif timer; suspend/resume
    RefreshFrequency.swift    manual/sabit/adaptive mod enum'u
    AdaptiveRefreshPolicy.swift saf politika: etkileşim+güç+termal → cadence
    NotificationService.swift UNUserNotificationCenter; provider-agnostik eşikler
    LoginItemService.swift    SMAppService.mainApp (macOS 13+)
    UsageExporter.swift       ~/.cursormeterfs/usage.json (sadece agregat veriler)
  Views/
    PopoverRootView.swift     header + ProviderTabStrip + ProviderDetailView + footer
    Providers/
      ProviderTabStrip.swift      sekmeler: ikon + ad + marka-renkli kalan-kota çizgisi
      ProviderDetailView.swift    plan rozeti, şeritler, cost, Cursor ekstraları
      RateWindowRow.swift         tek kota şeridi (başlık/%/bar/reset/pace)
    UsageCardView.swift       StatusBadge (paylaşılan)
    RecentRequestsView.swift  son N request (model + token + maliyet)
    OnboardingView.swift      Cursor login yok durumu
    Settings/
      SettingsView.swift            TabView iskelet
      GeneralSettingsView.swift     auth, plan override, refresh, ikon stili
      NotificationsSettingsView.swift  slider'lar, test butonu
      AboutView.swift               versiyon, güvenlik notu, linkler
    MenuBar/
      MenuBarIconRenderer.swift     6 stil × 2 mod (Battery/Circular/Minimal/Segments/DualBar/Gauge)
  Utilities/
    Color+Usage.swift         renk eşlemeleri (SwiftUI + NSColor)
    Date+Reset.swift          relativeDescription, billing cycle helpers
  Resources/
    Info.plist                LSUIElement=YES, ATS kısıtı (sadece cursor.com)
    CursorMeterFS.entitlements  Keychain, network client, hardened runtime
    Assets.xcassets           AppIcon, MenuBarIcon
CursorMeterFSTests/
  JWTDecoderTests.swift       JWT decode, userId, session token format, expiry
  UsageStatusTests.swift      eşik mantığı, Plan parse, Date helpers
  CursorAPIClientTests.swift  mock response parse, dinamik kota, defensive decode
project.yml                   XcodeGen konfigürasyonu
```

---

## Build & Run

```bash
# 1. Bağımlılık kur (sadece ilk seferinde)
brew install xcodegen

# 2. Xcode projesi üret
xcodegen generate

# 3. Aç + derle
open CursorMeterFS.xcodeproj
# Xcode → Product → Run  (⌘R)
# İlk çalıştırmada: Signing & Capabilities → Team seç (Personal Team yeterli)
```

### CLI ile build & test
```bash
xcodebuild -scheme CursorMeterFS -destination "platform=macOS" build
xcodebuild -scheme CursorMeterFS -destination "platform=macOS" test
```

### ÖNEMLİ: Yeni dosya eklendiğinde `xcodegen generate` şart
`project.yml`'de `sources: path: CursorMeterFS` klasör bazlı tanımlı — yani `.xcodeproj`
dosya listesi otomatik senkronize OLMAZ. `Views/`, `Services/`, `Models/` vb. altına
**yeni bir `.swift` dosyası eklendiğinde/silindiğinde** mutlaka:
```bash
xcodegen generate
```
çalıştırılmalı, yoksa Xcode o dosyayı target'a dahil etmez ve derleme
`Cannot find 'X' in scope` hatası verir (dosya diskte var, kod doğru, ama proje
dosyaya referans vermiyor demektir). Var olan bir dosyayı düzenlemek bu adımı
gerektirmez — sadece dosya ekleme/silme/yeniden adlandırmada gerekir.

---

## Geliştirme Notları

### API değişirse ne yapmalı?
Cursor'ın API'leri resmi/dökümante değildir. Kırılırsa:
1. `CursorAPIClientTests.swift`'teki mock JSON'ları gerçek response ile karşılaştır
2. `CursorAPIClient.swift` → `UsageAPIResponse` / `InvoiceResponse` modellerini güncelle
3. `UsageStore.swift` → `refresh()` içindeki parse mantığını ayarla
4. Graceful degradation: son bilinen veriyi göster + hata rozeti (asla crash etme)

### Yeni menü bar ikonu stili eklemek
1. `MenuBarIconStyle` enum'una yeni case ekle (`UsageStore.swift`)
2. `MenuBarIconRenderer.swift`'e `static func newStyleImage(...)` ekle
3. `switch style` bloğuna yönlendir
4. `GeneralSettingsView.swift` → ikon grid otomatik güncellenir (ForEach)

### Plan tipi değişirse
`Plan.from(rawValue:)` fonksiyonu (`Models/Plan.swift`) bilinmeyen değerleri `.pro`'ya
düşürür. Yeni tier eklenirse buraya case ekle.

### Token süresi dolarsa
`CursorAPIClient` 401 döndüğünde `APIError.tokenInvalid` fırlatır.
`UsageStore.refresh()` bunu yakalar → Keychain'i temizler → SQLite'tan taze okur.
Cursor uygulaması da token'ı periyodik yenilediğinden genellikle taze bulunur.

### Keychain günde birkaç kez şifre soruyorsa
Kök neden: kurulu app'in **ad-hoc imzası** (paid Apple hesabı yok, bkz. `release.yml`)
stabil bir Team ID/sertifikaya bağlı değil — macOS'un "Her zaman izin ver" güveni relock/
uyku-uyanma/reboot sonrası bu yüzden düşer ve `ClaudeCredentialsReader`'ın login keychain'deki
`Claude Code-credentials` (Claude Code CLI'ye ait, cross-app) okuması tekrar prompt açar.
İki taraflı çözüm: `scripts/sign-local.sh` kurulu app'i login keychain'de oluşturduğu kalıcı
self-signed sertifikayla yeniden imzalar (imza artık sabit kalır); ayrıca
`ClaudeCredentialsReader` credential'ı bellekte `expiresAt`'e kadar cache'ler (`isFresh`),
böylece Keychain her refresh yerine token ömrü başına ~1 kez okunur. `tokenInvalid` sonrası
`invalidate()` cache'i temizler. Detay: `README.md` → "Keychain Prompt Reappears Multiple
Times a Day".

---

## Test Stratejisi

| Katman | Test Dosyası | Kapsam |
|--------|-------------|--------|
| JWT | `JWTDecoderTests` | decode, userId, session token format, expiry |
| İş mantığı | `UsageStatusTests` | eşik, Plan parse, Date helpers, fraction |
| API parse | `CursorAPIClientTests` | mock JSON, dinamik kota, eksik alan dayanıklılığı |
| Entegrasyon | Manuel | Gerçek state.vscdb → API çağrısı → UI |

**Kural:** Gerçek `cursor.com` API'ye çarpan testler yazma (network bağımlılığı).
Mock JSON ile parse katmanını test et; entegrasyon testi manuel yap.

---

## Güvenlik Kontrol Listesi (commit öncesi)

- [ ] `grep -r "cursorAuth\|accessToken\|sessionToken" . --include="*.swift"` → sadece Keychain/Reader'da olmalı
- [ ] Log çıktılarında token substring yok
- [ ] `state.vscdb`'ye yazma yok (`SQLITE_OPEN_READONLY` flag'i kaybolmadı)
- [ ] Host doğrulama (`validateHost`) kaldırılmadı
- [ ] Yeni `@Published` property → UserDefaults'ta secret olmadığından emin ol

---

## Bağımlılıklar

| Bağımlılık | Kaynak | Neden |
|-----------|--------|-------|
| `libsqlite3` | macOS sistem | state.vscdb okuma (XcodeGen: `OTHER_LDFLAGS: -lsqlite3`) |
| `Security.framework` | macOS sistem | Keychain |
| `ServiceManagement.framework` | macOS sistem | Start at Login (SMAppService) |
| `UserNotifications.framework` | macOS sistem | Bildirimler |
| `Combine` | Apple stdlib | @Published + sink |
| XcodeGen | brew (dev) | .xcodeproj üretimi (CI + local) |

**Üçüncü taraf Swift paketi (SPM) yok** — kasıtlı, binary küçük kalır.
