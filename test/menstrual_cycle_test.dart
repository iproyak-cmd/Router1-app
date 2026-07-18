import 'package:fabula_app/models/menstrual_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cycleLength = 28;
  const periodLength = 5;
  final settings = CycleSettings(
    lastPeriodStart: DateTime(2026, 7, 1),
    cycleLength: cycleLength,
    periodLength: periodLength,
  );

  test('tracks cycle day and menstrual phase', () {
    final snapshot = settings.snapshot(DateTime(2026, 7, 3));
    expect(snapshot.cycleDay, 3);
    expect(snapshot.phase, CyclePhase.menstruation);
  });

  test('estimates fertile window and ovulation', () {
    expect(settings.snapshot(DateTime(2026, 7, 9)).phase, CyclePhase.fertile);
    expect(
      settings.snapshot(DateTime(2026, 7, 14)).phase,
      CyclePhase.ovulation,
    );
    expect(settings.snapshot(DateTime(2026, 7, 15)).phase, CyclePhase.luteal);
  });

  test('predicts next period from the last known start', () {
    final snapshot = settings.snapshot(DateTime(2026, 7, 18));
    expect(snapshot.nextPeriodStart, DateTime(2026, 7, 29));
    expect(snapshot.daysUntilNextPeriod, 11);
  });

  test('continues predictions after a missed confirmation', () {
    final snapshot = settings.snapshot(DateTime(2026, 7, 30));
    expect(snapshot.cycleDay, 2);
    expect(snapshot.nextPeriodStart, DateTime(2026, 8, 26));
  });
}
