import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../router1_api.dart';

enum DailyContentSource { live, cached, editorialOffline }

class DailyContentEnvelope {
  const DailyContentEnvelope({
    required this.forecast,
    required this.source,
    required this.updatedAt,
    required this.notice,
  });

  final Router1DailyHoroscope forecast;
  final DailyContentSource source;
  final DateTime updatedAt;
  final String notice;

  bool get isLive => source == DailyContentSource.live;
}

class DailyContentService {
  const DailyContentService(this.api);

  final Router1Api api;

  Future<DailyContentEnvelope> resolve({
    required String sign,
    required DateTime date,
    required SharedPreferences preferences,
  }) async {
    final day = dateOnly(date);
    final key = dateKey(day);
    try {
      final remote = await api.dailyHoroscope(sign, date: day);
      final normalized = withAccurateMoon(remote, day);
      _validate(normalized, expectedDate: key, expectedSign: sign);
      final updatedAt = DateTime.now();
      await preferences.setString(
        _cacheKey(key, sign),
        jsonEncode({
          'updated_at': updatedAt.toIso8601String(),
          'forecast': _toJson(normalized),
        }),
      );
      return DailyContentEnvelope(
        forecast: normalized,
        source: DailyContentSource.live,
        updatedAt: updatedAt,
        notice: 'Прогноз обновлён сегодня',
      );
    } catch (_) {
      final cached = _readCache(preferences, key, sign);
      if (cached != null) {
        return DailyContentEnvelope(
          forecast: withAccurateMoon(cached.$1, day),
          source: DailyContentSource.cached,
          updatedAt: cached.$2,
          notice: 'Сохранённый прогноз за сегодня',
        );
      }
      return DailyContentEnvelope(
        forecast: buildEditorialForecast(sign, day),
        source: DailyContentSource.editorialOffline,
        updatedAt: DateTime.now(),
        notice: 'Офлайн-подборка — серверный прогноз пока недоступен',
      );
    }
  }

  (Router1DailyHoroscope, DateTime)? _readCache(
    SharedPreferences preferences,
    String expectedDate,
    String expectedSign,
  ) {
    final raw = preferences.getString(_cacheKey(expectedDate, expectedSign));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final forecast = Router1DailyHoroscope.fromJson(
        Map<String, dynamic>.from(decoded['forecast'] as Map),
      );
      _validate(
        forecast,
        expectedDate: expectedDate,
        expectedSign: expectedSign,
      );
      final updatedAt =
          DateTime.tryParse(decoded['updated_at']?.toString() ?? '') ??
          DateTime.now();
      return (forecast, updatedAt);
    } catch (_) {
      return null;
    }
  }

  void _validate(
    Router1DailyHoroscope value, {
    required String expectedDate,
    required String expectedSign,
  }) {
    if (value.date != expectedDate ||
        value.sign != expectedSign ||
        value.signTitle.trim().isEmpty ||
        value.overview.trim().isEmpty ||
        value.work.trim().isEmpty ||
        value.money.trim().isEmpty ||
        value.love.trim().isEmpty ||
        value.advice.trim().isEmpty ||
        value.color.trim().isEmpty ||
        value.number < 1 ||
        value.number > 9 ||
        value.tarotTitle.trim().isEmpty ||
        value.tarotMeaning.trim().isEmpty) {
      throw const FormatException('stale_or_incomplete_daily_content');
    }
  }
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _cacheKey(String day, String sign) =>
    'fabula_daily_content_${day}_$sign';

Map<String, Object?> _toJson(Router1DailyHoroscope value) => {
  'date': value.date,
  'sign': value.sign,
  'sign_title': value.signTitle,
  'symbol': value.symbol,
  'lunar_phase': value.lunarPhase,
  'overview': value.overview,
  'work': value.work,
  'money': value.money,
  'love': value.love,
  'advice': value.advice,
  'color': value.color,
  'number': value.number,
  'tarot': {
    'title': value.tarotTitle,
    'meaning': value.tarotMeaning,
  },
  'disclaimer': value.disclaimer,
};

Router1DailyHoroscope withAccurateMoon(
  Router1DailyHoroscope value,
  DateTime date,
) => Router1DailyHoroscope(
  date: value.date,
  sign: value.sign,
  signTitle: value.signTitle,
  symbol: value.symbol,
  lunarPhase: lunarPhaseFor(date),
  overview: value.overview,
  work: value.work,
  money: value.money,
  love: value.love,
  advice: value.advice,
  color: value.color,
  number: value.number,
  tarotTitle: value.tarotTitle,
  tarotMeaning: value.tarotMeaning,
  disclaimer: value.disclaimer,
);

String lunarPhaseFor(DateTime value) {
  const synodicMonth = 29.530588853;
  final instant = DateTime.utc(value.year, value.month, value.day, 12);
  final reference = DateTime.utc(2000, 1, 6, 18, 14);
  final elapsedDays =
      instant.difference(reference).inMilliseconds /
      Duration.millisecondsPerDay;
  final age = ((elapsedDays % synodicMonth) + synodicMonth) % synodicMonth;
  if (age < 1.84566 || age >= 27.68493) return 'Новолуние';
  if (age < 5.53699) return 'Растущий серп';
  if (age < 9.22831) return 'Первая четверть';
  if (age < 12.91963) return 'Растущая Луна';
  if (age < 16.61096) return 'Полнолуние';
  if (age < 20.30228) return 'Убывающая Луна';
  if (age < 23.99361) return 'Последняя четверть';
  return 'Убывающий серп';
}

String lunarGuidanceFor(DateTime value) => switch (lunarPhaseFor(value)) {
  'Новолуние' =>
    'Подходящий день, чтобы определить намерение и начать с небольшого шага.',
  'Растущий серп' =>
    'Добавляйте темп постепенно и поддерживайте то, что уже начало расти.',
  'Первая четверть' =>
    'Сверьте направление и примите одно решение, которое давно откладывали.',
  'Растущая Луна' =>
    'Продолжайте начатое: сейчас важнее последовательность, чем скорость.',
  'Полнолуние' =>
    'Заметьте результат, снизьте перегрузку и не принимайте решения на пике эмоций.',
  'Убывающая Луна' =>
    'Завершайте незакрытое и освобождайте место от лишних обязательств.',
  'Последняя четверть' =>
    'Подведите промежуточные итоги и оставьте только то, что действительно работает.',
  _ =>
    'Снизьте темп, восстановитесь и подготовьте пространство для нового цикла.',
};

Router1DailyHoroscope buildEditorialForecast(String sign, DateTime date) {
  const signs = <String, (String, String)>{
    'aries': ('Овен', '♈'),
    'taurus': ('Телец', '♉'),
    'gemini': ('Близнецы', '♊'),
    'cancer': ('Рак', '♋'),
    'leo': ('Лев', '♌'),
    'virgo': ('Дева', '♍'),
    'libra': ('Весы', '♎'),
    'scorpio': ('Скорпион', '♏'),
    'sagittarius': ('Стрелец', '♐'),
    'capricorn': ('Козерог', '♑'),
    'aquarius': ('Водолей', '♒'),
    'pisces': ('Рыбы', '♓'),
  };
  final identity = signs[sign] ?? signs['libra']!;
  final key = '${dateKey(date)}:$sign';
  const overviews = [
    'Сегодня полезно выбрать один ясный приоритет и дать ему достаточно внимания.',
    'День лучше раскрывается через спокойный темп, точные слова и небольшие завершённые дела.',
    'Не всё требует немедленного ответа: пауза поможет увидеть более сильное решение.',
    'Сосредоточьтесь на том, что возвращает ощущение опоры и управляемости.',
    'Сегодня ценнее последовательность, чем резкий рывок или желание успеть всё.',
    'Дайте место любопытству: неожиданная деталь может подсказать практичный следующий шаг.',
  ];
  const work = [
    'Закройте одну задачу с измеримым результатом прежде, чем открывать следующую.',
    'Проверьте договорённости и сроки: ясность сегодня экономит силы завтра.',
    'Лучшее решение появится после короткого разговора с человеком, который видит ситуацию иначе.',
    'Отделите срочное от важного и защитите время для главной задачи.',
  ];
  const money = [
    'Полезно сверить регулярные расходы и не принимать решение только из-за срочности.',
    'Сравните условия и зафиксируйте цифры письменно перед новым обязательством.',
    'Сегодня разумнее укрепить уже работающий источник, чем распыляться на несколько новых.',
    'Небольшая экономия внимания может оказаться важнее небольшой экономии денег.',
  ];
  const love = [
    'Говорите прямо и бережно: ясная просьба сегодня лучше намёков.',
    'Тёплый короткий контакт поможет больше, чем попытка решить всё одним разговором.',
    'Оставьте место и близости, и личному пространству — одно не отменяет другое.',
    'Не угадывайте чужие мысли: задайте спокойный уточняющий вопрос.',
  ];
  const advice = [
    'Сделайте следующий шаг достаточно маленьким, чтобы начать его без внутреннего сопротивления.',
    'Оставьте в расписании двадцать минут без экрана и новых задач.',
    'Запишите решение одним предложением — так станет видно, действительно ли оно ваше.',
    'Выберите действие, после которого вечер станет спокойнее.',
  ];
  const colors = [
    'Бордовый',
    'Золотой',
    'Зелёный',
    'Синий',
    'Бирюзовый',
    'Фиолетовый',
    'Серебристый',
  ];
  const cards = <(String, String)>[
    ('Шут', 'Новый шаг не требует знания всего маршрута. Достаточно честного интереса и внимания к границам.'),
    ('Маг', 'Используйте то, что уже есть под рукой: ресурс дня проявляется через действие.'),
    ('Верховная Жрица', 'Не торопите выводы. Наблюдение и тишина помогут отделить интуицию от тревоги.'),
    ('Императрица', 'Поддержите то, что растёт через заботу, качество и уважение к собственному темпу.'),
    ('Император', 'Структура и ясные правила освободят больше энергии, чем постоянное исправление хаоса.'),
    ('Влюблённые', 'Выбор становится проще, когда совпадает с вашими ценностями, а не только с ожиданиями.'),
    ('Колесница', 'Определите направление и не отдавайте внимание каждому внешнему сигналу.'),
    ('Сила', 'Мягкая настойчивость сегодня убедительнее давления.'),
    ('Отшельник', 'Короткое уединение поможет услышать собственный ответ.'),
    ('Колесо Фортуны', 'Изменение условий можно использовать, если быстро отделить возможность от шума.'),
    ('Справедливость', 'Проверьте факты, договорённости и последствия до окончательного решения.'),
    ('Звезда', 'Вернитесь к большой цели и выберите один шаг, который подтверждает направление.'),
    ('Луна', 'Неопределённость не требует паники: дайте деталям проявиться.'),
    ('Солнце', 'Покажите результат и позвольте себе признать то, что уже получилось.'),
    ('Мир', 'Завершение освобождает место. Зафиксируйте итог прежде, чем идти дальше.'),
  ];
  T pick<T>(List<T> values, String field) =>
      values[_stableHash('$key:$field') % values.length];
  return Router1DailyHoroscope(
    date: dateKey(date),
    sign: sign,
    signTitle: identity.$1,
    symbol: identity.$2,
    lunarPhase: lunarPhaseFor(date),
    overview: pick(overviews, 'overview'),
    work: pick(work, 'work'),
    money: pick(money, 'money'),
    love: pick(love, 'love'),
    advice: pick(advice, 'advice'),
    color: pick(colors, 'color'),
    number: _stableHash('$key:number') % 9 + 1,
    tarotTitle: pick(cards, 'tarot').$1,
    tarotMeaning: pick(cards, 'tarot').$2,
    disclaimer:
        'Редакционная офлайн-подборка. Не является научным прогнозом.',
  );
}

String dailyAffirmationFor(String sign, DateTime date) {
  const values = [
    'Я выбираю один важный шаг и спокойно довожу его до результата.',
    'Я могу двигаться в своём темпе и сохранять ясность.',
    'Сегодня я замечаю возможности, которые действительно поддерживают меня.',
    'Я отношусь к себе бережно и говорю о своих потребностях прямо.',
    'Мне не нужно успевать всё, чтобы день имел ценность.',
    'Я доверяю фактам, своим границам и выбранному направлению.',
    'Я оставляю место отдыху, вниманию и хорошим неожиданностям.',
    'Я могу изменить решение, если новая информация делает его лучше.',
    'Сегодня моя сила — в последовательности и спокойном присутствии.',
    'Я разрешаю себе завершать лишнее и освобождать пространство.',
    'Я замечаю собственный прогресс, даже если он состоит из маленьких шагов.',
    'Я выбираю отношения и дела, в которых есть взаимность.',
  ];
  return values[_stableHash('${dateKey(date)}:$sign:affirmation') % values.length];
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
