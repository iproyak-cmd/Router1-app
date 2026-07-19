import 'package:flutter_test/flutter_test.dart';
import 'package:fabula_app/daily_look.dart';

void main() {
  test('keeps one stable editorial look for the whole day', () {
    final morning = dailyLookFor(
      installationId: 'installation-a',
      date: DateTime(2026, 7, 19, 8),
    );
    final evening = dailyLookFor(
      installationId: 'installation-a',
      date: DateTime(2026, 7, 19, 23, 59),
    );

    expect(evening.id, morning.id);
  });

  test('does not repeat before the current collection is exhausted', () {
    final looks = <String>{};
    for (var day = 0; day < dailyLookCatalog.length; day++) {
      final look = dailyLookFor(
        installationId: 'installation-a',
        date: DateTime(2026, 7, 19).add(Duration(days: day)),
        seenIds: looks,
      );
      expect(looks, isNot(contains(look.id)));
      looks.add(look.id);
    }

    expect(looks, hasLength(dailyLookCatalog.length));
    expect(
      () => dailyLookFor(
        installationId: 'installation-a',
        date: DateTime(2026, 7, 27),
        seenIds: looks,
      ),
      throwsA(isA<DailyLookCatalogExhausted>()),
    );
  });

  test('personalizes the sequence for different installations', () {
    List<String> sequence(String installationId) {
      final seen = <String>{};
      return List.generate(dailyLookCatalog.length, (day) {
        final look = dailyLookFor(
          installationId: installationId,
          date: DateTime(2026, 7, 19).add(Duration(days: day)),
          seenIds: seen,
        );
        seen.add(look.id);
        return look.id;
      });
    }

    final firstSequence = sequence('installation-a');
    final secondSequence = sequence('installation-b');

    expect(secondSequence, isNot(equals(firstSequence)));
  });

  test('every catalog item points to a curated Fabula asset', () {
    for (final look in dailyLookCatalog) {
      expect(look.assetPath, isNotNull);
      expect(look.assetPath!, startsWith('assets/fabula/daily_looks/'));
      expect(look.assetPath!, endsWith('.webp'));
      expect(look.title.trim(), isNotEmpty);
      expect(look.description.trim(), isNotEmpty);
    }
  });
}
