# ValAPP — Valorant Shop, Rank & Account Companion 🎯

[![Flutter](https://img.shields.io/badge/Flutter-3.3.0+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A high-performance, feature-packed, and beautifully designed Flutter mobile application (iOS & Android) for monitoring your Valorant account — Daily Shop, Featured Bundles, Night Market, Skin Catalog & Wishlist, Interactive Chromas & Video Inspector, Multi-Account Manager, Competitive Rank & 10-Game Net RR Trend, Match Scoreboards with MVP Badges, Battle Pass Carousel, Equipped Loadout Inspector, and Native Background Push Notifications — directly from your smartphone without opening the game client.

> **Disclaimer:** This application uses unofficial Valorant endpoints reverse-engineered by the community and metadata from `valorant-api.com`. It is intended strictly for personal use. Riot Games does not officially support or endorse this project.

---

## 🌟 Key Features

| Screen / Feature | Capabilities & Description |
|------------------|----------------------------|
| 🛒 **Daily Shop & Bundles** | 4 Daily Skin Offers with prices & reset countdown timer, **Featured Bundle Promo Banner**, **Night Market** (with real skin artwork & discount percentages), VP/RP/KC/Free Agent wallet balances header, News Feed, and **Wishlist Match Alert Banner**. |
| 👥 **Multi-Account Manager** | Instant account switching between main and alt Riot accounts (`AccountSwitcherModal`) with active account indicator (`AppColors.red`), region/shard indicators, account deletion, and seamless webview onboarding. |
| 🔍 **Skin Catalog & Wishlist** | Comprehensive skin catalog with live search bar, weapon category filters (`Vandal`, `Phantom`, `Melee`, `Operator`, `Sheriff`, `Ghost`, `Classic`, `Spectre`, `Outlaw`, etc.), and one-tap wishlist bookmarking. |
| 🎬 **Skin Inspector & Video VFX** | **Interactive Chromas & Level Inspector (`SkinDetailModal`)**: Live color swatch picker (Base, Variant 1, 2, 3) with artwork swap, Radianite level upgrade tiers, and **`▶ VIDEO`** button opening a dedicated MP4 player dialog (`SkinVideoDialog`) for watching level VFX & finisher animations. |
| 🏆 **Competitive Rank & RR Trend** | Official high-res rank tier badges from `valorant-api.com` (**Platinum 3**, Gold, Diamond, Radiant, etc.), animated RR progress bar (`0 – 100 RR`), sparkline chart, and **10-Game Net RR Trend Summary Card** (e.g. `+42 RR (6 W / 4 L)`). |
| ⚔️ **Match History & Scoreboards** | Recent match list with **Map Artwork Thumbnails**, queue filters (Competitive, Unrated, Spike Rush, Deathmatch), per-match scoreboard with batch player name resolution (`Name#TAG`), K/D/A, ACS, and **Gold `MATCH MVP` & Cyan `TEAM MVP` Badges**. |
| 📜 **Battle Pass & Missions** | Act progression, active daily & weekly missions tracker, and a full **Swipeable Battle Pass Carousel (`BattlepassCarouselModal`)** displaying level numbers, free items, and reward unlock statuses. |
| 🎒 **Equipped Loadout Inspector** | View your account's currently equipped weapon skins, gun buddies, player cards, titles, and sprays. |
| 🔔 **Background Push Alerts** | Periodic background worker (`Workmanager`) running every 3 hours to evaluate user-configured smart category rules (`Wishlist`, `Melee / Knives`, `Vandal`, `Phantom`, `Operator`, `Sheriff`) and fire native system push alerts on iOS & Android. |
| 👤 **Profile & Cache Control** | Account level, total XP, recent XP gain logs, clean cache invalidation, multi-account switcher trigger, and secure logout. |

---

## 🛠️ Core Technical Capabilities & Optimizations

- **🔒 Native WebView Login & Cloudflare Bypass:** Authentic Riot OAuth authentication via native `webview_flutter` handling Cloudflare Turnstile protection, multi-factor authentication (MFA/2FA), and Riot Mobile Authenticator (TOTP).
- **🔄 Silent Background Cookie Re-auth (`SilentWebviewReauth`):** Off-screen background WebView cookie re-auth using persistent `ssid` session cookies. Refreshes expired tokens silently without interrupting user flow.
- **⚡ Proactive Token & Interceptor Refresh:** `ValorantInterceptor` monitors token TTL and proactive refresh window (<5 minutes remaining), auto-refreshing entitlement and access tokens before expiration.
- **🚀 Rolling Cache Memory Optimization:** `MatchDetailLocalCache` employs a rolling eviction strategy (capped at 30 recent matches) to prevent unbounded local storage growth and main-thread lag.
- **⏱️ Rate Limit Compliance (`RateLimitInterceptor`):** Enforces a minimum 500ms request spacing across API calls to prevent Riot rate limits (HTTP 429).
- **🎨 Unified Valorant Theme Token System (`AppColors`):** Single source of truth for Valorant signature red (`#FF4655`), dark slate card surfaces (`#0D1117`, `#111823`), and semantic match outcome colors.
- **🔄 Auto-Updated Client Version:** Automated 24h version synchronization with `valorant-api.com/v1/version` and updated fallback string (`release-13.02-shipping-7-5092570`).

---

## 🛠️ Tech Stack

| Component | Technology / Package |
|-----------|----------------------|
| **Framework** | [Flutter](https://flutter.dev) (Dart 3+) — Cross-platform iOS & Android |
| **State Management** | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) (2.6+) |
| **Navigation & Routing** | [go_router](https://pub.dev/packages/go_router) (13.2+) |
| **HTTP Network Client** | [dio](https://pub.dev/packages/dio) + `dio_cookie_manager` + `cookie_jar` |
| **Authentication** | [webview_flutter](https://pub.dev/packages/webview_flutter) + native `ssid` cookie persistence |
| **Security & Storage** | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) (Android Keystore / iOS Keychain) |
| **Background Service** | [workmanager](https://pub.dev/packages/workmanager) (Periodic background worker tasks) |
| **Notifications** | [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) (Native push alerts) |
| **Video Player** | [video_player](https://pub.dev/packages/video_player) (Streamed MP4 level VFX & finisher videos) |
| **Local Cache** | [shared_preferences](https://pub.dev/packages/shared_preferences) |
| **Image Caching** | [cached_network_image](https://pub.dev/packages/cached_network_image) |
| **Asset Metadata** | [valorant-api.com](https://valorant-api.com) API (Skins, Chromas, Levels, Rank Badges, Maps & Bundles) |

---

## 📁 Project Architecture

```
lib/
├── main.dart
├── app.dart                          # Router configuration, MaterialApp theme & bottom navigation dock
├── core/
│   ├── di/providers.dart             # Riverpod dependency injection & singletons
│   ├── network/                      # auth_dio, api_dio, rate_limit_interceptor & valorant_interceptor
│   ├── services/                     # BackgroundService (Workmanager) & NotificationService (push alerts)
│   ├── storage/                      # SecureStorage (credentials) & CacheStorage (JSON/SharedPreferences)
│   └── exceptions/                   # AuthException & ApiException
├── shared/
│   ├── utils/                        # ValorantAssets (valorant-api.com fetcher & cache), AppColors, TierColors, VersionService
│   └── widgets/                      # SkinCard, RankBadge, CountdownTimer, LoadingShimmer
└── features/
    ├── auth/                         # WebView login, AccountSwitcherModal, SilentWebviewReauth & token extraction
    ├── shop/                         # ShopScreen, WishlistCatalogScreen, SkinDetailModal, SkinVideoDialog, NotificationRuleService
    ├── match/                        # MatchHistoryScreen, MatchDetailScreen, MatchLocalCache & scoreboard models
    ├── rank/                         # RankScreen, MMR remote source, net RR trend & sparkline painter
    ├── contracts/                    # ContractsScreen, BattlepassCarouselModal & mission models
    ├── loadout/                      # LoadoutScreen & equipped gear models
    ├── news/                         # NewsRemoteSource & news model
    └── profile/                      # ProfileScreen, AccountLocalCache & display name batch resolver
```

---

## 🔐 Authentication & Data Security

- **WebView OAuth Login:** Authentication is handled natively through an embedded WebView (`webview_flutter`) to support Riot's Cloudflare Turnstile protection, multi-factor authentication (MFA/2FA), and Riot Mobile Authenticator.
- **Local Credentials Storage:** All credentials, OAuth access tokens, entitlement tokens, and session cookies are stored strictly on the user's device using `flutter_secure_storage` (Android Keystore / iOS Keychain).
- **Privacy:** No user credentials, tokens, or personal data are ever sent to any intermediate or third-party servers — all API requests communicate directly with official Riot Games servers (`pd.pas.si.riotgames.com`, `pvp.net`).

---

## 🚀 Build & Local Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (>= 3.3.0)
- Android Studio / Xcode for device deployment

### Installation
```bash
# 1. Clone the repository
git clone https://github.com/Irsyadmr354/Valapp.git
cd Valapp

# 2. Install dependencies
flutter pub get

# 3. Run static code analysis
flutter analyze

# 4. Launch on connected device or emulator
flutter run

# 5. Build release APK (Android)
flutter build apk --release

# 6. Build unsigned release IPA (iOS)
flutter build ipa --no-codesign
```

---

## 📚 API References

- **Riot Remote API:** [Unofficial Valorant API Docs](https://valapidocs.techchrism.me/)
- **Valorant Assets API:** [valorant-api.com](https://valorant-api.com) (Skin Icons, Chromas, Levels, Rank Badges, Map Artwork & Bundles)

---

## 📄 License

This project is open-source and available under the [MIT License](LICENSE).
