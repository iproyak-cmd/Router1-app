class DailyLook {
  const DailyLook({
    required this.id,
    required this.title,
    required this.description,
    this.assetPath,
    this.imageUrl,
  }) : assert(assetPath != null || imageUrl != null);

  final String id;
  final String? assetPath;
  final String? imageUrl;
  final String title;
  final String description;
}

const dailyLookCatalog = <DailyLook>[
  DailyLook(
    id: '2026-07-burgundy-ivory-01',
    assetPath: 'assets/fabula/daily_looks/burgundy-ivory.webp',
    title: 'Тихая уверенность',
    description:
        'Верх: блуза или топ оттенка айвори. Низ: винная юбка миди или прямые брюки. Обувь: молочные лодочки либо лаконичные лоферы. Добавьте одну золотую деталь — серьги, браслет или пряжку сумки. Образ подходит для офиса, встречи и спокойного вечернего выхода.',
  ),
  DailyLook(
    id: '2026-07-black-silver-02',
    assetPath: 'assets/fabula/daily_looks/black-silver.webp',
    title: 'Чёткая линия',
    description:
        'Основа: чёрный жакет прямого кроя и шёлковый топ. Низ: широкие брюки или юбка ниже колена. Обувь: остроносые ботильоны либо минималистичные туфли. Украшения — серебро без крупных камней. Подходит для деловой встречи, презентации или вечера в городе.',
  ),
  DailyLook(
    id: '2026-07-cashmere-camel-03',
    assetPath: 'assets/fabula/daily_looks/cashmere-camel.webp',
    title: 'Спокойная роскошь',
    description:
        'Верх: мягкий джемпер цвета айвори или светлая рубашка. Сверху — пальто либо жакет верблюжьего оттенка. Низ: тёмные прямые джинсы или шоколадные брюки. Обувь и сумка — из тёмной кожи. Это удобный образ для прохладного дня, поездок и неформальных встреч.',
  ),
  DailyLook(
    id: '2026-07-emerald-aubergine-04',
    assetPath: 'assets/fabula/daily_looks/emerald-aubergine.webp',
    title: 'Глубина цвета',
    description:
        'Главная вещь: изумрудная блуза, платье или сатиновая юбка. Добавьте баклажановый жакет либо сумку глубокого фиолетового оттенка. Обувь лучше выбрать нейтральную — чёрную или тёмно-коричневую. Украшения — приглушённое золото. Подходит для ужина, события и выразительного городского образа.',
  ),
  DailyLook(
    id: '2026-07-navy-dawn-05',
    assetPath: 'assets/fabula/daily_looks/navy-dawn.webp',
    title: 'Собранная энергия',
    description:
        'Основа: полуночно-синий костюм, платье-футляр или комплект из рубашки и брюк. Добавьте светло-серый или голубой слой у лица. Обувь — белая, серебристая или тёмно-синяя. Украшения — холодное серебро. Хороший вариант для насыщенного рабочего дня и встреч, где важны собранность и ясность.',
  ),
  DailyLook(
    id: '2026-07-rose-oxblood-06',
    assetPath: 'assets/fabula/daily_looks/rose-oxblood.webp',
    title: 'Мягкая сила',
    description:
        'Верх: пудрово-розовый топ, рубашка или тонкий трикотаж. Низ: брюки, юбка либо джинсы оттенка oxblood. Обувь — молочная или бордовая. Сумку выберите сливочного оттенка. Образ подходит для свидания, встречи с подругами и дня, когда хочется выглядеть мягко, но не слишком романтично.',
  ),
  DailyLook(
    id: '2026-07-ivory-stone-07',
    assetPath: 'assets/fabula/daily_looks/ivory-stone.webp',
    title: 'Светлая свобода',
    description:
        'Соберите монохромный комплект из айвори и тёплого каменного оттенка: свободная рубашка, прямые брюки или юбка простой формы. Обувь — светлые кеды, балетки либо босоножки. Украшения оставьте минимальными. Подходит для тёплой погоды, прогулки, отпуска и спокойного рабочего дня.',
  ),
  DailyLook(
    id: '2026-07-cobalt-tobacco-08',
    assetPath: 'assets/fabula/daily_looks/cobalt-tobacco.webp',
    title: 'Смелый баланс',
    description:
        'Выберите одну кобальтовую вещь: жакет, рубашку, юбку или сумку. Сочетайте её с табачными брюками, шёлковым топом или аксессуарами тёплого коричневого оттенка. Обувь — тёмно-коричневая или бежевая. Добавьте одну геометричную деталь. Образ подходит для города, творческой встречи и выхода, где хочется быть заметной.',
  ),
];

DailyLook dailyLookFor({
  required String installationId,
  required DateTime date,
  List<DailyLook> catalog = dailyLookCatalog,
  Set<String> seenIds = const {},
}) {
  final available = catalog
      .where((look) => !seenIds.contains(look.id))
      .toList(growable: false);
  if (available.isEmpty) {
    throw const DailyLookCatalogExhausted();
  }
  final normalizedDate = DateTime.utc(date.year, date.month, date.day);
  final seed = _stableHash(
    '${installationId.trim().isEmpty ? 'fabula-local-installation' : installationId}:'
    '${normalizedDate.toIso8601String()}',
  );
  return available[_positiveModulo(seed, available.length)];
}

class DailyLookCatalogExhausted implements Exception {
  const DailyLookCatalogExhausted();
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

int _positiveModulo(int value, int modulus) =>
    ((value % modulus) + modulus) % modulus;
