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
    description: 'Винный шёлк, тёплый айвори и одна золотая деталь.',
  ),
  DailyLook(
    id: '2026-07-black-silver-02',
    assetPath: 'assets/fabula/daily_looks/black-silver.webp',
    title: 'Чёткая линия',
    description: 'Архитектурный чёрный, мягкий блеск шёлка и серебро.',
  ),
  DailyLook(
    id: '2026-07-cashmere-camel-03',
    assetPath: 'assets/fabula/daily_looks/cashmere-camel.webp',
    title: 'Спокойная роскошь',
    description: 'Кашемир цвета айвори, верблюжий оттенок и тёмная кожа.',
  ),
  DailyLook(
    id: '2026-07-emerald-aubergine-04',
    assetPath: 'assets/fabula/daily_looks/emerald-aubergine.webp',
    title: 'Глубина цвета',
    description: 'Изумрудный сатин, баклажановый фон и приглушённое золото.',
  ),
  DailyLook(
    id: '2026-07-navy-dawn-05',
    assetPath: 'assets/fabula/daily_looks/navy-dawn.webp',
    title: 'Собранная энергия',
    description: 'Полуночный синий, прохладный рассвет и точное серебро.',
  ),
  DailyLook(
    id: '2026-07-rose-oxblood-06',
    assetPath: 'assets/fabula/daily_looks/rose-oxblood.webp',
    title: 'Мягкая сила',
    description: 'Пудровая роза, оттенок oxblood и сливочный камень.',
  ),
  DailyLook(
    id: '2026-07-ivory-stone-07',
    assetPath: 'assets/fabula/daily_looks/ivory-stone.webp',
    title: 'Светлая свобода',
    description: 'Скульптурный айвори, тёплый камень и чистая линия.',
  ),
  DailyLook(
    id: '2026-07-cobalt-tobacco-08',
    assetPath: 'assets/fabula/daily_looks/cobalt-tobacco.webp',
    title: 'Смелый баланс',
    description: 'Кобальт, табачный шёлк и одна геометричная деталь.',
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
