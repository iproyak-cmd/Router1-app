import 'package:fabula_app/career_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('vacancy pipeline persists vacancy details and stage', () async {
    final store = VacancyPipelineStore();
    const vacancy = CareerVacancy(
      id: '123',
      title: 'Project Manager',
      company: 'Fabula',
      url: 'https://hh.ru/vacancy/123',
      salary: 'от 180000 RUR',
      area: 'Санкт-Петербург',
      requirement: 'Управление командой',
      responsibility: 'Запуск продукта',
      salaryFrom: 180000,
    );

    await store.save({
      vacancy.id: const TrackedVacancy(
        vacancy: vacancy,
        stage: VacancyStage.interview,
      ),
    });

    final restored = await store.load();
    expect(restored.keys, ['123']);
    expect(restored['123']?.stage, VacancyStage.interview);
    expect(restored['123']?.vacancy.title, 'Project Manager');
    expect(restored['123']?.vacancy.company, 'Fabula');
    expect(restored['123']?.vacancy.salaryFrom, 180000);
  });

  test('vacancy pipeline ignores corrupted local data', () async {
    SharedPreferences.setMockInitialValues({
      'career_vacancy_pipeline_v1': '{broken',
    });

    expect(await VacancyPipelineStore().load(), isEmpty);
  });
}
