# Router1 Route Profiles

Дата: 2026-07-08

Этот документ фиксирует продуктовую и техническую логику режимов Router1, чтобы
backend, визуал и настройка роутера не расходились.

## Профили

### Standard

- ID API: `gold_standard`
- Старый alias: `router-default`
- Назначение: основной стабильный режим продаж.
- Через туннель: Telegram, WhatsApp, YouTube.
- Нейронки: нет.
- Игровые сервисы: нет.
- Ожидание клиента: быстрый обычный интернет напрямую, нужные медиа и мессенджеры
  работают через Router1.

### +AI

- ID API: `ai`
- Назначение: расширенный режим, когда клиенту нужны нейронки.
- Через туннель: Standard + ChatGPT, Claude, Gemini, Perplexity и связанные
  endpoint.
- Может быть медленнее Standard.
- Этот режим требует отдельного тестирования, потому что ChatGPT/Claude зависят от
  Cloudflare, auth, challenge, DNS, IPv6 и MTU.

### For Gamers

- ID API: `gamers`
- Назначение: игровые сервисы без нейронок.
- Через туннель: Standard + игровые домены.
- Нейронки: нет.
- Первый набор игровых доменов: Discord, Steam, Epic, Battle.net, Activision,
  Riot, EA, Ubisoft, Xbox, PlayStation.

## Production API

Доступные endpoint:

- `/api/app/route-profile/router-default`
- `/api/app/route-profile/gold_standard`
- `/api/app/route-profile/ai`
- `/api/app/route-profile/gamers`

`router-default` намеренно возвращает `gold_standard`, чтобы старые версии
приложения получали стабильный режим Telegram / WhatsApp / YouTube.

Проверенное состояние production API:

- version: `2026-07-08.3`
- `gold_standard`: `media_domains=45`, `ai_domains=0`,
  `media_resolved_hosts=14`, `media_ipv4_routes=133`, services: `youtube`,
  `telegram`, `whatsapp`
- `ai`: `media_domains=45`, `ai_domains=74`, `media_resolved_hosts=14`,
  `ai_resolved_hosts=30`, `media_ipv4_routes=132`, `ai_ipv4_routes=65`,
  services: `youtube`, `telegram`, `whatsapp`, `ai`
- `gamers`: `media_domains=72`, `ai_domains=0`, `media_resolved_hosts=20`,
  `media_ipv4_routes=144`, services: `youtube`, `telegram`, `whatsapp`,
  `games`

## Flutter API

Клиентский API:

```dart
api.routerRouteProfile();
api.routerRouteProfile(profile: Router1RouteProfileKind.ai);
api.routerRouteProfile(profile: Router1RouteProfileKind.gamers);
```

По умолчанию используется `Router1RouteProfileKind.goldStandard`.

Для связывания старых UI-режимов с новыми продуктовыми профилями:

```dart
final profile = Router1RouteProfileKind.fromRouterMode(mode);
```

Текущий setup-flow передает выбранный `Router1RouteProfileKind` из `main.dart`
в виджет установки роутера и вызывает:

```dart
routeProfile = await widget.api.routerRouteProfile(
  profile: widget.routeProfileKind,
);
```

`keenetic_setup_service.dart` для первого этапа менять не нужно: он уже применяет
тот `Router1RouteProfile`, который получает.

## Зоны ответственности

Codex:

- production route-profile API;
- `lib/router1_api.dart`;
- backend/payments/provisioning/config delivery.

Claude:

- визуальные названия и экраны выбора режима;
- `main.dart`;
- assets;
- UX-копирайт.

Пересечение:

- `lib/services/keenetic_setup_service.dart`.

Этот файл меняется только согласованно, потому что там фактическая установка
маршрутов на Keenetic.

## UX wording

Текущие пользовательские названия:

- `Standard`
- `+AI`
- `For Gamers`

Нельзя возвращать старые формулировки `Full tunnel`, `Скоростной режим` и
`VPN с маршрутизацией` в пользовательский текст.
