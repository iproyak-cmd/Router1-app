import 'package:fabula_app/fabula_modules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional bottom sections follow profile toggles', () {
    expect(
      fabulaNavigationSectionIds({
        cycleModuleId,
        connectionModuleId,
        compatibilityModuleId,
      }),
      ['today', 'cycle', 'connection', 'compatibility', 'profile'],
    );

    expect(
      fabulaNavigationSectionIds({connectionModuleId}),
      ['today', 'connection', 'profile'],
    );

    expect(fabulaNavigationSectionIds({}), ['today', 'profile']);
  });
}
