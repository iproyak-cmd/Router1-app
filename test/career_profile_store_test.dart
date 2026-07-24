import 'package:fabula_app/career_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('career profile experience is saved and restored', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CareerProfileStore();

    await store.saveExperience('  Управлял командой из 12 человек.  ');

    expect(
      await store.loadExperience(),
      'Управлял командой из 12 человек.',
    );
  });
}
