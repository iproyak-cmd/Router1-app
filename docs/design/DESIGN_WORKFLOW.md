# Router1 Design Workflow

Date: 2026-06-28 UTC

Goal: make future Router1 UI work fast, repeatable and close to approved designs without changing business logic by accident.

## Current State

The app lives in:

```text
/root/router1_app_mvp
```

Approved visual references live in:

```text
/root/router1_app_mvp/docs/design/
```

Flutter asset structure is prepared:

```text
assets/
  images/
  illustrations/
  icons/
  animations/
  fonts/
```

These folders are registered in `pubspec.yaml`.

## Ideal Figma Setup

Owner actions required:

1. Create or use a Figma Team for Router1.
2. Put all approved screens in one file: `Router1 App`.
3. Create pages:
   - `00 Cover`
   - `01 Foundations`
   - `02 Components`
   - `03 First Run`
   - `04 Home`
   - `05 Prototype`
   - `99 Archive`
4. Enable Dev Mode for the file/team.
5. Invite Codex operator/developer account with view/dev access.
6. Create a Figma personal access token only if REST API access is needed.

Recommended Figma component structure:

- `Color/Brand/Green`
- `Color/Background/App`
- `Text/Title/Large`
- `Button/Primary`
- `Card/Glass`
- `IconButton/Glass`
- `Status/Orb`
- `Plan/Router1Keenetics`

## Figma Dev Mode Workflow

1. Designer marks screens as ready.
2. Developer opens the exact frame in Dev Mode.
3. Extract:
   - frame size;
   - spacing;
   - typography;
   - colors;
   - radii;
   - shadows/glow;
   - assets;
   - component names.
4. Update `UI_GUIDE.md` if a token changed.
5. Export only required image assets into the correct `assets/` folder.
6. Implement Flutter components, not static screen images.
7. Build APK and compare screenshots against the Figma/PNG reference.

## Figma MCP Workflow

Figma MCP should be used when Codex needs structured design data:

- node sizes;
- colors;
- text styles;
- component hierarchy;
- Auto Layout;
- asset references.

Recommended setup options:

### Option A: Figma Dev Mode MCP Server

Use this when working locally with the Figma desktop app and Dev Mode.

Owner/developer requirements:

- Figma account with Dev Mode access.
- Figma desktop app.
- Dev Mode MCP server enabled in Figma settings.
- MCP client configured in Codex or the local IDE.

### Option B: Figma REST API

Use this when MCP is unavailable or automation is needed in CI.

Requirements:

- Figma personal access token.
- Figma file key.
- Node IDs for approved frames.

Useful API targets:

- file document;
- selected nodes;
- styles;
- components;
- image exports.

## Codex MCP Configuration Template

Do not commit real tokens.

Create a local MCP config using the active Codex/MCP format and point it to the Figma MCP server. Store secrets outside the repo.

Template:

```json
{
  "mcpServers": {
    "figma": {
      "command": "npx",
      "args": ["-y", "figma-developer-mcp", "--stdio"],
      "env": {
        "FIGMA_ACCESS_TOKEN": "set-outside-repo"
      }
    }
  }
}
```

If using the official Figma Dev Mode MCP server, configure the MCP client to connect to the local server endpoint exposed by Figma Desktop/Dev Mode instead of using a token-based community server.

## Asset Pipeline

Naming:

- Lowercase.
- Use underscores.
- Include purpose, not screen number.

Examples:

```text
assets/illustrations/router_keenetic_dark.webp
assets/icons/router1_mark.svg
assets/animations/status_orb.riv
assets/images/payment_plan_bg.webp
```

Formats:

- WebP: preferred for raster UI illustrations and backgrounds.
- PNG: only when transparency fidelity is needed or source export requires it.
- SVG: simple icons and logos.
- Rive: interactive state animations.
- Lottie JSON: lightweight sequence animations.

Size rules:

- Keep single raster assets under 500 KB when possible.
- Export at 2x or 3x only when needed.
- Prefer WebP for APK size.
- Keep original design exports in `docs/design/exports/` only if needed; app-ready files go in `assets/`.

Flutter use:

```dart
Image.asset('assets/illustrations/router_keenetic_dark.webp')
```

For SVG, add `flutter_svg` only after SVG assets are approved.

## Icon Recommendation

Recommended: Phosphor.

Why:

- Broad set.
- Modern, friendly, less generic than Material icons.
- Good weights for product UI.
- Works well for router, devices, shield, support, game and AI metaphors.

Second option: Iconsax.

Why not first:

- Stronger fintech/mobile aesthetic.
- Can look less native in restrained SaaS/product screens.

Current action:

- Do not add icon package until final choice is approved.
- Continue using Material icons only as temporary placeholders.

## Animation Recommendation

Recommended for Router1 status sphere: Rive.

Why:

- Interactive state machine support.
- Can represent statuses: connected, searching, warning, offline.
- Better for a living dashboard element than one-shot JSON animation.

Use Lottie for:

- onboarding micro-animation;
- payment success;
- lightweight non-interactive illustrations.

Do not use animation until the static layout is stable.

## Font Recommendation

Recommended: Manrope.

Decision path:

1. Test Manrope in the APK.
2. If it feels too geometric, test Inter.
3. Use Plus Jakarta Sans only after confirming Cyrillic coverage and readability.
4. Do not bundle SF Pro in Android APK.

## UI Update Process

For each future screen:

1. Confirm approved Figma frame or PNG reference.
2. Record frame size and target Android viewport.
3. Export assets into `assets/`.
4. Update or create reusable Flutter component.
5. Keep logic untouched unless the task explicitly allows it.
6. Run:

```bash
/root/flutter/bin/flutter analyze
/root/flutter/bin/flutter build apk --release
```

7. Copy APK:

```bash
cp build/app/outputs/flutter-apk/app-release.apk build-output/router1_app_mvp.apk
sha256sum build-output/router1_app_mvp.apk > build-output/router1_app_mvp.apk.sha256
```

8. Install on Android and compare visually.

## Screenshot Comparison

Recommended next tool:

- Android emulator or physical device screenshots through `adb`.
- Store screenshots in `docs/design/reviews/YYYYMMDD/`.
- Compare side by side against approved PNGs.

Future automation:

- Add golden tests after UI components stabilize.
- Add screenshot diff tooling only after the main flow stops changing daily.

## Sources To Use

- Figma Dev Mode and MCP documentation.
- Figma REST API documentation.
- Flutter assets and fonts documentation.
- Pub.dev package pages for selected icon/animation packages.

