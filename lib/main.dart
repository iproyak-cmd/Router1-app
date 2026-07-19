import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'fabula_modules.dart';
import 'models/menstrual_cycle.dart';
import 'router1_api.dart';
import 'services/awg_tunnel_service.dart';

const fabulaVersion = '0.4.0+10';
const _burgundy = Color(0xFF7A3045);
const _cream = Color(0xFFF6F2ED);
const _ink = Color(0xFF171717);
const _muted = Color(0xFF6F6B67);
const _sage = Color(0xFFA7B3A4);
const _line = Color(0xFFE5DED7);

const zodiacSigns = <(String, String, String)>[
  ('aries', 'Овен', '♈'),
  ('taurus', 'Телец', '♉'),
  ('gemini', 'Близнецы', '♊'),
  ('cancer', 'Рак', '♋'),
  ('leo', 'Лев', '♌'),
  ('virgo', 'Дева', '♍'),
  ('libra', 'Весы', '♎'),
  ('scorpio', 'Скорпион', '♏'),
  ('sagittarius', 'Стрелец', '♐'),
  ('capricorn', 'Козерог', '♑'),
  ('aquarius', 'Водолей', '♒'),
  ('pisces', 'Рыбы', '♓'),
];

const _moduleCatalog = <({String id, String title, String subtitle})>[
  (id: 'day', title: 'Ваш день', subtitle: 'Цвет, число и энергия дня'),
  (id: 'tarot', title: 'Таро', subtitle: 'Карта дня и полное толкование'),
  (
    id: 'horoscope',
    title: 'Гороскоп',
    subtitle: 'Подробный прогноз по вашему знаку',
  ),
  (id: 'lunar', title: 'Лунный ритм', subtitle: 'Фаза Луны и рекомендация дня'),
  (
    id: 'compatibility',
    title: 'Совместимость',
    subtitle: 'Разбор пары по знакам',
  ),
  (
    id: 'affirmation',
    title: 'Аффирмация',
    subtitle: 'Личная мысль и опора дня',
  ),
  (id: 'mood', title: 'Настроение', subtitle: 'Эмоциональный ритм дня'),
  (id: 'look', title: 'Образ дня', subtitle: 'Вдохновение, цвета и детали'),
  (
    id: 'journal',
    title: 'Личный дневник',
    subtitle: 'Приватные заметки для себя',
  ),
  (
    id: 'connection',
    title: 'Подключение',
    subtitle: 'Защищённый доступ Fabula',
  ),
  (
    id: 'cycle',
    title: 'Цикл',
    subtitle: 'Личный календарь и бережные подсказки',
  ),
];

void main() => runApp(const FabulaApp());

class FabulaApp extends StatelessWidget {
  const FabulaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Fabula',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _cream,
      fontFamily: 'Manrope',
      colorScheme: ColorScheme.fromSeed(
        seedColor: _burgundy,
        brightness: Brightness.light,
        surface: _cream,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _burgundy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      ),
    ),
    home: const FabulaShell(),
  );
}

class FabulaShell extends StatefulWidget {
  const FabulaShell({super.key});
  @override
  State<FabulaShell> createState() => _FabulaShellState();
}

class _FabulaShellState extends State<FabulaShell> {
  final api = Router1Api(
    baseUrl: 'https://router1.tech/api',
    token: const String.fromEnvironment('ROUTER1_APP_TOKEN'),
    demoFallback: true,
  );
  final tunnel = AwgTunnelService();
  String section = 'today';
  var loading = true;
  var vpnBusy = false;
  String name = '';
  String phone = '';
  String birthday = '';
  String sign = 'libra';
  String journalEntry = '';
  Set<String> enabledModules = _moduleCatalog.map((item) => item.id).toSet();
  CycleSettings? cycle;
  Router1DailyHoroscope? forecast;
  AwgTunnelStatus vpn = const AwgTunnelStatus(state: 'down');
  Future<Router1ClientLookup>? vpnAccessPreparation;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    timer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshVpn()),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('fabula_name') ?? '';
    phone = prefs.getString('fabula_phone') ?? '';
    birthday = prefs.getString('fabula_birthday') ?? '';
    sign = prefs.getString('fabula_sign') ?? 'libra';
    journalEntry = prefs.getString('fabula_journal_entry') ?? '';
    final savedModules = prefs.getStringList('fabula_enabled_modules');
    if (savedModules != null) {
      enabledModules = savedModules.toSet();
      if ((prefs.getInt('fabula_modules_schema') ?? 1) < 2) {
        enabledModules.add('cycle');
        await prefs.setStringList(
          'fabula_enabled_modules',
          _moduleCatalog
              .where((item) => enabledModules.contains(item.id))
              .map((item) => item.id)
              .toList(growable: false),
        );
      }
    }
    await prefs.setInt('fabula_modules_schema', 2);
    final cycleStart = prefs.getString('fabula_cycle_start');
    final parsedCycleStart = cycleStart == null
        ? null
        : DateTime.tryParse(cycleStart);
    if (parsedCycleStart != null) {
      cycle = CycleSettings(
        lastPeriodStart: parsedCycleStart,
        cycleLength: prefs.getInt('fabula_cycle_length') ?? 28,
        periodLength: prefs.getInt('fabula_period_length') ?? 5,
      );
    }
    await Future.wait([_loadForecast(), _refreshVpn()]);
    if (mounted) setState(() => loading = false);
    unawaited(_trackEvent('app_opened'));
    if (phone.isNotEmpty) unawaited(_warmVpnAccess());
  }

  Future<void> _loadForecast() async {
    try {
      final v = await api.dailyHoroscope(sign);
      if (v.tarotTitle.trim().isEmpty || v.tarotMeaning.trim().isEmpty) {
        throw const FormatException('incomplete_daily_content');
      }
      if (mounted) setState(() => forecast = v);
    } catch (_) {
      if (mounted) setState(() => forecast = _demoForecast(sign));
    }
  }

  Future<void> _refreshVpn() async {
    try {
      final v = await tunnel.status();
      if (mounted) setState(() => vpn = v);
    } catch (_) {}
  }

  Future<void> _toggleVpn() async {
    if (vpnBusy) return;
    if (phone.trim().isEmpty) {
      await _editProfile(requirePhone: true);
      return;
    }
    setState(() => vpnBusy = true);
    try {
      if (vpn.connected) {
        vpn = await tunnel.disconnect();
      } else {
        final lookup = await _ensureVpnAccess();
        final available = _fabulaConfigs(lookup);
        final candidates = available.where((c) {
          final text = '${c.productType} ${c.deviceName}'.toLowerCase();
          return Platform.isWindows
              ? text.contains('windows') ||
                    text.contains('pc') ||
                    text.contains('пк')
              : text.contains('android') ||
                    text.contains('smartphone') ||
                    text.contains('смартфон');
        }).toList();
        final config = candidates.isNotEmpty
            ? candidates.first
            : (available.isNotEmpty ? available.first : null);
        if (config == null) throw const FormatException('no_config');
        final text = await api.fetchClientConfigText(
          phone: phone,
          deviceId: config.id,
        );
        await tunnel.prepare();
        vpn = await tunnel.connect(text, serverCode: config.serverCode);
        unawaited(
          _trackEvent(
            'vpn_connected',
            details: {'server_code': config.serverCode},
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Не удалось подготовить подключение. Повторите через минуту.',
            ),
            action: SnackBarAction(label: 'Повторить', onPressed: _toggleVpn),
          ),
        );
    } finally {
      if (mounted) setState(() => vpnBusy = false);
    }
  }

  Future<Router1ClientLookup> _ensureVpnAccess() {
    final current = vpnAccessPreparation;
    if (current != null) return current;
    final future = _lookupOrCreateTrial();
    vpnAccessPreparation = future;
    return future.whenComplete(() {
      if (identical(vpnAccessPreparation, future)) vpnAccessPreparation = null;
    });
  }

  Future<void> _warmVpnAccess() async {
    try {
      await _ensureVpnAccess();
    } catch (_) {
      // The visible VPN button retries; onboarding must not be blocked by network.
    }
  }

  Future<Router1ClientLookup> _lookupOrCreateTrial() async {
    final deviceType = Platform.isWindows ? 'laptop_test' : 'smartphone_test';
    try {
      final current = await api.findClientByPhone(
        phone,
        deviceType: deviceType,
      );
      if (_fabulaConfigs(current).isNotEmpty) return current;
    } catch (_) {}
    await api.createFabulaAccess(product: deviceType, name: name, phone: phone);
    for (var attempt = 0; attempt < 45; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final lookup = await api.findClientByPhone(
          phone,
          deviceType: deviceType,
        );
        if (_fabulaConfigs(lookup).isNotEmpty) return lookup;
      } catch (_) {}
    }
    throw const FormatException('config_generation_timeout');
  }

  List<Router1ClientConfig> _fabulaConfigs(Router1ClientLookup lookup) => lookup
      .configs
      .where((config) {
        final status = config.status.toLowerCase();
        return !config.routerCandidate &&
            config.hasConfig &&
            !const {
              'blocked',
              'disabled',
              'expired',
              'revoked',
            }.contains(status);
      })
      .toList(growable: false);

  Future<void> _chooseSign() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _cream,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ваш знак',
                style: TextStyle(fontFamily: 'serif', fontSize: 28),
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 1.55,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: zodiacSigns
                    .map(
                      (z) => OutlinedButton(
                        onPressed: () => Navigator.pop(context, z.$1),
                        child: Text('${z.$3} ${z.$2}'),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (value == null) return;
    sign = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fabula_sign', value);
    if (mounted) setState(() => forecast = null);
    await _loadForecast();
  }

  Future<void> _editProfile({bool requirePhone = false}) async {
    final nameController = TextEditingController(text: name);
    final phoneController = TextEditingController(text: phone);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cream,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Профиль Fabula',
              style: TextStyle(fontFamily: 'serif', fontSize: 30),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Имя (необязательно)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Телефон${requirePhone ? ' для подключения' : ''}',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    name = nameController.text.trim();
    phone = phoneController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fabula_name', name);
    await prefs.setString('fabula_phone', phone);
    vpnAccessPreparation = null;
    unawaited(_warmVpnAccess());
    if (mounted) setState(() {});
  }

  Future<void> _completeOnboarding(
    String valueName,
    String valuePhone,
    DateTime valueBirthday,
  ) async {
    name = valueName.trim();
    phone = valuePhone.trim();
    birthday =
        '${valueBirthday.year.toString().padLeft(4, '0')}-'
        '${valueBirthday.month.toString().padLeft(2, '0')}-'
        '${valueBirthday.day.toString().padLeft(2, '0')}';
    sign = _zodiacFor(valueBirthday.month, valueBirthday.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fabula_name', name);
    await prefs.setString('fabula_phone', phone);
    await prefs.setString('fabula_birthday', birthday);
    await prefs.setString('fabula_sign', sign);
    if (mounted)
      setState(() {
        forecast = null;
      });
    await _loadForecast();
    unawaited(_warmVpnAccess());
  }

  Future<void> _saveCycle(CycleSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'fabula_cycle_start',
      value.lastPeriodStart.toIso8601String().substring(0, 10),
    );
    await prefs.setInt('fabula_cycle_length', value.cycleLength);
    await prefs.setInt('fabula_period_length', value.periodLength);
    if (mounted) setState(() => cycle = value);
  }

  Future<void> _editJournal() async {
    final controller = TextEditingController(text: journalEntry);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cream,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _editorial('Личный дневник', size: 28),
            const SizedBox(height: 8),
            const Text(
              'Запись хранится только на этом устройстве.',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              minLines: 5,
              maxLines: 9,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Что хочется сохранить из этого дня?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
    final value = controller.text.trim();
    controller.dispose();
    if (saved != true) return;
    journalEntry = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fabula_journal_entry', journalEntry);
    if (mounted) setState(() {});
  }

  Future<String> _installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString('fabula_installation_id');
    if (current != null && current.isNotEmpty) return current;
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final created = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$random';
    await prefs.setString('fabula_installation_id', created);
    return created;
  }

  Future<void> _trackEvent(
    String event, {
    Map<String, Object?> details = const {},
  }) async {
    try {
      await api.trackFabulaEvent(
        event: event,
        installationId: await _installationId(),
        platform: Platform.operatingSystem,
        appVersion: fabulaVersion,
        phone: phone.trim().isEmpty ? null : phone.trim(),
        details: details,
      );
    } catch (_) {
      // Analytics must never block onboarding or the protected connection.
    }
  }

  Future<void> _toggleModule(String id, bool enabled) async {
    setState(() {
      if (enabled) {
        enabledModules.add(id);
      } else {
        enabledModules.remove(id);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'fabula_enabled_modules',
      _moduleCatalog
          .where((item) => enabledModules.contains(item.id))
          .map((item) => item.id)
          .toList(growable: false),
    );
    await prefs.setInt('fabula_modules_schema', 2);
  }

  Future<void> _openCycle() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CyclePage(initial: cycle, onSave: _saveCycle),
      ),
    );
  }

  Future<void> _share() async {
    final f = forecast;
    if (f == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text:
            '${f.symbol} ${f.signTitle} — сегодня\n\n${f.overview}\n\n'
            'Карта дня: ${f.tarotTitle}\n${f.tarotMeaning}\n\nFabula',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = !loading && name.isNotEmpty && phone.isNotEmpty && birthday.isNotEmpty;
    final visibleNavigation = fabulaNavigationSectionIds(enabledModules);
    final sections = <({String id, Widget page, NavigationDestination destination})>[
      (
        id: 'today',
        page: _TodayPage(
          name: name,
          forecast: forecast,
          enabledModules: enabledModules,
          journalEntry: journalEntry,
          onSign: _chooseSign,
          onShare: _share,
          onJournal: _editJournal,
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome),
          label: 'Сегодня',
        ),
      ),
      if (visibleNavigation.contains(cycleModuleId))
        (
          id: 'cycle',
          page: _CyclePage(initial: cycle, onSave: _saveCycle, embedded: true),
          destination: const NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: 'Цикл',
          ),
        ),
      if (visibleNavigation.contains(connectionModuleId))
        (
          id: 'connection',
          page: _ConnectionPage(vpn: vpn, busy: vpnBusy, onToggle: _toggleVpn),
          destination: const NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'VPN',
          ),
        ),
      if (visibleNavigation.contains(compatibilityModuleId))
        (
          id: 'compatibility',
          page: const _CompatibilityPage(),
          destination: const NavigationDestination(
            icon: Icon(Icons.favorite_border),
            label: 'Пара',
          ),
        ),
      (
        id: 'profile',
        page: _ProfilePage(
          name: name,
          phone: phone,
          sign: sign,
          onEdit: _editProfile,
          enabledModules: enabledModules,
          onModuleChanged: _toggleModule,
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Профиль',
        ),
      ),
    ];
    final currentIndex = sections.indexWhere((item) => item.id == section);
    final selectedIndex = currentIndex < 0 ? 0 : currentIndex;

    return Scaffold(
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : !ready
            ? _OnboardingPage(onComplete: _completeOnboarding)
            : IndexedStack(
                index: selectedIndex,
                children: sections.map((item) => item.page).toList(growable: false),
              ),
      ),
      bottomNavigationBar: !ready
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (value) => setState(() => section = sections[value].id),
              destinations: sections.map((item) => item.destination).toList(growable: false),
            ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: constraints.maxWidth > 840 ? 840 : constraints.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
          children: children,
        ),
      ),
    ),
  );
}

class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({required this.onComplete});
  final Future<void> Function(String, String, DateTime) onComplete;
  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  DateTime? birthday;
  var saving = false;

  Future<void> _save() async {
    if (name.text.trim().isEmpty ||
        phone.text.trim().isEmpty ||
        birthday == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните имя, телефон и дату рождения')),
      );
      return;
    }
    setState(() => saving = true);
    await widget.onComplete(name.text, phone.text, birthday!);
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 36, 28, 30),
    children: [
      Center(
        child: Image.asset('assets/fabula/logo.png', width: 92, height: 92),
      ),
      const SizedBox(height: 20),
      Center(child: _editorial('Добро пожаловать в Fabula', size: 34)),
      const SizedBox(height: 10),
      const Text(
        'Познакомимся, чтобы сделать ежедневные материалы персональными.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, height: 1.45),
      ),
      const SizedBox(height: 28),
      _Card(
        child: Column(
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ваше имя'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Номер телефона'),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата рождения'),
              subtitle: Text(
                birthday == null
                    ? 'Не выбрана'
                    : '${birthday!.day.toString().padLeft(2, '0')}.${birthday!.month.toString().padLeft(2, '0')}.${birthday!.year}',
              ),
              trailing: const Icon(
                Icons.calendar_month_outlined,
                color: _burgundy,
              ),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now(),
                  initialDate: birthday ?? DateTime(1990, 1, 1),
                );
                if (value != null) setState(() => birthday = value);
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? 'Сохраняем...' : 'Продолжить'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Данные используются для персонализации Fabula и подключения сервиса.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 12),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(24)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: _line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

Text _editorial(String text, {double size = 30}) => Text(
  text,
  style: TextStyle(
    fontFamily: 'serif',
    color: _ink,
    fontSize: size,
    height: 1.08,
    fontWeight: FontWeight.w500,
  ),
);

class _TodayPage extends StatelessWidget {
  const _TodayPage({
    required this.name,
    required this.forecast,
    required this.enabledModules,
    required this.journalEntry,
    required this.onSign,
    required this.onShare,
    required this.onJournal,
  });
  final String name;
  final Router1DailyHoroscope? forecast;
  final Set<String> enabledModules;
  final String journalEntry;
  final VoidCallback onSign, onShare, onJournal;

  @override
  Widget build(BuildContext context) {
    final f = forecast ?? _demoForecast('libra');
    final energy = 76 + (f.number * 3) % 19;
    return _Page(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _editorial(
                    name.isEmpty ? 'Доброе утро' : 'Доброе утро, $name',
                    size: 28,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _date(),
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            ClipOval(
              child: Image.asset(
                'assets/fabula/logo.png',
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (enabledModules.contains('look')) ...[
          const _DailyLookCard(),
          const SizedBox(height: 14),
        ],
        if (enabledModules.contains('horoscope')) ...[
          _Card(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionLabel('АСТРОЛОГИЧЕСКИЙ ПРОГНОЗ'),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: onSign,
                            style: TextButton.styleFrom(
                              foregroundColor: _burgundy,
                              padding: EdgeInsets.zero,
                            ),
                            icon: Text(
                              f.symbol,
                              style: const TextStyle(fontSize: 22),
                            ),
                            label: Text(
                              f.signTitle,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 88,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E4E8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$energy%',
                            style: const TextStyle(
                              color: _burgundy,
                              fontFamily: 'serif',
                              fontSize: 27,
                            ),
                          ),
                          const Text(
                            'ЭНЕРГИЯ',
                            style: TextStyle(
                              color: _burgundy,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _editorial(f.overview, size: 25),
                const SizedBox(height: 18),
                _AstroDetail(title: 'ДЕЛА', text: f.work),
                const Divider(height: 26, color: _line),
                _AstroDetail(title: 'ДЕНЬГИ', text: f.money),
                const Divider(height: 26, color: _line),
                _AstroDetail(title: 'ОТНОШЕНИЯ', text: f.love),
                const Divider(height: 26, color: _line),
                _AstroDetail(title: 'СОВЕТ ДНЯ', text: f.advice),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (enabledModules.contains('mood')) ...[
          _Card(
            child: Row(
              children: [
                const Icon(
                  Icons.sentiment_satisfied_alt_outlined,
                  color: _burgundy,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('НАСТРОЕНИЕ ДНЯ'),
                      const SizedBox(height: 6),
                      _editorial(_mood(f.number), size: 22),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (enabledModules.contains('tarot')) ...[
          _Card(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 4, 6, 12),
                  child: _SectionLabel('КАРТА ТАРО НА СЕГОДНЯ'),
                ),
                LayoutBuilder(
                  builder: (context, constraints) => _TarotArtwork(
                    title: f.tarotTitle,
                    width: constraints.maxWidth,
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _editorial(f.tarotTitle, size: 30),
                      const SizedBox(height: 10),
                      Text(
                        f.tarotMeaning,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (enabledModules.contains('day')) ...[
          Row(
            children: [
              Expanded(
                child: _Card(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('ЦВЕТ ДНЯ'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _colorForName(f.color),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                f.color,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Card(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('ЧИСЛО ДНЯ'),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            '${f.number}',
                            style: const TextStyle(
                              color: _burgundy,
                              fontFamily: 'serif',
                              fontSize: 40,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Внимание\nк деталям',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 11,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (enabledModules.contains('lunar')) ...[
          _Card(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8E9DE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.brightness_3_outlined,
                    color: _burgundy,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('ЛУННЫЙ РИТМ'),
                      const SizedBox(height: 6),
                      _editorial(
                        f.lunarPhase.isEmpty ? 'Растущая Луна' : f.lunarPhase,
                        size: 21,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Хороший день, чтобы продолжать начатое и не торопить результат.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (enabledModules.contains('affirmation'))
          _Card(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'АФФИРМАЦИЯ ДНЯ',
                        style: TextStyle(color: _burgundy, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      _editorial(_affirmation(f.number), size: 22),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share, color: _burgundy),
                ),
              ],
            ),
          ),
        if (enabledModules.contains('journal')) ...[
          const SizedBox(height: 12),
          _Card(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.menu_book_outlined, color: _burgundy),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('ЛИЧНЫЙ ДНЕВНИК'),
                      const SizedBox(height: 7),
                      Text(
                        journalEntry.isEmpty
                            ? 'Сохраните мысль, чувство или маленькое открытие этого дня.'
                            : journalEntry,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: onJournal,
                        child: Text(journalEntry.isEmpty ? 'Добавить запись' : 'Изменить'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AstroDetail extends StatelessWidget {
  const _AstroDetail({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionLabel(title),
      const SizedBox(height: 7),
      Text(text, style: const TextStyle(color: _muted, height: 1.45)),
    ],
  );
}

class _DailyLookCard extends StatelessWidget {
  const _DailyLookCard();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(26),
    child: AspectRatio(
      aspectRatio: 1.38,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/fabula/daily-look.webp',
            fit: BoxFit.cover,
            alignment: const Alignment(.5, -.2),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xD9F6F2ED),
                  Color(0x66F6F2ED),
                  Color(0x00000000),
                ],
                stops: [0, .5, .82],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 155,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel('ОБРАЗ ДНЯ'),
                    const SizedBox(height: 8),
                    _editorial('Спокойная уверенность', size: 24),
                    const SizedBox(height: 8),
                    const Text(
                      'Винный оттенок, мягкий беж и одна золотая деталь.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CycleTodayCard extends StatelessWidget {
  const _CycleTodayCard({required this.settings, required this.onTap});

  final CycleSettings? settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final snapshot = settings?.snapshot();
    return _Card(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: Color(0xFFF3E4E8),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.water_drop_outlined,
              color: _burgundy,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('МОЙ ЦИКЛ'),
                const SizedBox(height: 6),
                _editorial(
                  snapshot == null
                      ? 'Добавить цикл'
                      : '${snapshot.cycleDay}-й день цикла',
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  snapshot == null
                      ? 'Календарь, фазы и бережные напоминания'
                      : '${_cyclePhaseTitle(snapshot.phase)} · ${_nextPeriodText(snapshot)}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.chevron_right, color: _burgundy),
            tooltip: snapshot == null ? 'Добавить цикл' : 'Открыть календарь',
          ),
        ],
      ),
    );
  }
}

class _CyclePage extends StatefulWidget {
  const _CyclePage({
    required this.initial,
    required this.onSave,
    this.embedded = false,
  });

  final CycleSettings? initial;
  final Future<void> Function(CycleSettings) onSave;
  final bool embedded;

  @override
  State<_CyclePage> createState() => _CyclePageState();
}

class _CyclePageState extends State<_CyclePage> {
  CycleSettings? settings;
  late DateTime month;

  @override
  void initState() {
    super.initState();
    settings = widget.initial;
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
  }

  Future<void> _edit() async {
    final value = await showModalBottomSheet<CycleSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cream,
      builder: (context) => _CycleSetupSheet(initial: settings),
    );
    if (value == null) return;
    await widget.onSave(value);
    if (mounted) setState(() => settings = value);
  }

  @override
  Widget build(BuildContext context) {
    final value = settings;
    if (widget.embedded) {
      return value == null ? _emptyCycle() : _cycleContent(value);
    }
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Мой цикл'),
        actions: [
          if (value != null)
            TextButton(onPressed: _edit, child: const Text('Изменить')),
        ],
      ),
      body: SafeArea(
        top: false,
        child: value == null ? _emptyCycle() : _cycleContent(value),
      ),
    );
  }

  Widget _emptyCycle() => ListView(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
    children: [
      _editorial('Мой цикл'),
      const SizedBox(height: 24),
      Center(
        child: Container(
          width: 98,
          height: 98,
          decoration: const BoxDecoration(
            color: Color(0xFFF3E4E8),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.water_drop_outlined,
            color: _burgundy,
            size: 44,
          ),
        ),
      ),
      const SizedBox(height: 24),
      Center(child: _editorial('Понимайте свой ритм', size: 31)),
      const SizedBox(height: 12),
      const Text(
        'Отмечайте начало менструации, следите за фазами цикла и планируйте дни с большей заботой о себе.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, height: 1.5),
      ),
      const SizedBox(height: 26),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _CycleBenefit(
              icon: Icons.calendar_month_outlined,
              text: 'Прогноз следующей менструации',
            ),
            SizedBox(height: 18),
            _CycleBenefit(
              icon: Icons.auto_awesome_outlined,
              text: 'Текущая фаза и день цикла',
            ),
            SizedBox(height: 18),
            _CycleBenefit(
              icon: Icons.lock_outline,
              text: 'Данные хранятся только на вашем устройстве',
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      FilledButton(onPressed: _edit, child: const Text('Добавить цикл')),
      const SizedBox(height: 12),
      const Text(
        'Fabula даёт ориентировочный прогноз и не заменяет консультацию врача.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
      ),
    ],
  );

  Widget _cycleContent(CycleSettings value) {
    final snapshot = value.snapshot();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
      children: [
        _editorial('Мой цикл'),
        const SizedBox(height: 18),
        _CycleHero(settings: value, snapshot: snapshot),
        const SizedBox(height: 14),
        _Card(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      _monthTitle(month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 22,
                        color: _ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _CycleCalendar(month: month, settings: value),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _CycleLegend(color: _burgundy, label: 'Менструация'),
                  _CycleLegend(color: _sage, label: 'Фертильные дни'),
                  _CycleLegend(color: Color(0xFFB8A17B), label: 'Овуляция'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('СЕГОДНЯ'),
              const SizedBox(height: 8),
              _editorial(_cyclePhaseTitle(snapshot.phase), size: 25),
              const SizedBox(height: 8),
              Text(
                _cyclePhaseDescription(snapshot.phase),
                style: const TextStyle(color: _muted, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Расчёты основаны на указанных средних значениях. Они не предназначены для контрацепции или медицинской диагностики.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }
}

class _CycleBenefit extends StatelessWidget {
  const _CycleBenefit({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _burgundy, size: 22),
      const SizedBox(width: 13),
      Expanded(
        child: Text(text, style: const TextStyle(color: _ink, height: 1.35)),
      ),
    ],
  );
}

class _CycleHero extends StatelessWidget {
  const _CycleHero({required this.settings, required this.snapshot});
  final CycleSettings settings;
  final CycleSnapshot snapshot;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('ТЕКУЩИЙ ЦИКЛ'),
                  const SizedBox(height: 8),
                  _editorial('${snapshot.cycleDay}-й день', size: 34),
                  const SizedBox(height: 6),
                  Text(
                    _cyclePhaseTitle(snapshot.phase),
                    style: const TextStyle(
                      color: _burgundy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF3E4E8),
                border: Border.all(color: _burgundy.withAlpha(46), width: 7),
              ),
              child: Text(
                '${snapshot.cycleDay}',
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 27,
                  color: _burgundy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            minHeight: 9,
            value: snapshot.cycleDay / settings.cycleLength,
            backgroundColor: const Color(0xFFF1ECE7),
            color: _burgundy,
          ),
        ),
        const SizedBox(height: 12),
        Text(_nextPeriodText(snapshot), style: const TextStyle(color: _muted)),
      ],
    ),
  );
}

class _CycleSetupSheet extends StatefulWidget {
  const _CycleSetupSheet({required this.initial});
  final CycleSettings? initial;

  @override
  State<_CycleSetupSheet> createState() => _CycleSetupSheetState();
}

class _CycleSetupSheetState extends State<_CycleSetupSheet> {
  late DateTime start;
  late int cycleLength;
  late int periodLength;

  @override
  void initState() {
    super.initState();
    start = widget.initial?.lastPeriodStart ?? DateTime.now();
    cycleLength = widget.initial?.cycleLength ?? 28;
    periodLength = widget.initial?.periodLength ?? 5;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      20,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 26,
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _editorial('Настроить цикл', size: 29),
            const SizedBox(height: 8),
            const Text(
              'Укажите привычные значения. Их можно изменить в любой момент.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Первый день последней менструации'),
              subtitle: Text(_shortDate(start)),
              trailing: const Icon(
                Icons.calendar_month_outlined,
                color: _burgundy,
              ),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(
                    const Duration(days: 3650),
                  ),
                  lastDate: DateTime.now(),
                  initialDate: start,
                );
                if (value != null) setState(() => start = value);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: cycleLength,
              decoration: const InputDecoration(
                labelText: 'Обычная длина цикла',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var day = 21; day <= 45; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text('$day ${_daysWord(day)}'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => cycleLength = value);
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              value: periodLength,
              decoration: const InputDecoration(
                labelText: 'Обычная длительность менструации',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var day = 2; day <= 10; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text('$day ${_daysWord(day)}'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => periodLength = value);
              },
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                CycleSettings(
                  lastPeriodStart: start,
                  cycleLength: cycleLength,
                  periodLength: periodLength,
                ),
              ),
              child: const Text('Сохранить'),
            ),
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: _muted),
                SizedBox(width: 5),
                Text(
                  'Только на этом устройстве',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _CycleCalendar extends StatelessWidget {
  const _CycleCalendar({required this.month, required this.settings});
  final DateTime month;
  final CycleSettings settings;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1;
    final cellCount = ((offset + daysInMonth + 6) ~/ 7) * 7;
    const weekdays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
    return Column(
      children: [
        Row(
          children: weekdays
              .map(
                (day) => Expanded(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 5,
            crossAxisSpacing: 4,
          ),
          itemCount: cellCount,
          itemBuilder: (context, index) {
            final day = index - offset + 1;
            if (day < 1 || day > daysInMonth) return const SizedBox();
            final date = DateTime(month.year, month.month, day);
            final phase = settings.phaseOn(date);
            final today = DateTime.now();
            final isToday =
                date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;
            final color = _cyclePhaseColor(phase);
            final filled = phase == CyclePhase.menstruation;
            return Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? color
                    : color.withAlpha(
                        phase == CyclePhase.follicular ||
                                phase == CyclePhase.luteal
                            ? 10
                            : 51,
                      ),
                border: Border.all(
                  color: isToday
                      ? _ink
                      : phase == CyclePhase.ovulation
                      ? color
                      : Colors.transparent,
                  width: isToday ? 1.5 : 1,
                ),
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  color: filled ? Colors.white : _ink,
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CycleLegend extends StatelessWidget {
  const _CycleLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _burgundy,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.05,
    ),
  );
}

class _DayMetric extends StatelessWidget {
  const _DayMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: Color(0xFFE8E9DE),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: _muted),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            '$label:\n$value',
            maxLines: 2,
            style: const TextStyle(color: _muted, fontSize: 9.5, height: 1.25),
          ),
        ),
      ],
    ),
  );
}

String _mood(int number) => switch (number % 4) {
  0 => 'ясность',
  1 => 'лёгкость',
  2 => 'уверенность',
  _ => 'гармония',
};

class _VpnCard extends StatelessWidget {
  const _VpnCard({
    required this.vpn,
    required this.busy,
    required this.onToggle,
  });
  final AwgTunnelStatus vpn;
  final bool busy;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ЗАЩИЩЁННОЕ ПОДКЛЮЧЕНИЕ',
                style: TextStyle(color: _burgundy, fontSize: 11),
              ),
              const SizedBox(height: 7),
              _editorial(
                vpn.connected
                    ? 'Всё работает'
                    : busy
                    ? 'Готовим доступ...'
                    : 'Подключить',
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                vpn.connected
                    ? 'Соединение защищено'
                    : busy
                    ? 'Создаём личный конфиг — обычно до 30 секунд'
                    : 'Нажмите на кнопку справа',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              if (!vpn.connected) ...[
                const SizedBox(height: 5),
                const Text(
                  'Демо-доступ активируется автоматически',
                  style: TextStyle(color: _burgundy, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: busy ? null : onToggle,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: vpn.connected ? _sage : _line,
                width: 7,
              ),
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(),
                  )
                : Icon(
                    Icons.shield_outlined,
                    color: vpn.connected ? _sage : _burgundy,
                    size: 30,
                  ),
          ),
        ),
      ],
    ),
  );
}

class _ForecastPage extends StatelessWidget {
  const _ForecastPage({required this.forecast, required this.onSign});
  final Router1DailyHoroscope? forecast;
  final VoidCallback onSign;
  @override
  Widget build(BuildContext context) {
    final f = forecast;
    return _Page(
      children: [
        _editorial('Ваш прогноз'),
        TextButton(
          onPressed: onSign,
          child: Text('${f?.symbol ?? ''} ${f?.signTitle ?? 'Выбрать знак'}'),
        ),
        if (f != null) ...[
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editorial(f.overview, size: 27),
                const SizedBox(height: 18),
                _detail('Дела', f.work),
                _detail('Деньги', f.money),
                _detail('Отношения', f.love),
                _detail('Совет', f.advice),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'КАРТА ТАРО',
                  style: TextStyle(color: _burgundy, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Center(child: _TarotArtwork(title: f.tarotTitle, width: 260)),
                const SizedBox(height: 18),
                _editorial(f.tarotTitle),
                const SizedBox(height: 10),
                Text(
                  f.tarotMeaning,
                  style: const TextStyle(color: _muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _detail(String title, String text) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: _burgundy,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(color: _muted, height: 1.4)),
      ],
    ),
  );
}

class _TarotArtwork extends StatelessWidget {
  const _TarotArtwork({required this.title, required this.width});
  final String title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final asset = switch (title.trim().toLowerCase()) {
      'шут' || 'дурак' => 'assets/fabula/tarot/fool.webp',
      'маг' => 'assets/fabula/tarot/magician.webp',
      'верховная жрица' || 'жрица' =>
        'assets/fabula/tarot/high_priestess.webp',
      'императрица' => 'assets/fabula/tarot/empress.webp',
      'император' => 'assets/fabula/tarot/emperor.webp',
      'иерофант' || 'верховный жрец' || 'жрец' =>
        'assets/fabula/tarot/hierophant.webp',
      'влюблённые' || 'влюбленные' => 'assets/fabula/tarot/lovers.webp',
      'колесница' => 'assets/fabula/tarot/chariot.webp',
      'сила' => 'assets/fabula/tarot/strength.webp',
      'отшельник' => 'assets/fabula/tarot/hermit.webp',
      'колесо фортуны' || 'колесо судьбы' =>
        'assets/fabula/tarot/wheel_of_fortune.webp',
      'справедливость' || 'правосудие' =>
        'assets/fabula/tarot/justice.webp',
      'повешенный' => 'assets/fabula/tarot/hanged_man.webp',
      'смерть' => 'assets/fabula/tarot/death.webp',
      'умеренность' => 'assets/fabula/tarot/temperance.webp',
      'дьявол' => 'assets/fabula/tarot/devil.webp',
      'башня' => 'assets/fabula/tarot/tower.webp',
      'звезда' => 'assets/fabula/tarot/star.webp',
      'луна' => 'assets/fabula/tarot/moon.webp',
      'солнце' => 'assets/fabula/tarot/sun.webp',
      'суд' || 'страшный суд' => 'assets/fabula/tarot/judgement.webp',
      'мир' => 'assets/fabula/tarot/world.webp',
      _ => 'assets/fabula/tarot/fool.webp',
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.asset(
        asset,
        width: width,
        height: width * 1.5,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _ConnectionPage extends StatelessWidget {
  const _ConnectionPage({
    required this.vpn,
    required this.busy,
    required this.onToggle,
  });
  final AwgTunnelStatus vpn;
  final bool busy;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => _Page(
    children: [
      _editorial('Защищённая связь'),
      const SizedBox(height: 8),
      const Text(
        'Для привычных сайтов, сервисов и приложений.',
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 22),
      _VpnCard(vpn: vpn, busy: busy, onToggle: onToggle),
      const SizedBox(height: 16),
      const _Card(
        child: Text(
          'Fabula автоматически создаёт персональный конфиг по номеру из профиля. Оплата в демо-версии не требуется: останется только подтвердить системный запрос VPN при первом подключении.',
          style: TextStyle(color: _muted, height: 1.45),
        ),
      ),
    ],
  );
}

class _CompatibilityPage extends StatefulWidget {
  const _CompatibilityPage();
  @override
  State<_CompatibilityPage> createState() => _CompatibilityPageState();
}

class _CompatibilityPageState extends State<_CompatibilityPage> {
  var first = 'libra';
  var second = 'leo';

  @override
  Widget build(BuildContext context) {
    final firstSign = zodiacSigns.firstWhere((z) => z.$1 == first);
    final secondSign = zodiacSigns.firstWhere((z) => z.$1 == second);
    final result = _compatibility(first, second);
    return _Page(
      children: [
        _editorial('Совместимость'),
        const SizedBox(height: 8),
        const Text(
          'Не приговор, а подсказка: где вам легко, а где важно слышать друг друга.',
          style: TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        _Card(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SignSelector(
                      label: 'ВЫ',
                      value: first,
                      onChanged: (v) => setState(() => first = v),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.favorite, color: _burgundy, size: 21),
                  ),
                  Expanded(
                    child: _SignSelector(
                      label: 'ПАРТНЁР',
                      value: second,
                      onChanged: (v) => setState(() => second = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 146,
                height: 146,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: result.score / 100,
                      strokeWidth: 10,
                      backgroundColor: _line,
                      color: _burgundy,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${result.score}%',
                          style: const TextStyle(
                            fontFamily: 'serif',
                            fontSize: 39,
                            color: _ink,
                          ),
                        ),
                        Text(
                          result.label,
                          style: const TextStyle(
                            color: _burgundy,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _editorial(
                '${firstSign.$3} ${firstSign.$2} + ${secondSign.$3} ${secondSign.$2}',
                size: 23,
              ),
              const SizedBox(height: 10),
              Text(
                result.summary,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CompatibilityDetail(
                title: 'ЧТО ВАС СБЛИЖАЕТ',
                text: result.strength,
              ),
              const Divider(height: 28, color: _line),
              _CompatibilityDetail(
                title: 'ГДЕ НУЖНА ЗАБОТА',
                text: result.care,
              ),
              const Divider(height: 28, color: _line),
              _CompatibilityDetail(
                title: 'ПОДСКАЗКА ПАРЕ',
                text: result.advice,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignSelector extends StatelessWidget {
  const _SignSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label, value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionLabel(label),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: zodiacSigns
            .map(
              (z) => DropdownMenuItem(
                value: z.$1,
                child: Text('${z.$3} ${z.$2}', overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ],
  );
}

class _CompatibilityDetail extends StatelessWidget {
  const _CompatibilityDetail({required this.title, required this.text});
  final String title, text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: _burgundy,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .7,
        ),
      ),
      const SizedBox(height: 7),
      Text(text, style: const TextStyle(color: _muted, height: 1.45)),
    ],
  );
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.name,
    required this.phone,
    required this.sign,
    required this.onEdit,
    required this.enabledModules,
    required this.onModuleChanged,
  });
  final String name, phone, sign;
  final VoidCallback onEdit;
  final Set<String> enabledModules;
  final Future<void> Function(String, bool) onModuleChanged;
  @override
  Widget build(BuildContext context) {
    final z = zodiacSigns.firstWhere((e) => e.$1 == sign);
    return _Page(
      children: [
        _editorial('Профиль'),
        const SizedBox(height: 18),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Гость Fabula' : name,
                style: const TextStyle(fontFamily: 'serif', fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text('${z.$3} ${z.$2}', style: const TextStyle(color: _burgundy)),
              const SizedBox(height: 6),
              Text(
                phone.isEmpty ? 'Телефон не указан' : phone,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onEdit,
                child: const Text('Изменить профиль'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _editorial('Моя Fabula', size: 27),
        const SizedBox(height: 8),
        Text(
          '${enabledModules.length} из ${_moduleCatalog.length} блоков подключено. '
          'Выключенные блоки остаются доступны и их можно вернуть в любой момент.',
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        _Card(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (var index = 0; index < _moduleCatalog.length; index++) ...[
                SwitchListTile(
                  value: enabledModules.contains(_moduleCatalog[index].id),
                  activeColor: _burgundy,
                  secondary: Icon(
                    _moduleIcon(_moduleCatalog[index].id),
                    color: _burgundy,
                  ),
                  title: Text(
                    _moduleCatalog[index].title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _moduleCatalog[index].subtitle,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  onChanged: (value) => unawaited(
                    onModuleChanged(_moduleCatalog[index].id, value),
                  ),
                ),
                if (index != _moduleCatalog.length - 1)
                  const Divider(height: 1, indent: 58, color: _line),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Fabula $fabulaVersion',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }
}

IconData _moduleIcon(String id) => switch (id) {
  'day' => Icons.auto_awesome_outlined,
  'tarot' => Icons.style_outlined,
  'horoscope' => Icons.stars_outlined,
  'lunar' => Icons.dark_mode_outlined,
  'compatibility' => Icons.favorite_border,
  'affirmation' => Icons.format_quote,
  'mood' => Icons.sentiment_satisfied_alt_outlined,
  'look' => Icons.checkroom_outlined,
  'journal' => Icons.menu_book_outlined,
  'connection' => Icons.shield_outlined,
  'cycle' => Icons.water_drop_outlined,
  _ => Icons.circle_outlined,
};

String _cyclePhaseTitle(CyclePhase phase) => switch (phase) {
  CyclePhase.menstruation => 'Менструальная фаза',
  CyclePhase.follicular => 'Фолликулярная фаза',
  CyclePhase.fertile => 'Фертильное окно',
  CyclePhase.ovulation => 'Предполагаемая овуляция',
  CyclePhase.luteal => 'Лютеиновая фаза',
};

String _cyclePhaseDescription(CyclePhase phase) => switch (phase) {
  CyclePhase.menstruation =>
    'Организм может просить больше покоя. Выбирайте комфортный темп и отмечайте самочувствие без требований к себе.',
  CyclePhase.follicular =>
    'Энергия часто постепенно возвращается. Подходящий момент для новых планов, если вы чувствуете внутренний ресурс.',
  CyclePhase.fertile =>
    'Расчёт отмечает вероятное фертильное окно. Это только прогноз по календарю, а не способ контрацепции.',
  CyclePhase.ovulation =>
    'Ориентировочный день овуляции рассчитан по средней длине цикла. Фактическая дата может отличаться.',
  CyclePhase.luteal =>
    'Полезно оставить больше пространства для восстановления, сна и спокойного завершения начатого.',
};

Color _cyclePhaseColor(CyclePhase phase) => switch (phase) {
  CyclePhase.menstruation => _burgundy,
  CyclePhase.follicular => _line,
  CyclePhase.fertile => _sage,
  CyclePhase.ovulation => const Color(0xFFB8A17B),
  CyclePhase.luteal => _line,
};

String _nextPeriodText(CycleSnapshot snapshot) {
  final days = snapshot.daysUntilNextPeriod;
  if (days == 0) return 'Менструация ожидается сегодня';
  if (days == 1) return 'Менструация ожидается завтра';
  return 'До следующей менструации $days ${_daysWord(days)}';
}

String _daysWord(int value) {
  final mod100 = value.abs() % 100;
  final mod10 = value.abs() % 10;
  if (mod100 >= 11 && mod100 <= 14) return 'дней';
  if (mod10 == 1) return 'день';
  if (mod10 >= 2 && mod10 <= 4) return 'дня';
  return 'дней';
}

String _shortDate(DateTime date) {
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _monthTitle(DateTime date) {
  const months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String _date() {
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  const weekdays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  final d = DateTime.now();
  return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

Color _colorForName(String name) => switch (name.toLowerCase()) {
  'синий' => const Color(0xFF3F5F91),
  'бирюзовый' => const Color(0xFF3E9D99),
  'золотой' => const Color(0xFFB8A17B),
  'зелёный' => const Color(0xFF71866B),
  'фиолетовый' => const Color(0xFF79638F),
  'серебристый' => const Color(0xFFAAA8A5),
  _ => _burgundy,
};

String _zodiacFor(int month, int day) {
  if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return 'aries';
  if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return 'taurus';
  if ((month == 5 && day >= 21) || (month == 6 && day <= 20)) return 'gemini';
  if ((month == 6 && day >= 21) || (month == 7 && day <= 22)) return 'cancer';
  if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return 'leo';
  if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return 'virgo';
  if ((month == 9 && day >= 23) || (month == 10 && day <= 22)) return 'libra';
  if ((month == 10 && day >= 23) || (month == 11 && day <= 21))
    return 'scorpio';
  if ((month == 11 && day >= 22) || (month == 12 && day <= 21))
    return 'sagittarius';
  if ((month == 12 && day >= 22) || (month == 1 && day <= 19))
    return 'capricorn';
  if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return 'aquarius';
  return 'pisces';
}

String _affirmation(int number) => <String>[
  'Я могу двигаться в своём темпе и всё равно приходить вовремя.',
  'Сегодня я замечаю возможности, которые поддерживают меня.',
  'Я выбираю ясность, спокойствие и бережное отношение к себе.',
  'Мне не нужно спешить, чтобы быть сильной и заметной.',
][number.abs() % 4];

Router1DailyHoroscope _demoForecast(String sign) {
  final z = zodiacSigns.firstWhere(
    (item) => item.$1 == sign,
    orElse: () => zodiacSigns[6],
  );
  final index = zodiacSigns.indexOf(z);
  const cards = <(String, String)>[
    (
      'Звезда',
      'Сегодня особенно важно помнить о большой цели. Маленький шаг вернёт ощущение направления и внутренней опоры.',
    ),
    (
      'Императрица',
      'День раскрывается через заботу, красоту и умение принимать хорошее без чувства вины.',
    ),
    (
      'Луна',
      'Не торопитесь с выводами. Интуиция уже подсказывает верное направление, но деталям нужно проявиться.',
    ),
    (
      'Шут',
      'Разрешите себе попробовать новый путь без требования сразу знать весь маршрут.',
    ),
    (
      'Башня',
      'Освободите место от того, что давно держится только по привычке. Честность сегодня даёт облегчение.',
    ),
  ];
  final card = cards[index % cards.length];
  const colors = [
    'Бордовый',
    'Золотой',
    'Зелёный',
    'Синий',
    'Бирюзовый',
    'Фиолетовый',
  ];
  return Router1DailyHoroscope(
    date: DateTime.now().toIso8601String().substring(0, 10),
    sign: z.$1,
    signTitle: z.$2,
    symbol: z.$3,
    lunarPhase: 'Растущая Луна',
    overview:
        'Сегодня лучше выбирать не самое громкое решение, а то, после которого внутри становится спокойнее. Один точный шаг даст больше, чем несколько поспешных.',
    work:
        'Сосредоточьтесь на одной задаче, которая действительно меняет результат. Разговор во второй половине дня может открыть полезную возможность.',
    money:
        'Хороший день для расчётов и взвешенных решений. Не соглашайтесь на условия, которые приходится оправдывать самой себе.',
    love:
        'Тёплый прямой разговор окажется важнее догадок. Говорите о своих желаниях мягко, но без лишних намёков.',
    advice:
        'Оставьте в расписании немного воздуха — лучшая идея дня может появиться в паузе.',
    color: colors[index % colors.length],
    number: (index * 3 + DateTime.now().day) % 9 + 1,
    tarotTitle: card.$1,
    tarotMeaning: card.$2,
    disclaimer: 'Развлекательный персональный прогноз',
  );
}

typedef _CompatibilityResult = ({
  int score,
  String label,
  String summary,
  String strength,
  String care,
  String advice,
});

_CompatibilityResult _compatibility(String first, String second) {
  final a = zodiacSigns.indexWhere((z) => z.$1 == first);
  final b = zodiacSigns.indexWhere((z) => z.$1 == second);
  final distance = (a - b).abs();
  final circularDistance = distance > 6 ? 12 - distance : distance;
  final score = (88 - circularDistance * 4 + ((a * 7 + b * 3) % 9))
      .clamp(58, 96)
      .toInt();
  if (score >= 86) {
    return (
      score: score,
      label: 'СИЛЬНЫЙ СОЮЗ',
      summary:
          'Между вами легко возникает ощущение команды. Вы по-разному смотрите на детали, но совпадаете в главном.',
      strength:
          'Умение поддерживать инициативу друг друга и быстро возвращать отношениям тепло после напряжённого дня.',
      care:
          'Не принимайте молчание партнёра за отдаление: иногда каждому из вас нужно немного личного пространства.',
      advice:
          'Создайте общий небольшой ритуал — прогулку, завтрак или вечер без телефонов. Он станет вашей точкой опоры.',
    );
  }
  if (score >= 74) {
    return (
      score: score,
      label: 'ГАРМОНИЯ',
      summary:
          'Ваши различия скорее дополняют союз, чем мешают ему. Главное — не ждать, что партнёр догадается обо всём сам.',
      strength:
          'Один приносит движение и смелость, другой — внимание к нюансам и эмоциональную глубину.',
      care:
          'Разный темп принятия решений может создавать ненужное раздражение. Давайте друг другу время сформулировать ответ.',
      advice:
          'Перед важным разговором сначала назовите общую цель — тогда спор быстрее превращается в совместное решение.',
    );
  }
  return (
    score: score,
    label: 'ПРИТЯЖЕНИЕ',
    summary:
        'Союз может быть ярким и развивающим. Он требует чуть больше ясности, зато помогает обоим выйти за привычные рамки.',
    strength:
        'Сильное взаимное любопытство и способность показывать друг другу новый взгляд на привычные вещи.',
    care:
        'Не спорьте о чувствах как о фактах. Сначала признайте переживание партнёра, затем обсуждайте ситуацию.',
    advice:
        'Чаще проговаривайте ожидания заранее — это сохранит энергию для близости, а не для расшифровки намёков.',
  );
}
