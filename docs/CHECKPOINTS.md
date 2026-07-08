# Router1 App Checkpoints

## MVP Checkpoint 1 - Android Demo

Success criteria:

- APK exists in `build-output/router1_app_mvp.apk`.
- App starts on Android.
- Demo Mode appears when API is unavailable.
- Dashboard looks like a commercial product.
- Modes switch locally.
- Support screen explains useful actions without developer commentary.

Status:

- UI implemented.
- Demo Mode implemented.
- Android toolchain installed.
- APK built successfully:
  `/root/router1_app_mvp/build-output/router1_app_mvp.apk`

## MVP Checkpoint 1.5 - First Run Experience

Success criteria:

- New user sees Splash: Router1, Умный интернет.
- User chooses router or gadget.
- Router path leads through search, compatibility, benefits, payment, setup, success.
- Gadget path leads through platform, payment, instruction, success.
- Screens avoid protocol language and focus on value.
- Flow can be clicked end to end without live backend.
- Splash is automatic and requires no user action.

Status:

- Implemented in `lib/main.dart`.
- User-facing code checked for forbidden terms.
- APK rebuilt with the flow.
- Splash auto-transition and adaptive height were fixed after real Android testing.

## Sprint 1 Task 1 - Keenetic Discovery

Success criteria:

- App keeps the approved first-run screens.
- Selecting router starts real local network discovery.
- Discovery checks gateway candidates, `192.168.1.1`, and `my.keenetic.net`.
- If found, the app shows model, IP, firmware when available, Wi-Fi name when available, and readiness.
- If not found, the app shows a manual fallback with retry.
- Release APK is rebuilt.

Status:

- Implemented in `lib/services/keenetic_discovery.dart`.
- Model added in `lib/models/keenetic_router.dart`.
- Search screen connected to discovery.
- `flutter analyze` passes.
- APK rebuilt at `/root/router1_app_mvp/build-output/router1_app_mvp.apk`.

## Sprint UI Task 1 - Approved 8 Screens

Success criteria:

- Flutter UI follows the approved PNGs in `docs/design/`.
- PNGs are not embedded as static screens.
- Router path keeps the approved sequence:
  Splash, First Run, Search, Found, Compatibility, Benefits, Payment, Home.
- Keenetic Discovery logic is preserved.
- Payment screen shows `Router1 для роутера`, `2300 ₽`, first month included,
  monthly fee `300 ₽/мес`, and `Оплатить`.
- Release APK is rebuilt and SHA256 is refreshed.

Status:

- Implemented in `lib/main.dart`.
- Reusable visual components added: `Router1Theme`, `PrimaryButton`, `Router1Card`, `StatusOrb`, `SetupHeader`.
- Home screen rebuilt to match `08. Home.png` direction.
- `flutter analyze` passes.
- APK rebuilt at `/root/router1_app_mvp/build-output/router1_app_mvp.apk`.
- SHA256: `6a4eb44ef9f93e120ce104689d80bbc0c52f7d0eef8a45819aa19f75b18b1580`.

## Sprint UI Task 2 - Design Environment

Success criteria:

- Project has a clean asset structure for images, illustrations, icons, animations and fonts.
- Flutter knows about app-ready asset directories.
- Design workflow is documented.
- UI tokens and recommendations are recorded.
- Figma Dev Mode and MCP setup path is documented.
- No app screens or business logic are changed.

Status:

- Implemented.
- Added `docs/design/UI_GUIDE.md`.
- Added `docs/design/DESIGN_WORKFLOW.md`.
- Added `docs/design/mcp/README.md`.
- Added `tool/design/README.md`.
- Added asset folders under `assets/`.
- `flutter pub get` passes.
- `flutter analyze` passes.

## MVP Checkpoint 2 - Secure API

Success criteria:

- API is available only through HTTPS `/api/v1`.
- Local API still binds to `127.0.0.1`.
- Bearer token required.
- Nginx rate limit enabled.
- Only required methods are allowed.
- Request logs are separate.

Status:

- Plan exists in `docs/API_EXPOSURE_PLAN.md`.
- Domain and TLS are pending.

## MVP Checkpoint 3 - Real Keenetic Pilot

Success criteria:

- One existing Keenetic client can install the APK.
- App shows real Router1 API status.
- App can switch at least one mode through the API.
- Support action can send useful diagnostics.

Status:

- Pending API exposure and token issuing.

## MVP Checkpoint 4 - Commercial Demo

Success criteria:

- Founder can show APK to a client without explaining technical internals.
- Client understands that Router1 manages home internet, not just VPN.
- App copy focuses on YouTube, Telegram, AI, games, privacy, and support.

Status:

- Current UI is ready for Android visual review against the approved PNGs.
