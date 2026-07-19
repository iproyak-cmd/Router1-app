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
      looks.add(
        dailyLookFor(
          installationId: 'installation-a',
          date: DateTime(2026, 7, 19).add(Duration(days: day)),
        ).id,
      );
    }

    expect(looks, hasLength(dailyLookCatalog.length));
  });

  test('personalizes the sequence for different installations', () {
    final firstSequence = List.generate(
      dailyLookCatalog.length,
      (day) => dailyLookFor(
        installationId: 'installation-a',
        date: DateTime(2026, 7, 19).add(Duration(days: day)),
      ).id,
    );
    final secondSequence = List.generate(
      dailyLookCatalog.length,
      (day) => dailyLookFor(
        installationId: 'installation-b',
        date: DateTime(2026, 7, 19).add(Duration(days: day)),
      ).id,
    );

    expect(secondSequence, isNot(equals(firstSequence)));
  });

  test('every catalog item points to a curated Fabula asset', () {
    for (final look in dailyLookCatalog) {
      expect(look.assetPath, startsWith('assets/fabula/daily_looks/'));
      expect(look.assetPath, endsWith('.webp'));
      expect(look.title.trim(), isNotEmpty);
      expect(look.description.trim(), isNotEmpty);
    }
  });
}
