import 'package:fabula_app/career_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('structured career profile is saved and restored', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CareerProfileStore();

    await store.save(const CareerProfile(
      targetRole: 'Project Manager',
      experience: 'Управлял командой из 12 человек.',
      skills: 'Продажи, управление',
      achievements: 'Рост выручки с 2 до 12 млн ₽/мес',
      minimumSalary: 150000,
      stopFactors: 'стажировка, холодные звонки',
    ));

    final profile = await store.load();
    expect(profile.targetRole, 'Project Manager');
    expect(profile.minimumSalary, 150000);
    expect(profile.excludedTerms, ['стажировка', 'холодные звонки']);
    expect(profile.applicationContext, contains('Рост выручки'));
  });

  test('legacy experience is migrated without data loss', () async {
    SharedPreferences.setMockInitialValues({
      'career_profile_experience': '  Управлял командой из 12 человек.  ',
    });

    final profile = await CareerProfileStore().load();

    expect(profile.experience, 'Управлял командой из 12 человек.');
  });
}
