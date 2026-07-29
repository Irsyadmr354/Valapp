# Valorant Shop Monitor 🎯

A personal, high-performance Flutter mobile application (iOS & Android) to monitor your Valorant account — Daily Shop, Featured Bundles, Night Market, Competitive Rank, Match History with Map Artwork, Act Progress, and Account Stats — directly from your phone without needing a PC running the game.

> **Disclaimer:** This application uses the unofficial Valorant API reverse-engineered by the community and metadata from `valorant-api.com`. It is intended strictly for personal use. Riot Games does not officially support or endorse this project.

---

## 🌟 Key Features

| Tab | Features & Capabilities |
|-----|-------------------------|
| **Shop** | 4 Daily Skin Offers with prices, reset countdown timer, **Featured Bundle Hero Artwork Banner**, **Night Market** (when active with real skin images & fixed discount badges), VP/RP/KC wallet balance header, and wishlist bookmarks |
| **Rank** | Official high-res Competitive Tier Badge icons from `valorant-api.com` (**Platinum 3**, Gold, Diamond, etc.), animated RR progress bar (`0 - 100 RR`), and recent competitive match RR deltas |
| **Matches** | Last 20 matches with **Map Artwork Thumbnails**, queue filters (Competitive, Unrated, Spike Rush, Deathmatch), and full per-match scoreboard with batch player name resolution (`Name#TAG`), K/D/A, and ACS |
| **Progress** | Battlepass level & XP progress bar, active daily & weekly missions with progress tracking |
| **Profile** | Account level, total XP, recent XP gain logs, and secure logout |

### 🛠️ Core Capabilities
- **Reliable WebView Login & Cloudflare Turnstile Bypass:** Seamless Riot authentication using `flutter_inappwebview`, supporting email 2FA and Riot Mobile Authenticator (TOTP).
- **Silent Cookie Token Refresh:** Stay logged in for ~3 weeks without re-entering credentials.
- **Cache-First Offline Strategy:** Instantly loads previously cached data while silently fetching fresh updates in the background.
- **Wishlist Skin Monitor:** Bookmark desired skins; get visual highlights when they appear in your daily shop.

---

## 🛠️ Tech Stack

| Layer | Technology / Library |
|-------|----------------------|
| **Framework** | Flutter (Dart) — Cross-platform iOS & Android |
| **HTTP Client** | `dio` + `dio_cookie_manager` with custom JSON response interceptor |
| **Authentication** | `flutter_inappwebview` + `cookie_jar` (PersistCookieJar) |
| **Security** | `flutter_secure_storage` (Android Keystore / iOS Keychain) |
| **State Management** | `flutter_riverpod` |
| **Navigation** | `go_router` |
| **Storage & Cache** | `shared_preferences` + `hive_flutter` |
| **Image Loading** | `cached_network_image` with local disk caching |
| **Asset Metadata** | [valorant-api.com](https://valorant-api.com) API (skin icons, rank icons, map artwork, bundle promos) |

---

## 📁 Project Architecture

```
lib/
├── main.dart
├── app.dart                          # App router, theme system & bottom navigation dock
├── core/
│   ├── di/providers.dart             # Riverpod dependency injection & providers
│   ├── network/                      # auth_dio, api_dio, json_response_interceptor
│   ├── storage/                      # SecureStorage & CacheStorage
│   └── exceptions/                   # AuthException & ApiException
└── features/
    ├── auth/                         # WebView authentication, cookie reauth & token extraction
    ├── shop/                         # Daily storefront, wallet, featured bundle & night market
    ├── match/                        # Match history list with map thumbnails & detailed match scoreboards
    ├── rank/                         # MMR, official rank tier badges, RR progress bar & update history
    ├── contracts/                    # Battlepass progress & active mission trackers
    └── profile/                      # Account level, XP history & display name batch resolver
```

---

## 🔐 Authentication & Security

- **WebView Login:** Riot utilizes Cloudflare Turnstile protection on their auth endpoints. Authentication is handled natively via WebView (`flutter_inappwebview`), allowing user-friendly login and 2FA input while extracting required OAuth tokens (`access_token`, `entitlements_token`, `sub`/PUUID) and persistent session cookies (`ssid`, `tdid`).
- **Data Privacy:** All credentials and tokens are stored exclusively on your device via `flutter_secure_storage`. No credentials, tokens, or personal data are ever transmitted to any third-party server — all requests go directly to Riot Games endpoints (`pd.pas.si.riotgames.com`, `pvp.net`).

---

## 🚀 Build & Local Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (latest stable release)
- Android Studio / Xcode for device deployment

### Installation
```bash
# Clone the repository
git clone https://github.com/Irsyadmr354/Valapp.git
cd Valapp/valorant_shop_monitor

# Install dependencies
flutter pub get

# Run on connected Android device / emulator
flutter run -d android

# Build release APK
flutter build apk --release
```

---

## 📚 API References

- **Riot Remote API:** [Unofficial Valorant API Docs](https://valapidocs.techchrism.me/)
- **Valorant Assets API:** [valorant-api.com](https://valorant-api.com) (Skin Icons, Tiers, Rank Badges, Map Artwork & Bundles)

