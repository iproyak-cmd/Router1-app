import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _burgundy = Color(0xFF7A3045);
const _muted = Color(0xFF6F6B67);
const _line = Color(0xFFE5DED7);

class CareerProfileStore {
  static const _profileKey = 'career_profile_v2';
  static const _experienceKey = 'career_profile_experience';

  Future<CareerProfile> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_profileKey);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map<String, dynamic>) {
          return CareerProfile.fromJson(decoded);
        }
      } on FormatException {
        // Fall back to the legacy value if local preferences were corrupted.
      }
    }
    return CareerProfile(
      experience: preferences.getString(_experienceKey)?.trim() ?? '',
    );
  }

  Future<void> save(CareerProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_profileKey, jsonEncode(profile.toJson()));
    await preferences.remove(_experienceKey);
  }
}

class CareerProfile {
  const CareerProfile({
    this.targetRole = '',
    this.experience = '',
    this.skills = '',
    this.achievements = '',
    this.minimumSalary = 0,
    this.stopFactors = '',
  });

  final String targetRole;
  final String experience;
  final String skills;
  final String achievements;
  final int minimumSalary;
  final String stopFactors;

  bool get isEmpty =>
      targetRole.isEmpty &&
      experience.isEmpty &&
      skills.isEmpty &&
      achievements.isEmpty &&
      minimumSalary == 0 &&
      stopFactors.isEmpty;

  String get applicationContext => [
        if (experience.isNotEmpty) 'Опыт:\n$experience',
        if (skills.isNotEmpty) 'Ключевые навыки:\n$skills',
        if (achievements.isNotEmpty) 'Измеримые достижения:\n$achievements',
      ].join('\n\n');

  List<String> get excludedTerms => stopFactors
      .split(RegExp(r'[,;\n]'))
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  factory CareerProfile.fromJson(Map<String, dynamic> json) => CareerProfile(
        targetRole: (json['target_role'] ?? '').toString().trim(),
        experience: (json['experience'] ?? '').toString().trim(),
        skills: (json['skills'] ?? '').toString().trim(),
        achievements: (json['achievements'] ?? '').toString().trim(),
        minimumSalary: int.tryParse('${json['minimum_salary'] ?? 0}') ?? 0,
        stopFactors: (json['stop_factors'] ?? '').toString().trim(),
      );

  Map<String, dynamic> toJson() => {
        'target_role': targetRole.trim(),
        'experience': experience.trim(),
        'skills': skills.trim(),
        'achievements': achievements.trim(),
        'minimum_salary': minimumSalary,
        'stop_factors': stopFactors.trim(),
      };
}

class CareerVacancy {
  const CareerVacancy({
    required this.id,
    required this.title,
    required this.company,
    required this.url,
    required this.salary,
    required this.area,
    this.requirement = '',
    this.responsibility = '',
    this.salaryFrom,
    this.salaryTo,
  });

  final String id;
  final String title;
  final String company;
  final String url;
  final String salary;
  final String area;
  final String requirement;
  final String responsibility;
  final int? salaryFrom;
  final int? salaryTo;

  String get searchableText =>
      '$title $company $requirement $responsibility'.toLowerCase();

  factory CareerVacancy.fromJson(Map<String, dynamic> json) {
    final employer = json['employer'];
    final area = json['area'];
    final salary = json['salary'];
    final snippet = json['snippet'];
    String salaryText = 'Зарплата не указана';
    int? salaryFrom;
    int? salaryTo;
    if (salary is Map<String, dynamic>) {
      final from = salary['from'];
      final to = salary['to'];
      salaryFrom = from is num ? from.round() : int.tryParse('$from');
      salaryTo = to is num ? to.round() : int.tryParse('$to');
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
      requirement: snippet is Map
          ? (snippet['requirement'] ?? '').toString().replaceAll(RegExp('<[^>]*>'), '')
          : '',
      responsibility: snippet is Map
          ? (snippet['responsibility'] ?? '')
              .toString()
              .replaceAll(RegExp('<[^>]*>'), '')
          : '',
      salaryFrom: salaryFrom,
      salaryTo: salaryTo,
    );
  }
}

class CareerMatch {
  const CareerMatch({
    required this.vacancy,
    required this.score,
    required this.reasons,
  });

  final CareerVacancy vacancy;
  final int score;
  final List<String> reasons;

  static CareerMatch evaluate(CareerVacancy vacancy, CareerProfile profile) {
    final text = vacancy.searchableText;
    final roleTokens = _tokens(profile.targetRole);
    final matchedRole = roleTokens.where(text.contains).length;
    final roleScore = roleTokens.isEmpty
        ? 0
        : (45 * matchedRole / roleTokens.length).round();

    final skills = profile.skills
        .split(RegExp(r'[,;\n]'))
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.length > 1)
        .toSet();
    final matchedSkills = skills.where(text.contains).toList(growable: false);
    final skillScore =
        skills.isEmpty ? 0 : (40 * matchedSkills.length / skills.length).round();

    var salaryScore = 0;
    String salaryReason;
    if (profile.minimumSalary <= 0) {
      salaryReason = 'зарплатный порог не задан';
    } else if (vacancy.salaryFrom == null && vacancy.salaryTo == null) {
      salaryScore = 5;
      salaryReason = 'зарплата не указана';
    } else {
      final upperBound = vacancy.salaryTo ?? vacancy.salaryFrom ?? 0;
      if (upperBound >= profile.minimumSalary) {
        salaryScore = 15;
        salaryReason = 'зарплата соответствует';
      } else {
        salaryReason = 'зарплата ниже ожиданий';
      }
    }

    final reasons = <String>[
      roleTokens.isEmpty
          ? 'целевая должность не задана'
          : matchedRole == 0
              ? 'название должности не совпало'
              : 'совпадение по должности: $matchedRole из ${roleTokens.length}',
      skills.isEmpty
          ? 'навыки не заданы'
          : matchedSkills.isEmpty
              ? 'совпадений по навыкам не найдено'
              : 'навыки: ${matchedSkills.take(3).join(', ')}',
      salaryReason,
    ];

    return CareerMatch(
      vacancy: vacancy,
      score: (roleScore + skillScore + salaryScore).clamp(0, 100).toInt(),
      reasons: reasons,
    );
  }

  static Set<String> _tokens(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-zа-яё0-9+#]+', caseSensitive: false))
      .where((token) => token.length > 2)
      .toSet();
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
    int minimumSalary,
  ) async {
    final payload = await _get('/career/hh/vacancies', {
      'installation_id': installationId,
      'text': text,
      if (minimumSalary > 0) 'salary': '$minimumSalary',
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
    this.profileStore,
  });

  final String installationId;
  final CareerApi? api;
  final CareerProfileStore? profileStore;

  @override
  State<CareerPage> createState() => _CareerPageState();
}

class _CareerPageState extends State<CareerPage>
    with WidgetsBindingObserver {
  late final CareerApi api;
  late final CareerProfileStore profileStore;
  final query = TextEditingController(text: 'Project Manager');
  bool loading = true;
  bool connected = false;
  String error = '';
  CareerProfile profile = const CareerProfile();
  List<CareerMatch> vacancies = const [];

  @override
  void initState() {
    super.initState();
    api = widget.api ?? CareerApi();
    profileStore = widget.profileStore ?? CareerProfileStore();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
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

  Future<void> _loadProfile() async {
    final saved = await profileStore.load();
    if (!mounted) return;
    setState(() {
      profile = saved;
      if (saved.targetRole.isNotEmpty) query.text = saved.targetRole;
    });
  }

  Future<void> _editProfile() async {
    final updated = await showDialog<CareerProfile>(
      context: context,
      builder: (context) => _ProfileDialog(initialValue: profile),
    );
    if (!mounted || updated == null) return;
    await profileStore.save(updated);
    if (mounted) {
      setState(() {
        profile = updated;
        if (updated.targetRole.isNotEmpty) query.text = updated.targetRole;
      });
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
        profile.minimumSalary,
      );
      if (!mounted) return;
      final excluded = profile.excludedTerms;
      final ranked = result
          .where((vacancy) =>
              !excluded.any((term) => vacancy.searchableText.contains(term)))
          .map((vacancy) => CareerMatch.evaluate(vacancy, profile))
          .toList();
      ranked.sort((left, right) => right.score.compareTo(left.score));
      setState(
        () => vacancies = List<CareerMatch>.unmodifiable(ranked),
      );
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
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Профессиональный профиль',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        profile.isEmpty
                            ? 'Заполните профиль один раз — Fabula настроит поиск и будет подставлять факты в отклики.'
                            : [
                                if (profile.targetRole.isNotEmpty)
                                  profile.targetRole,
                                if (profile.skills.isNotEmpty) profile.skills,
                                if (profile.minimumSalary > 0)
                                  'от ${profile.minimumSalary} ₽',
                              ].join(' · '),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _editProfile,
                        icon: Icon(profile.isEmpty ? Icons.add : Icons.edit),
                        label: Text(
                          profile.isEmpty ? 'Заполнить профиль' : 'Изменить',
                        ),
                      ),
                    ],
                  ),
                ),
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
                  for (final match in vacancies) ...[
                    _VacancyCard(
                      match: match,
                      onPrepare: () => _prepare(match.vacancy),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ],
          ),
        ),
      );

  Future<void> _prepare(CareerVacancy vacancy) async {
    final selectedExperience = await showDialog<String>(
      context: context,
      builder: (context) => _ExperienceDialog(
        initialValue: profile.applicationContext,
        title: profile.applicationContext.isEmpty
            ? 'Релевантный опыт'
            : 'Проверьте факты',
        actionLabel: 'Подготовить',
      ),
    );
    if (!mounted ||
        selectedExperience == null ||
        selectedExperience.trim().isEmpty) {
      return;
    }
    final normalizedExperience = selectedExperience.trim();
    setState(() => loading = true);
    try {
      final draft = await api.prepareApplication(
        installationId: widget.installationId,
        vacancy: vacancy,
        experience: normalizedExperience,
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
  const _VacancyCard({required this.match, required this.onPrepare});

  final CareerMatch match;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    final vacancy = match.vacancy;
    final matchColor = match.score >= 70
        ? Colors.green.shade700
        : match.score >= 45
            ? Colors.orange.shade800
            : _muted;
    return _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 17, color: matchColor),
                const SizedBox(width: 6),
                Text(
                  'Совпадение ${match.score}%',
                  style: TextStyle(
                    color: matchColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
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
            const SizedBox(height: 8),
            Text(
              match.reasons.join(' · '),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
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
}

class _ExperienceDialog extends StatefulWidget {
  const _ExperienceDialog({
    required this.initialValue,
    required this.title,
    required this.actionLabel,
  });

  final String initialValue;
  final String title;
  final String actionLabel;

  @override
  State<_ExperienceDialog> createState() => _ExperienceDialogState();
}

class _ExperienceDialogState extends State<_ExperienceDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
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
            child: Text(widget.actionLabel),
          ),
        ],
      );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.initialValue});

  final CareerProfile initialValue;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController role;
  late final TextEditingController experience;
  late final TextEditingController skills;
  late final TextEditingController achievements;
  late final TextEditingController salary;
  late final TextEditingController stopFactors;

  @override
  void initState() {
    super.initState();
    final value = widget.initialValue;
    role = TextEditingController(text: value.targetRole);
    experience = TextEditingController(text: value.experience);
    skills = TextEditingController(text: value.skills);
    achievements = TextEditingController(text: value.achievements);
    salary = TextEditingController(
      text: value.minimumSalary == 0 ? '' : '${value.minimumSalary}',
    );
    stopFactors = TextEditingController(text: value.stopFactors);
  }

  @override
  void dispose() {
    for (final controller in [
      role,
      experience,
      skills,
      achievements,
      salary,
      stopFactors,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Профессиональный профиль'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _field(role, 'Целевая должность', 'Project Manager'),
                _field(
                  experience,
                  'Опыт',
                  'Компании, роли и реальные задачи',
                  lines: 4,
                ),
                _field(skills, 'Навыки', 'Управление командой, продажи, Agile'),
                _field(
                  achievements,
                  'Измеримые достижения',
                  'Например: увеличил выручку с 2 до 12 млн ₽/мес',
                  lines: 3,
                ),
                _field(
                  salary,
                  'Минимальная зарплата, ₽',
                  '150000',
                  keyboardType: TextInputType.number,
                ),
                _field(
                  stopFactors,
                  'Стоп-факторы',
                  'Стажировка, холодные звонки, конкретная компания',
                  lines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              CareerProfile(
                targetRole: role.text.trim(),
                experience: experience.text.trim(),
                skills: skills.text.trim(),
                achievements: achievements.text.trim(),
                minimumSalary: int.tryParse(
                      salary.text.replaceAll(RegExp(r'\D'), ''),
                    ) ??
                    0,
                stopFactors: stopFactors.text.trim(),
              ),
            ),
            child: const Text('Сохранить'),
          ),
        ],
      );

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int lines = 1,
    TextInputType? keyboardType,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          minLines: lines,
          maxLines: lines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
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
