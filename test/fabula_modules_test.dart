import 'package:fabula_app/fabula_modules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid connection appears only when its module is enabled', () {
    expect(
      fabulaNavigationSectionIds({
        companionModuleId,
        cycleModuleId,
        connectionModuleId,
        compatibilityModuleId,
      }),
      ['today', 'companion', 'cycle', 'connection', 'compatibility', 'profile'],
    );

    expect(
      fabulaNavigationSectionIds({companionModuleId, connectionModuleId}),
      ['today', 'companion', 'connection', 'profile'],
    );

    expect(fabulaNavigationSectionIds({}), ['today', 'profile']);
  });

  test('assistant only suggests enabled modules', () {
    expect(
      fabulaAssistantNudgeModuleId(
        {cycleModuleId, journalModuleId},
        cycleConfigured: false,
      ),
      cycleModuleId,
    );
    expect(
      fabulaAssistantNudgeModuleId(
        {journalModuleId},
        cycleConfigured: false,
      ),
      journalModuleId,
    );
    expect(
      fabulaAssistantNudgeModuleId({}, cycleConfigured: false),
      isNull,
    );
  });

  test('career has its own optional navigation section', () {
    expect(
      fabulaNavigationSectionIds({careerModuleId}),
      ['today', 'career', 'profile'],
    );
  });
}
