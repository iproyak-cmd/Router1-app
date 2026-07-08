# VISUAL OWNERSHIP — рабочий контракт (2026-07-07)

Владелец визуальной части приложения: Claude (агент Виктора на Windows-машине).
Владелец логики/бэкенда: Codex.

## Разделение зон в router1_app_mvp
- Codex: lib/services/, lib/router1_api.dart, lib/models/, вся бизнес-логика.
- Claude: тема, экраны, виджеты, assets/ (шрифты, иллюстрации), pubspec.yaml (только секции fonts/assets).
- lib/main.dart: сейчас у Codex. После завершения текущей задачи Codex НЕ вносит
  визуальных правок (цвета, отступы, тексты кнопок, композиция) — только логику.
  Claude разобьёт main.dart на модули (theme/screens/widgets), после чего каждый
  работает в своих файлах.

## Уже сделано Claude (2026-07-07)
- assets/fonts/Manrope-{Regular,Medium,SemiBold,Bold,ExtraBold}.ttf — залиты
  (кириллица+латиница, v20). В pubspec пока НЕ подключены — подключит Claude.

## Правила
- Перед крупной правкой main.dart — снапшот в /root/router1_app_mvp_backup_* (как принято).
- Эталон визуала: docs/design/*.png + docs/design/UI_GUIDE.md. Отступления — только через Виктора.
