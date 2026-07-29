# Valorant Shop Monitor

Personal Flutter app (iOS & Android) to monitor your Valorant account — daily shop, rank, match history, battlepass progress, and account stats — directly from your phone without needing a PC running the game.

> **Disclaimer:** This app uses the unofficial Valorant API reverse-engineered by the community. It is for personal use only. Riot Games does not officially support or endorse this. Endpoint stability is not guaranteed.

---

## Features

| Tab | What you get |
|-----|-------------|
| **Shop** | 4 daily skin offers with prices, countdown timer, featured bundle, night market (when active), VP/RP/KC wallet balance |
| **Rank** | Current competitive tier, RR, recent match RR history |
| **Matches** | Last 20 matches with queue filter, per-match scoreboard |
| **Progress** | Battlepass level + XP bar, active missions with progress |
| **Profile** | Account level, XP history, logout |

**Additional:**
- Cookie-based silent token refresh — stays logged in for ~3 weeks without re-entering credentials
- Wishlist skins — get highlighted when they appear in your daily shop
- Cache-first strategy — shows last cached data instantly, refreshes in background
- Supports both **email 2FA** and **Authenticator App (TOTP)**

---

## Tech Stack

| Layer | Library |
|-------|---------|
| Framework | Flutter (Dart) — stable channel |
| HTTP | `dio` + `dio_cookie_manager` |
| Cookie persistence | `cookie_jar` (PersistCookieJar) |
| Secure storage | `flutter_secure_storage` |
| State management | `flutter_riverpod` |
| Navigation | `go_router` |
| Cache | `shared_preferences` + `hive_flutter` |
| Image cache | `cached_network_image` |

---

## Project Structure

```
lib/
├── main.dart
├── app.dart                          # Router, theme, bottom nav shell
├── core/
│   ├── di/providers.dart             # Riverpod dependency injection
│   ├── network/                      # auth_dio, api_dio, interceptors
│   ├── storage/                      # SecureStorage, CacheStorage
│   └── exceptions/                   # AuthException, ApiException
└── features/
    ├── auth/                         # RSO login, 2FA, cookie reauth
    ├── shop/                         # Daily shop, wallet, bundle, night market
    ├── match/                        # Match history + detail
    ├── rank/                         # MMR, rank tier, RR history
    ├── contracts/                    # Battlepass, missions
    └── profile/                      # Account XP, display name
```

---

## Authentication Flow

Uses Riot's RSO OAuth headless flow (no browser redirect):

1. `POST /api/v1/authorization` — init cookie session
2. `PUT /api/v1/authorization` — submit username + password
3. `PUT /api/v1/authorization` — submit 2FA code (email or TOTP)
4. `POST entitlements.auth.riotgames.com` — get entitlement token
5. `PUT riot-geo.pas.si.riotgames.com` — get region + shard
6. Decode JWT `sub` field — extract PUUID

Silent reauth on every app open via cookie jar (valid ~3 weeks).

---

## Build & Run

### Preview in browser (Chrome)
```bash
flutter run -d chrome
```

### Android APK
Requires Android Studio + Android SDK:
```bash
flutter build apk --release
```

### iOS IPA
iOS builds require macOS + Xcode. From Windows, use **Codemagic CI**:

1. Push to GitHub
2. Connect repo at [codemagic.io](https://codemagic.io)
3. Build with the included `codemagic.yaml`
4. Download the unsigned `.ipa` from Artifacts
5. Sideload with [Sideloadly](https://sideloadly.io) using a free Apple ID

> Unsigned IPA signed with a free Apple ID expires every **7 days** and needs re-signing.

---

## Local Development Setup

```bash
# Clone
git clone https://github.com/Irsyadmr354/Valapp.git
cd Valapp

# Install dependencies
flutter pub get

# Run on Chrome
flutter run -d chrome

# Run on connected Android device
flutter run -d android
```

---

## API References

All endpoints are from the [unofficial Valorant API docs](https://valapidocs.techchrism.me/) — Remote API only (no Local/Lockfile dependency).

Asset metadata (skin names, icons, rank icons) from [valorant-api.com](https://valorant-api.com) — no auth required, cached locally for 24 hours.

---

## Security Notes

- Credentials are stored using `flutter_secure_storage` (Android Keystore / iOS Keychain)
- Cookies are persisted to the app's private documents directory
- Nothing is ever sent to third-party servers — all requests go directly to Riot's servers
- Never logs or prints any credential values
