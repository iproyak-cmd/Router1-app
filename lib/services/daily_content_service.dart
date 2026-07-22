import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../router1_api.dart';

enum DailyContentSource { live, cached }

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
      throw const DailyContentUnavailable();
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

class DailyContentUnavailable implements Exception {
  const DailyContentUnavailable();
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
