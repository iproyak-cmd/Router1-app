# Next Session

## Primary Goal

Turn the Android demo into a client-ready Router1 App pilot.

## Start Here

1. Confirm APK exists:

```bash
ls -lh /root/router1_app_mvp/build-output/router1_app_mvp.apk
```

2. If missing, rebuild:

```bash
export PATH=/root/flutter/bin:$PATH
cd /root/router1_app_mvp
flutter analyze
flutter build apk --release
mkdir -p build-output
cp build/app/outputs/flutter-apk/app-release.apk build-output/router1_app_mvp.apk
```

3. Install on Android test device:

```bash
/root/android-sdk/platform-tools/adb install -r build-output/router1_app_mvp.apk
```

## Sprint 1 Verification

- Install the latest visual demo APK on Android.
- Compare the first-run route visually against `docs/design/01..08`.
- Confirm Splash auto-opens `Что хотите подключить?` after about 1.5 seconds.
- Confirm Splash is not clipped on the test device.
- Open APK on Android while connected to a Keenetic Wi-Fi network.
- Tap `Настроить роутер`.
- Confirm the search screen starts real discovery.
- Confirm found router data appears before compatibility.
- If not found, confirm fallback text appears:
  `Не удалось найти роутер. Проверьте, что телефон подключён к Wi-Fi роутера.`
- Test both buttons:
  - `Повторить поиск`
  - `Указать вручную`
- Confirm the payment screen contains `Router1 Keenetics`, `2300 ₽`, all modes and locations, priority support, first month fee, and `Оплатить`.
- Confirm Home looks like a commercial Router1 center screen, not an engineering dashboard.

## Product Work

- Check all 8 approved screens on a real Android device.
- Verify Demo Mode is visible without API.
- Verify local mode switching feels instant.
- Tune Russian copy for non-technical Keenetic users.
- Connect discovery result to the payment/setup backend when ready.

## Design Environment Work

- Owner should provide the Figma file URL and approved frame links.
- Owner should enable Figma Dev Mode for the Router1 design file.
- If MCP is used, configure local Figma MCP outside the repo and do not commit tokens.
- When a font is approved, put font files into `assets/fonts/` and add the concrete `fonts:` block to `pubspec.yaml`.
- When icon family is approved, add the Flutter package and replace temporary Material icons screen by screen.
- For the Router1 status sphere, prepare a Rive prototype before replacing the current Flutter-painted orb.

## API Work

- Pick final API domain.
- Configure nginx with `/api/v1` using `docs/API_EXPOSURE_PLAN.md`.
- Issue scoped app tokens from existing bot/account system.
- Connect app to HTTPS API endpoint.

## Do Not Do Yet

- Do not replace existing VPN infrastructure.
- Do not add billing to the app yet.
- Do not support non-Keenetic routers in MVP.
- Do not expose restart/logs to all users until token scopes are implemented.
