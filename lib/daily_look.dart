class DailyLook {
  const DailyLook({
    required this.id,
    required this.title,
    required this.description,
    this.items = const [],
    this.stylingTip = '',
    this.occasion = '',
    this.assetPath,
    this.imageUrl,
  }) : assert(assetPath != null || imageUrl != null);

  final String id;
  final String? assetPath;
  final String? imageUrl;
  final String title;
  final String description;
  final List<String> items;
  final String stylingTip;
  final String occasion;
}

const dailyLookCatalog = <DailyLook>[
  DailyLook(
    id: '2026-07-burgundy-ivory-01',
    assetPath: 'assets/fabula/daily_looks/burgundy-ivory.webp',
    title: 'Тихая уверенность',
    description: 'Выразительный комплект для дня, когда хочется выглядеть собранно, но не строго.',
    items: ['Винная атласная рубашка', 'Брюки палаццо цвета айвори', 'Широкий золотой браслет'],
    stylingTip: 'Заправьте рубашку только спереди и оставьте верхнюю пуговицу расстёгнутой.',
    occasion: 'Офис, деловой обед или вечерняя встреча',
  ),
  DailyLook(
    id: '2026-07-black-silver-02',
    assetPath: 'assets/fabula/daily_looks/black-silver.webp',
    title: 'Чёткая линия',
    description: 'Монохромный образ, в котором мягкий сатин делает строгий костюм женственнее.',
    items: ['Чёрный жакет прямого кроя', 'Сатиновый топ с драпировкой', 'Серебряные серьги и кольцо'],
    stylingTip: 'Соберите волосы и оставьте шею открытой — так серьги станут главным акцентом.',
    occasion: 'Переговоры, презентация или ужин',
  ),
  DailyLook(
    id: '2026-07-cashmere-camel-03',
    assetPath: 'assets/fabula/daily_looks/cashmere-camel.webp',
    title: 'Спокойная роскошь',
    description: 'Светлая многослойность без лишнего объёма — спокойный и дорогой повседневный образ.',
    items: ['Тонкая водолазка цвета айвори', 'Широкие светлые брюки', 'Удлинённый жакет оттенка кэмел', 'Тёмные кожаные лоферы'],
    stylingTip: 'Поддержите вертикаль одинаковым оттенком верха и брюк, а жакет носите распахнутым.',
    occasion: 'Рабочий день, поездка или встреча в городе',
  ),
  DailyLook(
    id: '2026-07-emerald-aubergine-04',
    assetPath: 'assets/fabula/daily_looks/emerald-aubergine.webp',
    title: 'Глубина цвета',
    description: 'Самодостаточный вечерний образ: насыщенный цвет и чистый силуэт уже делают всю работу.',
    items: ['Изумрудное платье миди', 'Мягко очерченные плечи', 'Золотой браслет и небольшие серьги'],
    stylingTip: 'Не добавляйте яркое колье: открытая линия шеи сохранит образ современным.',
    occasion: 'Театр, свидание или торжественный ужин',
  ),
  DailyLook(
    id: '2026-07-navy-dawn-05',
    assetPath: 'assets/fabula/daily_looks/navy-dawn.webp',
    title: 'Собранная энергия',
    description: 'Деловой костюм с более мягким настроением благодаря голубой блузе и светлым аксессуарам.',
    items: ['Тёмно-синий брючный костюм', 'Голубая блуза свободного кроя', 'Крупное серебряное кольцо'],
    stylingTip: 'Закатайте рукава жакета до запястья и оставьте блузу слегка свободной.',
    occasion: 'Офис, собеседование или публичное выступление',
  ),
  DailyLook(
    id: '2026-07-rose-oxblood-06',
    assetPath: 'assets/fabula/daily_looks/rose-oxblood.webp',
    title: 'Мягкая сила',
    description: 'Сложные оттенки розового выглядят взросло, когда собраны вокруг глубокого винного цвета.',
    items: ['Пальто пыльно-розового оттенка', 'Платье цвета oxblood', 'Бордовый клатч'],
    stylingTip: 'Выбирайте обувь в тон платью или нейтральную — третий яркий цвет здесь не нужен.',
    occasion: 'Выставка, ресторан или вечерняя прогулка',
  ),
  DailyLook(
    id: '2026-07-ivory-stone-07',
    assetPath: 'assets/fabula/daily_looks/ivory-stone.webp',
    title: 'Светлая свобода',
    description: 'Воздушный монохром, в котором интерес создают асимметрия и движение ткани.',
    items: ['Топ без рукавов цвета айвори', 'Объёмная асимметричная юбка миди', 'Минималистичные сандалии'],
    stylingTip: 'Сохраните монохром и добавьте только один небольшой металлический аксессуар.',
    occasion: 'Отпуск, летнее событие или прогулка у моря',
  ),
  DailyLook(
    id: '2026-07-cobalt-tobacco-08',
    assetPath: 'assets/fabula/daily_looks/cobalt-tobacco.webp',
    title: 'Смелый баланс',
    description: 'Контраст тёплого табачного и холодного синего делает простой комплект заметным.',
    items: ['Табачная атласная рубашка', 'Кобальтовые брюки с высокой посадкой', 'Широкий золотой браслет'],
    stylingTip: 'Оставьте рубашку свободной и повторите золото только в одной детали.',
    occasion: 'Творческая встреча, мероприятие или выходной в городе',
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
