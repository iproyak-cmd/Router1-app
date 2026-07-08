# BUILD & VERSION CONVENTION (Router1 app) — 08.07.2026

Проект теперь под git (baseline: комбинированное состояние — бэкенд Codex + визуал Claude).
Цель: одна понятная нумерация сборок, никаких потерь правок, Виктор получает ОДИН поток APK.

## Правила (для Codex и Claude)
1. Перед правкой: `git pull`-эквивалента нет (общая рабочая папка) — но СНАЧАЛА `git status`,
   чтобы увидеть незакоммиченные чужие изменения. Не редактируй файл, если он изменён и не закоммичен.
2. После своей правки: `git add -A && git commit -m "<кто>: <что>"` (префикс `claude:` или `codex:`).
3. Версия в pubspec.yaml `version: X.Y.Z+BUILD` — при КАЖДОЙ сборке для Виктора инкремент BUILD (+1).
   Синхронно обновлять `router1AppVersion` в lib/main.dart (та же строка). Baseline: см. pubspec.
4. Сборка APK: сначала commit, потом build. Имя файла: `router1-<version>-<кто>-<короткое-описание>.apk`.
   Так по имени видно версию, автора и суть. Пример: router1-0.1.40+43-claude-splash-globe.apk.
5. Зоны (во избежание правок одного файла одновременно):
   - Claude: lib/main.dart (визуал/экраны/тема), assets/, pubspec (секции fonts/assets),
             lib/services/keenetic_setup_service.dart (split-tunnel маршруты/MTU).
   - Codex: lib/router1_api.dart, backend/route-profile, протоколы/конфиги узлов, оплаты.
   - Пересечение (keenetic_setup_service.dart) — предупреждать друг друга через Виктора/коммит-месседж.
6. Если оба тронули один файл — git покажет; последний коммитящий обязан вручную свести правки, не затирать.

## Что уже в baseline-коммите
- Визуал (claude): Manrope, реальные иллюстрации роутер/гаджет (assets/illustrations), FittedBox-заголовки.
- Split-tunnel (claude): убран невалидный opkg, MTU 1360→1280, статические маршруты Google/Cloudflare.
- Бэкенд/протоколы (codex): всё, что было в дереве на момент baseline.
