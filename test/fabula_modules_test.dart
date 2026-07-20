import 'package:fabula_app/fabula_modules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional bottom sections follow profile toggles', () {
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
}
