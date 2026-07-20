import 'package:fabula_app/fabula_modules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid connection never appears in bottom navigation', () {
    expect(
      fabulaNavigationSectionIds({
        companionModuleId,
        cycleModuleId,
        connectionModuleId,
        compatibilityModuleId,
      }),
      ['today', 'companion', 'cycle', 'compatibility', 'profile'],
    );

    expect(
      fabulaNavigationSectionIds({companionModuleId, connectionModuleId}),
      ['today', 'companion', 'profile'],
    );

    expect(fabulaNavigationSectionIds({}), ['today', 'profile']);
  });
}
