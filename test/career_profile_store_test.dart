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

  test('vacancies are scored from role, skills and salary facts', () {
    const profile = CareerProfile(
      targetRole: 'Project Manager',
      skills: 'Agile, управление командой, продажи',
      minimumSalary: 150000,
    );
    final strong = CareerMatch.evaluate(
      const CareerVacancy(
        id: '1',
        title: 'Project Manager',
        company: 'Example',
        url: '',
        salary: 'от 180000 RUR',
        area: 'Москва',
        requirement: 'Agile, управление командой и продажи',
        salaryFrom: 180000,
      ),
      profile,
    );
    final weak = CareerMatch.evaluate(
      const CareerVacancy(
        id: '2',
        title: 'Стажёр аналитик',
        company: 'Example',
        url: '',
        salary: 'до 90000 RUR',
        area: 'Москва',
        requirement: 'Excel',
        salaryTo: 90000,
      ),
      profile,
    );

    expect(strong.score, 100);
    expect(weak.score, 0);
    expect(strong.reasons.join(' '), contains('зарплата соответствует'));
  });

  test('stop factors inspect vacancy snippets, not only the title', () {
    const vacancy = CareerVacancy(
      id: '1',
      title: 'Менеджер проекта',
      company: 'Example',
      url: '',
      salary: 'Зарплата не указана',
      area: 'Москва',
      responsibility: 'В обязанности входят холодные звонки.',
    );

    expect(vacancy.searchableText, contains('холодные звонки'));
  });
}
