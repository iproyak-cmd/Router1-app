# Router1 UI Guide

Date: 2026-06-28 UTC

This guide is the working design contract for transferring approved Router1 screens into Flutter. The current source of truth for visual matching is the PNG set in `docs/design/`.

## Design Source

- Figma file: pending owner setup.
- Current approved references:
  - `01. Splash.png`
  - `02. First Run.png`
  - `03. Поиск роутера.png`
  - `04. Роутер найден.png`
  - `05. Совместимость.png`
  - `06. Что получаю.png`
  - `07. Оплата.png`
  - `08. Home.png`

## Color System

Primary background:

- App background: `#020B10`
- Deep green radial background: `#08241F`
- Panel dark: `#07151D` at high opacity
- Secondary panel: `#0A1E28` at medium opacity

Primary brand:

- Router1 green: `#7BE33C`
- Router1 green deep: `#28B84F`
- Action blue: `#2F69FF`

Text:

- Primary: `#F9FAFB`
- Secondary: `#A8B2BC`
- Muted border/text: `#1B3340`

States:

- Success: `#7BE33C`
- Info/action: `#2F69FF`
- AI/accent purple: `#9B6BFF`
- Warning/tariff accent: `#D8A21C`
- Alert/badge: `#FF554E`

## Typography

Current Flutter fallback: `Roboto`.

Recommended production font: `Manrope`.

Why:

- Good Cyrillic support.
- Commercial, modern SaaS feel.
- Strong numerals for prices, speeds, ping and dashboard metrics.
- Easier to license and ship than SF Pro.

Alternatives:

- Inter: excellent UI default, slightly more neutral and common.
- Plus Jakarta Sans: premium look, but Cyrillic coverage must be verified before use.
- SF Pro: strong Apple-native look, but licensing makes bundling in Android APK unsuitable.

Proposed scale:

- Hero/logo: 48-58, weight 900.
- Screen title: 32-34, weight 800-900.
- Section title/card title: 22-28, weight 700-900.
- Body: 17-19, weight 500-700.
- Caption: 13-15, weight 500-700.

Rules:

- Do not scale font size with viewport width.
- Use height-adaptive spacing and component sizes instead.
- Keep letter spacing at `0`.

## Spacing

Base unit: `4`.

Recommended spacing:

- Screen horizontal padding: `22-28`.
- Header top padding: `28-42`.
- Card internal padding: `16-24`.
- Card gap: `10-22`.
- CTA gap: `22-30`.

## Radius

- Primary buttons: `20`.
- Main glass cards: `22`.
- Icon containers: `14-15`.
- Small badges: `12`.
- Avoid deeply rounded cards unless the reference requires it.

## Shadows And Glow

Router1 uses glow as a product signal, not decoration.

Recommended values:

- Green card glow: green at `0.14-0.18`, blur `24-32`.
- Status orb glow: radial green with transparent edge.
- Background stars/noise: very low opacity, no decorative blobs.

Rules:

- Glow should support status, action or focus.
- Avoid one-note green screens; mix neutral panels, blue action and occasional purple/warning accents.

## Components

Current reusable Flutter primitives:

- `Router1Theme`
- `PrimaryButton`
- `Router1Card`
- `StatusOrb`
- `SetupHeader`

Recommended next components:

- `Router1IconButton`
- `ModeCard`
- `MetricCard`
- `DeviceRow`
- `SupportAction`
- `PaymentPlanCard`
- `DesignToken` constants for spacing/radius/type.

## Asset Rules

Use:

- PNG/WebP for raster illustrations, rich backgrounds and exported mock imagery.
- SVG for simple scalable icons and vector marks when the package supports it.
- Rive for interactive state animation.
- Lottie for lightweight decorative or onboarding animation.

Avoid:

- Embedding full-screen PNGs as app screens.
- Manually redrawing icons that exist in the selected icon set.
- Large uncompressed PNGs in APK.

