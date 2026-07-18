enum CyclePhase { menstruation, follicular, fertile, ovulation, luteal }

class CycleSettings {
  const CycleSettings({
    required this.lastPeriodStart,
    required this.cycleLength,
    required this.periodLength,
  });

  final DateTime lastPeriodStart;
  final int cycleLength;
  final int periodLength;

  CycleSnapshot snapshot([DateTime? value]) {
    final date = _dateOnly(value ?? DateTime.now());
    final start = _dateOnly(lastPeriodStart);
    final daysSinceStart = date.difference(start).inDays;
    final normalizedOffset = daysSinceStart >= 0
        ? daysSinceStart % cycleLength
        : (cycleLength - ((-daysSinceStart) % cycleLength)) % cycleLength;
    final cycleDay = normalizedOffset + 1;
    final ovulationDay = (cycleLength - 14)
        .clamp(periodLength + 2, cycleLength - 7)
        .toInt();
    final fertileStart = (ovulationDay - 5)
        .clamp(periodLength + 1, ovulationDay)
        .toInt();

    final phase = switch (cycleDay) {
      final day when day <= periodLength => CyclePhase.menstruation,
      final day when day < fertileStart => CyclePhase.follicular,
      final day when day < ovulationDay => CyclePhase.fertile,
      final day when day == ovulationDay => CyclePhase.ovulation,
      _ => CyclePhase.luteal,
    };

    var periodsAhead = daysSinceStart <= 0
        ? 1
        : (daysSinceStart + cycleLength - 1) ~/ cycleLength;
    if (periodsAhead < 1) periodsAhead = 1;
    final nextPeriodStart = start.add(
      Duration(days: periodsAhead * cycleLength),
    );

    return CycleSnapshot(
      date: date,
      cycleDay: cycleDay,
      phase: phase,
      nextPeriodStart: nextPeriodStart,
      daysUntilNextPeriod: nextPeriodStart.difference(date).inDays,
      ovulationDay: ovulationDay,
    );
  }

  CyclePhase phaseOn(DateTime date) => snapshot(date).phase;
}

class CycleSnapshot {
  const CycleSnapshot({
    required this.date,
    required this.cycleDay,
    required this.phase,
    required this.nextPeriodStart,
    required this.daysUntilNextPeriod,
    required this.ovulationDay,
  });

  final DateTime date;
  final int cycleDay;
  final CyclePhase phase;
  final DateTime nextPeriodStart;
  final int daysUntilNextPeriod;
  final int ovulationDay;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
