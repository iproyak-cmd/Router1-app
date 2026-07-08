# Router1 App Bootstrap

## Product Direction

Router1 App is the main MVP product.

Router1 does not sell a protocol. Router1 sells convenient control of home
internet for Keenetic users.

Do not create new VPN infrastructure unless explicitly required. Use the existing
Router1 WireGuard/Xray/OpenClaw infrastructure and expose it through Router1 API.

## Repository

```bash
cd /root/router1_app_mvp
```

Important files:

- `lib/main.dart` - Flutter UI.
- `lib/router1_api.dart` - API client and app data model.
- `README.md` - build and demo instructions.
- `docs/API_EXPOSURE_PLAN.md` - secure public API plan.

## Toolchain

Installed locally on this host:

- Flutter: `/root/flutter`
- Android SDK: `/root/android-sdk`
- Java: OpenJDK 17

Use:

```bash
export PATH=/root/flutter/bin:$PATH
flutter doctor -v
```

## Build

```bash
cd /root/router1_app_mvp
flutter pub get
flutter analyze
flutter build apk --release
mkdir -p build-output
cp build/app/outputs/flutter-apk/app-release.apk build-output/router1_app_mvp.apk
```

## API

Local development default:

```text
http://127.0.0.1:8081
```

Production target:

```text
https://api.router1.tech/api/v1
```

Router1 API must stay transport-agnostic. App code must not know whether the
backend uses WireGuard, sing-box, Xray, or another transport.
