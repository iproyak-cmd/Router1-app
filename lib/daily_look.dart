class DailyLook {
  const DailyLook({
    required this.id,
    required this.assetPath,
    required this.title,
    required this.description,
  });

  final String id;
  final String assetPath;
  final String title;
  final String description;
}

const dailyLookCatalog = <DailyLook>[
  DailyLook(
    id: 'burgundy_ivory',
    assetPath: 'assets/fabula/daily_looks/burgundy-ivory.webp',
    title: 'Тихая уверенность',
    description: 'Винный шёлк, тёплый айвори и одна золотая деталь.',
  ),
  DailyLook(
    id: 'black_silver',
    assetPath: 'assets/fabula/daily_looks/black-silver.webp',
    title: 'Чёткая линия',
    description: 'Архитектурный чёрный, мягкий блеск шёлка и серебро.',
  ),
  DailyLook(
    id: 'cashmere_camel',
    assetPath: 'assets/fabula/daily_looks/cashmere-camel.webp',
    title: 'Спокойная роскошь',
    description: 'Кашемир цвета айвори, верблюжий оттенок и тёмная кожа.',
  ),
  DailyLook(
    id: 'emerald_aubergine',
    assetPath: 'assets/fabula/daily_looks/emerald-aubergine.webp',
    title: 'Глубина цвета',
    description: 'Изумрудный сатин, баклажановый фон и приглушённое золото.',
  ),
  DailyLook(
    id: 'navy_dawn',
    assetPath: 'assets/fabula/daily_looks/navy-dawn.webp',
    title: 'Собранная энергия',
    description: 'Полуночный синий, прохладный рассвет и точное серебро.',
  ),
  DailyLook(
    id: 'rose_oxblood',
    assetPath: 'assets/fabula/daily_looks/rose-oxblood.webp',
    title: 'Мягкая сила',
    description: 'Пудровая роза, оттенок oxblood и сливочный камень.',
  ),
  DailyLook(
    id: 'ivory_stone',
    assetPath: 'assets/fabula/daily_looks/ivory-stone.webp',
    title: 'Светлая свобода',
    description: 'Скульптурный айвори, тёплый камень и чистая линия.',
  ),
  DailyLook(
    id: 'cobalt_tobacco',
    assetPath: 'assets/fabula/daily_looks/cobalt-tobacco.webp',
    title: 'Смелый баланс',
    description: 'Кобальт, табачный шёлк и одна геометричная деталь.',
  ),
];

DailyLook dailyLookFor({
  required String installationId,
  required DateTime date,
  List<DailyLook> catalog = dailyLookCatalog,
}) {
  if (catalog.isEmpty) {
    throw ArgumentError.value(catalog, 'catalog', 'must not be empty');
  }
  final normalizedDate = DateTime.utc(date.year, date.month, date.day);
  final dayNumber = normalizedDate.difference(DateTime.utc(2026)).inDays;
  final seed = _stableHash(
    installationId.trim().isEmpty ? 'fabula-local-installation' : installationId,
  );
  final step = _coprimeStep(seed, catalog.length);
  final position = _positiveModulo(dayNumber, catalog.length);
  final index = _positiveModulo(seed + position * step, catalog.length);
  return catalog[index];
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

int _coprimeStep(int seed, int length) {
  if (length == 1) return 1;
  var step = _positiveModulo(seed, length - 1) + 1;
  while (_greatestCommonDivisor(step, length) != 1) {
    step = step == length - 1 ? 1 : step + 1;
  }
  return step;
}

int _greatestCommonDivisor(int a, int b) {
  var left = a.abs();
  var right = b.abs();
  while (right != 0) {
    final remainder = left % right;
    left = right;
    right = remainder;
  }
  return left;
}

int _positiveModulo(int value, int modulus) =>
    ((value % modulus) + modulus) % modulus;
