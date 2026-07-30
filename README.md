# ValAPP — Valorant Shop & Account Monitor 🎯

A personal, high-performance, and feature-packed Flutter mobile application (iOS & Android) to monitor your Valorant account — Daily Shop, Featured Bundles, Night Market, Skin Catalog & Wishlist, Interactive Chromas & Video Inspector, Competitive Rank & 10-Game RR Trend, Match History with MVP Badges, Act Progress, and Native Smartphone Notifications — directly from your phone without needing a PC running the game.

> **Disclaimer:** This application uses the unofficial Valorant API reverse-engineered by the community and metadata from `valorant-api.com`. It is intended strictly for personal use. Riot Games does not officially support or endorse this project.

---

## 🌟 Key Features

| Tab | Features & Capabilities |
|-----|-------------------------|
| **Shop** | 4 Daily Skin Offers with prices, reset countdown timer, **Featured Bundle Promo Banner**, **Night Market** (with real skin artwork & discount badges), VP/RP/KC wallet balance header, and **Wishlist Match Alert Banner**. |
| **Catalog & Wishlist** | Dedicated **Skin Catalog Screen** with live search bar, weapon category filters (`Vandal`, `Phantom`, `Melee`, `Operator`, `Sheriff`, `Ghost`, `Classic`, `Spectre`, `Outlaw`, etc.), and one-tap wishlist bookmarking. |
| **Skin Inspector** | **Interactive Skin Chromas & Level Modal (`SkinDetailModal`)**: Real-time color swatch picker (Base, Variant 1, 2, 3) with instant artwork swap, level upgrade tiers (Level 1-4 with Radianite Points costs), and **`▶ VIDEO`** button opening a dedicated MP4 player (`SkinVideoDialog`) for watching level VFX & finisher animations! |
| **Rank** | Official high-res Competitive Tier Badges from `valorant-api.com` (**Platinum 3**, Gold, Diamond, Radiant, etc.), animated RR progress bar (`0 - 100 RR`), and **10-Games Net RR Trend Summary Card** (`+42 RR (6 W / 4 L)`). |
| **Matches** | Last 15 matches with **Map Artwork Thumbnails**, queue filters (Competitive, Unrated, Spike Rush, Deathmatch), per-match scoreboard with batch player name resolution (`Name#TAG`), K/D/A, ACS, and **Gold `MATCH MVP` & Cyan `TEAM MVP` Badges**. |
| **Progress** | Battlepass level & XP progress bar, active daily & weekly missions with progress tracking. |
| **Profile** | Account level, total XP, recent XP gain logs, clean cache invalidation, and secure logout. |

---

## 🛠️ Core Capabilities & Enhancements

- **🔒 WebView Authentication & Cloudflare Bypass:** Seamless Riot login via native WebView (`webview_flutter`), supporting 2FA email codes and Riot Mobile Authenticator (TOTP).
- **🔄 Permanent Background Silent Reauth (`SilentWebviewReauth`):** Off-screen background WebView cookie reauth utilizing persistent `ssid` cookies. Automatically refreshes expired tokens in <1 second without screen popups or logging out.
- **⚡ Proactive Token Refresh:** `ValorantInterceptor` automatically checks token lifetime and triggers background reauth before token expiry (<5m remaining).
- **🔔 Native Smartphone Push Notifications (`NotificationService`):** System notifications on iOS & Android whenever a wishlisted skin appears in your daily shop.
- **🎨 Interactive Chromas & Level VFX Player:** Tap any skin card to preview all color variants (Chromas) with instant artwork swapping, and watch streamed MP4 videos of level upgrades & finisher animations.
- **🛍️ Complete Weapon Skin Catalog:** Easily browse, search, and bookmark any Valorant skin by weapon type to track shop availability.

---

## 🛠️ Tech Stack

| Layer | Technology / Library |
|-------|----------------------|
| **Framework** | Flutter (Dart) — Cross-platform iOS & Android |
| **HTTP Client** | `dio` + `dio_cookie_manager` + `cookie_jar` (PersistCookieJar) |
| **Authentication** | `webview_flutter` + native cookie store (`ssid` session persistence) |
| **Security** | `flutter_secure_storage` (Android Keystore / iOS Keychain) |
| **Notifications** | `flutter_local_notifications` (Native iOS & Android system push alerts) |
| **Video Streaming** | `video_player` (MP4 level VFX & finisher video streaming) |
| **State Management** | `flutter_riverpod` |
| **Navigation** | `go_router` |
| **Storage & Cache** | `shared_preferences` (Cache-first offline strategy) |
| **Image Loading** | `cached_network_image` with disk caching |
| **Asset Metadata** | [valorant-api.com](https://valorant-api.com) API (Skins, Chromas, Levels, Rank Badges, Map Artwork & Bundles) |

---

## 📁 Project Architecture

```
lib/
├── main.dart
├── app.dart                          # App router, theme system & bottom navigation dock
├── core/
│   ├── di/providers.dart             # Riverpod dependency injection & providers
│   ├── network/                      # auth_dio, api_dio, valorant_interceptor
│   ├── services/                     # NotificationService (native smartphone push alerts)
│   ├── storage/                      # SecureStorage & CacheStorage
│   └── exceptions/                   # AuthException & ApiException
├── shared/
│   ├── utils/                        # ValorantAssets (valorant-api.com fetcher & cache), TierColors, VersionService
│   └── widgets/                      # SkinCard, CountdownTimer, LoadingShimmer
└── features/
    ├── auth/                         # WebView authentication, SilentWebviewReauth & token extraction
    ├── shop/                         # Daily storefront, WishlistCatalogScreen, SkinDetailModal, SkinVideoPlayer, wallet & bundle
    ├── match/                        # Match history list with map thumbnails, MVP badges & detailed scoreboards
    ├── rank/                         # MMR, official rank tier badges, RR progress bar & 10-Game Net RR Trend
    ├── contracts/                    # Battlepass progress & active mission trackers
    └── profile/                      # Account level, XP history & display name batch resolver
```

---

## 🔐 Authentication & Security

- **WebView Login:** Riot utilizes Cloudflare Turnstile protection on auth endpoints. Authentication is handled natively via WebView (`webview_flutter`), allowing user-friendly login and 2FA input while extracting required OAuth tokens (`access_token`, `id_token`, `sub`/PUUID) and persistent session cookies (`ssid`, `tdid`).
- **Data Privacy:** All credentials and tokens are stored exclusively on your device via `flutter_secure_storage`. No credentials, tokens, or personal data are ever transmitted to any third-party server — all requests go directly to Riot Games endpoints (`pd.pas.si.riotgames.com`, `pvp.net`).

---

## 🚀 Build & Local Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (>= 3.3.0)
- Android Studio / Xcode for device deployment

### Installation
```bash
# Clone the repository
git clone https://github.com/Irsyadmr354/Valapp.git
cd Valapp/valorant_shop_monitor

# Install dependencies
flutter pub get

# Run on connected device / emulator
flutter run

# Build release APK (Android)
flutter build apk --release

# Build unsigned release IPA (iOS via Codemagic / Mac)
flutter build ipa --no-codesign
```

---

## 📚 API References

- **Riot Remote API:** [Unofficial Valorant API Docs](https://valapidocs.techchrism.me/)
- **Valorant Assets API:** [valorant-api.com](https://valorant-api.com) (Skin Icons, Chromas, Levels, Rank Badges, Map Artwork & Bundles)
