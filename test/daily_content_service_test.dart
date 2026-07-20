import 'package:fabula_app/router1_api.dart';
import 'package:fabula_app/services/daily_content_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends Router1Api {
  _FakeApi(this.handler)
      : super(baseUrl: 'https://example.invalid', token: '', demoFallback: false);

  final Future<Router1DailyHoroscope> Function(String, DateTime?) handler;

  @override
  Future<Router1DailyHoroscope> dailyHoroscope(
    String sign, {
    DateTime? date,
  }) => handler(sign, date);
}

Router1DailyHoroscope _forecast(DateTime date, {String sign = 'libra'}) =>
    Router1DailyHoroscope(
      date: dateKey(date),
      sign: sign,
      signTitle: 'Весы',
      symbol: '♎',
      lunarPhase: 'server value',
      overview: 'Обзор',
      work: 'Дела',
      money: 'Деньги',
      love: 'Отношения',
      advice: 'Совет',
      color: 'Синий',
      number: 4,
      tarotTitle: 'Звезда',
      tarotMeaning: 'Смысл',
      disclaimer: 'Развлекательный прогноз',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('accepts only a package for the requested date and sign', () async {
    final day = DateTime(2026, 7, 20);
    final service = DailyContentService(
      _FakeApi((sign, requestedDate) async => _forecast(day)),
    );
    final prefs = await SharedPreferences.getInstance();

    final result = await service.resolve(
      sign: 'libra',
      date: day,
      preferences: prefs,
    );

    expect(result.source, DailyContentSource.live);
    expect(result.forecast.date, '2026-07-20');
    expect(result.forecast.lunarPhase, lunarPhaseFor(day));
  });

  test('stale server content is visibly replaced by editorial offline content',
      () async {
    final day = DateTime(2026, 7, 20);
    final stale = DateTime(2026, 7, 19);
    final service = DailyContentService(
      _FakeApi((sign, requestedDate) async => _forecast(stale)),
    );
    final prefs = await SharedPreferences.getInstance();

    final result = await service.resolve(
      sign: 'libra',
      date: day,
      preferences: prefs,
    );

    expect(result.source, DailyContentSource.editorialOffline);
    expect(result.notice, contains('Офлайн'));
    expect(result.forecast.date, '2026-07-20');
    expect(result.forecast.disclaimer, contains('офлайн'));
  });

  test('uses only same-day same-sign cache when the server is unavailable',
      () async {
    final day = DateTime(2026, 7, 20);
    final prefs = await SharedPreferences.getInstance();
    final online = DailyContentService(
      _FakeApi((sign, requestedDate) async => _forecast(day)),
    );
    await online.resolve(sign: 'libra', date: day, preferences: prefs);

    final offline = DailyContentService(
      _FakeApi((sign, requestedDate) async => throw Exception('offline')),
    );
    final cached = await offline.resolve(
      sign: 'libra',
      date: day,
      preferences: prefs,
    );
    final otherSign = await offline.resolve(
      sign: 'leo',
      date: day,
      preferences: prefs,
    );

    expect(cached.source, DailyContentSource.cached);
    expect(otherSign.source, DailyContentSource.editorialOffline);
  });

  test('moon phase uses the astronomical synodic cycle reference', () {
    expect(lunarPhaseFor(DateTime(2000, 1, 6)), 'Новолуние');
    expect(lunarGuidanceFor(DateTime(2026, 7, 20)), isNotEmpty);
  });

  test('editorial fallback is deterministic per date and sign', () {
    final day = DateTime(2026, 7, 20);
    final first = buildEditorialForecast('leo', day);
    final second = buildEditorialForecast('leo', day);

    expect(first.date, '2026-07-20');
    expect(first.sign, 'leo');
    expect(first.overview, second.overview);
    expect(first.tarotTitle, second.tarotTitle);
    expect(dailyAffirmationFor('leo', day), dailyAffirmationFor('leo', day));
  });
}
