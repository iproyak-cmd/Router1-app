# Router1 App MVP

Flutter MVP for Keenetic customers.

The app is the product layer. It must not depend on WireGuard, Xray, or sing-box
details directly. Those details belong behind Router1 API.

## APK

Target output:

```bash
/root/router1_app_mvp/build-output/router1_app_mvp.apk
```

Build again:

```bash
export PATH=/root/flutter/bin:$PATH
cd /root/router1_app_mvp
flutter pub get
flutter analyze
flutter build apk --release
mkdir -p build-output
cp build/app/outputs/flutter-apk/app-release.apk build-output/router1_app_mvp.apk
```

Installed toolchain on this host:

- Flutter SDK: `/root/flutter`
- Android SDK: `/root/android-sdk`
- Java: OpenJDK 17

## Current screens

- Dashboard: connection, server, mode, speed, ping, traffic, events.
- Modes: normal, game, AI, streaming, privacy, domains.
- Devices: Keenetic network devices.
- Support: diagnostics, logs, restart.
- Settings: router connection, server selection, updates.

## API

Update `lib/main.dart` before a real build:

```dart
Router1Api(
  baseUrl: 'https://api.router1.tech/api/v1',
  token: 'issued-user-token',
)
```

During development the app has demo fallback data, so the first UI can be shown
before the mobile API gateway is exposed publicly.

If API is unavailable, the app shows Demo Mode and keeps local mode switching
working for a commercial demo.

## Next integration steps

1. Add secure public Router1 API gateway with TLS. See `docs/API_EXPOSURE_PLAN.md`.
2. Add user/device token issuing from the existing bot or account system.
3. Add Keenetic local connector for device list, ping, logs, and diagnostics.
4. Replace demo speed/ping with API metrics.
5. Sign release builds with Router1 production keystore.
