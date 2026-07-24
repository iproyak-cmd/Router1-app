import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _burgundy = Color(0xFF7A3045);
const _muted = Color(0xFF6F6B67);
const _line = Color(0xFFE5DED7);

class CareerVacancy {
  const CareerVacancy({
    required this.id,
    required this.title,
    required this.company,
    required this.url,
    required this.salary,
    required this.area,
  });

  final String id;
  final String title;
  final String company;
  final String url;
  final String salary;
  final String area;

  factory CareerVacancy.fromJson(Map<String, dynamic> json) {
    final employer = json['employer'];
    final area = json['area'];
    final salary = json['salary'];
    String salaryText = 'Зарплата не указана';
    if (salary is Map<String, dynamic>) {
      final from = salary['from'];
      final to = salary['to'];
      final currency = (salary['currency'] ?? '').toString();
      if (from != null && to != null) {
        salaryText = '$from–$to $currency';
      } else if (from != null) {
        salaryText = 'от $from $currency';
      } else if (to != null) {
        salaryText = 'до $to $currency';
      }
    }
    return CareerVacancy(
      id: (json['id'] ?? '').toString(),
      title: (json['name'] ?? 'Вакансия').toString(),
      company: employer is Map ? (employer['name'] ?? '').toString() : '',
      url: (json['alternate_url'] ?? '').toString(),
      salary: salaryText,
      area: area is Map ? (area['name'] ?? '').toString() : '',
    );
  }
}

class ApplicationDraft {
  const ApplicationDraft({
    required this.resumeFocus,
    required this.coverLetter,
  });

  final String resumeFocus;
  final String coverLetter;

  factory ApplicationDraft.fromJson(Map<String, dynamic> json) =>
      ApplicationDraft(
        resumeFocus: (json['resume_focus'] ?? '').toString(),
        coverLetter: (json['cover_letter'] ?? '').toString(),
      );
}

class CareerApi {
  CareerApi({this.baseUrl = 'https://router1.tech/api'});

  final String baseUrl;

  Future<bool> connected(String installationId) async {
    final payload = await _get(
      '/career/hh/status',
      {'installation_id': installationId},
    );
    return payload['connected'] == true;
  }

  Uri loginUri(String installationId) => Uri.parse(
        '$baseUrl/auth/hh/login',
      ).replace(queryParameters: {'installation_id': installationId});

  Future<List<CareerVacancy>> vacancies(
    String installationId,
    String text,
  ) async {
    final payload = await _get('/career/hh/vacancies', {
      'installation_id': installationId,
      'text': text,
      'area': '113',
      'page': '0',
      'per_page': '20',
    });
    final items = payload['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => CareerVacancy.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<ApplicationDraft> prepareApplication({
    required String installationId,
    required CareerVacancy vacancy,
    required String experience,
  }) async {
    final payload = await _post('/career/applications/draft', {
      'installation_id': installationId,
      'vacancy_id': vacancy.id,
      'vacancy_title': vacancy.title,
      'company': vacancy.company,
      'experience': experience,
    });
    return ApplicationDraft.fromJson(payload);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Career API returned ${response.statusCode}');
      }
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Career API returned invalid JSON');
      }
      return payload;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Career API returned ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Career API returned invalid JSON');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}

class CareerPage extends StatefulWidget {
  const CareerPage({
    super.key,
    required this.installationId,
    this.api,
  });

  final String installationId;
  final CareerApi? api;

  @override
  State<CareerPage> createState() => _CareerPageState();
}

class _CareerPageState extends State<CareerPage>
    with WidgetsBindingObserver {
  late final CareerApi api;
  final query = TextEditingController(text: 'Project Manager');
  bool loading = true;
  bool connected = false;
  String error = '';
  List<CareerVacancy> vacancies = const [];

  @override
  void initState() {
    super.initState();
    api = widget.api ?? CareerApi();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    query.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await api.connected(widget.installationId);
      if (!mounted) return;
      setState(() => connected = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => error = 'Не удалось связаться с модулем карьеры.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _connect() async {
    final opened = await launchUrl(
      api.loginUri(widget.installationId),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() => error = 'Не удалось открыть авторизацию HH.');
    }
  }

  Future<void> _search() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await api.vacancies(
        widget.installationId,
        query.text.trim(),
      );
      if (!mounted) return;
      setState(() => vacancies = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => error = 'Не удалось загрузить вакансии. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 840,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
            children: [
              const Text(
                'КАРЬЕРА',
                style: TextStyle(
                  color: _burgundy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Вакансии, на которые стоит откликнуться',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 30,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 18),
              _panel(
                child: loading && !connected
                    ? const Center(child: CircularProgressIndicator())
                    : connected
                        ? const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.check_circle, color: Colors.green),
                            title: Text('HeadHunter подключён'),
                            subtitle: Text('Можно загружать реальные вакансии'),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Подключите HeadHunter',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 7),
                              const Text(
                                'Авторизация откроется в браузере. Fabula не получает ваш пароль.',
                                style: TextStyle(color: _muted, height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _connect,
                                child: const Text('Подключить HH'),
                              ),
                            ],
                          ),
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(error, style: const TextStyle(color: _burgundy)),
              ],
              if (connected) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    labelText: 'Желаемая должность',
                    hintText: 'Например, Project Manager',
                    suffixIcon: IconButton(
                      onPressed: loading ? null : _search,
                      icon: const Icon(Icons.search),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (loading)
                  const Center(child: CircularProgressIndicator())
                else if (vacancies.isEmpty)
                  const Text(
                    'Введите должность и нажмите поиск.',
                    style: TextStyle(color: _muted),
                  )
                else
                  for (final vacancy in vacancies) ...[
                    _VacancyCard(
                      vacancy: vacancy,
                      onPrepare: () => _prepare(vacancy),
                    ),
                    const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );

  Future<void> _prepare(CareerVacancy vacancy) async {
    final experience = await showDialog<String>(
      context: context,
      builder: (context) => const _ExperienceDialog(),
    );
    if (!mounted || experience == null || experience.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      final draft = await api.prepareApplication(
        installationId: widget.installationId,
        vacancy: vacancy,
        experience: experience.trim(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _DraftDialog(draft: draft, vacancy: vacancy),
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Не удалось подготовить отклик. Попробуйте ещё раз.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

Widget _panel({required Widget child}) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
      ),
      child: child,
    );

class _VacancyCard extends StatelessWidget {
  const _VacancyCard({required this.vacancy, required this.onPrepare});

  final CareerVacancy vacancy;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vacancy.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              [vacancy.company, vacancy.area].where((e) => e.isNotEmpty).join(' · '),
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 8),
            Text(
              vacancy.salary,
              style: const TextStyle(
                color: _burgundy,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: vacancy.url.isEmpty
                      ? null
                      : () => launchUrl(
                            Uri.parse(vacancy.url),
                            mode: LaunchMode.externalApplication,
                          ),
                  child: const Text('Открыть на HH'),
                ),
                FilledButton.tonal(
                  onPressed: onPrepare,
                  child: const Text('Подготовить отклик'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ExperienceDialog extends StatefulWidget {
  const _ExperienceDialog();

  @override
  State<_ExperienceDialog> createState() => _ExperienceDialogState();
}

class _ExperienceDialogState extends State<_ExperienceDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Релевантный опыт'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 5,
            maxLines: 10,
            autofocus: true,
            decoration: const InputDecoration(
              hintText:
                  'Напишите только реальные должности, задачи и измеримые результаты.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Подготовить'),
          ),
        ],
      );
}

class _DraftDialog extends StatelessWidget {
  const _DraftDialog({required this.draft, required this.vacancy});

  final ApplicationDraft draft;
  final CareerVacancy vacancy;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Отклик подготовлен'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Акцент резюме',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SelectableText(draft.resumeFocus),
                const SizedBox(height: 18),
                const Text(
                  'Сопроводительное письмо',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SelectableText(draft.coverLetter),
                const SizedBox(height: 14),
                const Text(
                  'Ничего не отправлено. Проверьте факты перед переходом на HH.',
                  style: TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: vacancy.url.isEmpty
                ? null
                : () => launchUrl(
                      Uri.parse(vacancy.url),
                      mode: LaunchMode.externalApplication,
                    ),
            child: const Text('Одобрить и открыть HH'),
          ),
        ],
      );
}
