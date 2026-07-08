# Router1 App Project State

Date: 2026-06-28 UTC

## Current Status

Router1 App MVP exists at:

```text
/root/router1_app_mvp
```

The app has:

- First Run Experience:
  - Splash with automatic transition after startup.
  - Choice between router and gadget.
  - Router search with real local network discovery.
  - Router found state with real discovery data when available.
  - Compatibility check.
  - Benefits.
  - Payment.
  - Home.
  - Gadget platform flow.
- Commercial Home screen matching the approved dark Router1 visual direction.
- Explicit Demo Mode.
- Local mode switching when API is unavailable.
- Product modes:
  - Обычный
  - Игровой
  - Нейросети
  - Стриминг
  - Приватность
  - Свои домены
- Device list screen.
- Support screen:
  - Проверить подключение
  - Отправить диагностику
  - Написать в поддержку
  - Обновить подключение
- Settings screen.

## Sprint UI State

Approved design PNGs live in:

```text
/root/router1_app_mvp/docs/design
```

The 8 approved user screens were transferred into Flutter widgets, not inserted as static PNGs:

- Splash.
- First Run.
- Router search.
- Router found.
- Compatibility.
- Benefits.
- Payment.
- Home.

Reusable UI primitives added in `lib/main.dart`:

- `Router1Theme`
- `PrimaryButton`
- `Router1Card`
- `StatusOrb`
- `SetupHeader`

The router first-run path now leads from payment directly to Home, matching the approved 8-screen demo sequence.

Splash behavior was corrected after Android device testing:

- Splash is no longer an action screen.
- It automatically opens First Run after about 1.5 seconds.
- Layout is height-adaptive and scroll-safe to avoid bottom clipping on smaller Android screens.

## Design Environment

Prepared:

- Flutter asset directories:
  - `assets/images/`
  - `assets/illustrations/`
  - `assets/icons/`
  - `assets/animations/`
  - `assets/fonts/`
- App-ready asset directories registered in `pubspec.yaml`.
- Design workflow documentation:
  - `docs/design/UI_GUIDE.md`
  - `docs/design/DESIGN_WORKFLOW.md`
  - `docs/design/mcp/README.md`
- Reserved design tooling directory:
  - `tool/design/`

Recommendations recorded:

- Figma Dev Mode should be the primary handoff surface.
- Figma MCP should be connected after the owner provides Figma access/file URL and, if needed, a token.
- Phosphor is the recommended icon family.
- Rive is recommended for the live Router1 status sphere.
- Lottie is suitable for lightweight onboarding/payment animations.
- Manrope is the recommended production font candidate.

## Keenetic Discovery

Implemented:

- Service: `lib/services/keenetic_discovery.dart`
- Model: `lib/models/keenetic_router.dart`
- Checks gateway candidates from local IPv4 interfaces.
- Checks `192.168.1.1`.
- Checks `my.keenetic.net`.
- Uses short timeouts and fallback.
- Returns model, IP, firmware when available, Wi-Fi name when available, and compatibility status.
- If not found, the first-run search screen shows manual fallback:
  - Повторить поиск
  - Указать вручную

## API State

Router1 API on EU-1 was expanded to product modes:

- `normal`
- `game`
- `ai`
- `streaming`
- `privacy`
- `domains`

API remains local-only on the node until nginx/TLS exposure is configured.

## Android State

Installed:

- Flutter 3.44.4 stable at `/root/flutter`
- Android SDK at `/root/android-sdk`
- Android platform 36
- Android build-tools 36.0.0
- OpenJDK 17

Generated Android platform files under:

```text
/root/router1_app_mvp/android
```

Project backup before Android generation:

```text
/root/router1_app_mvp_backup_20260628_070140
```

## Verification

Completed:

```bash
flutter analyze
```

Result:

```text
No issues found
```

Design environment validation:

```bash
flutter pub get
flutter analyze
```

Result:

```text
No issues found
```

APK build completed successfully with:

```bash
flutter build apk --release
```

Final APK:

```text
/root/router1_app_mvp/build-output/router1_app_mvp.apk
```

Size:

```text
44M
```

SHA256:

```text
6a4eb44ef9f93e120ce104689d80bbc0c52f7d0eef8a45819aa19f75b18b1580
```
