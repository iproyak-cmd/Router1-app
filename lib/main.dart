import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'fabula_ui_text.dart';
import 'router1_api.dart';
import 'services/awg_failover_service.dart';
import 'services/awg_tunnel_service.dart';

const fabulaVersion = '0.2.6+11';
const _fabulaDemoDeviceId = int.fromEnvironment(
  'FABULA_DEMO_DEVICE_ID',
  defaultValue: 0,
);
const _burgundy = Color(0xFF7A3045);
const _cream = Color(0xFFF6F2ED);
const _ink = Color(0xFF171717);
const _muted = Color(0xFF6F6B67);
const _sage = Color(0xFFA7B3A4);
const _line = Color(0xFFE5DED7);

const zodiacSigns = <(String, String, String)>[
  ('aries', 'Овен', '♈'), ('taurus', 'Телец', '♉'),
  ('gemini', 'Близнецы', '♊'), ('cancer', 'Рак', '♋'),
  ('leo', 'Лев', '♌'), ('virgo', 'Дева', '♍'),
  ('libra', 'Весы', '♎'), ('scorpio', 'Скорпион', '♏'),
  ('sagittarius', 'Стрелец', '♐'), ('capricorn', 'Козерог', '♑'),
  ('aquarius', 'Водолей', '♒'), ('pisces', 'Рыбы', '♓'),
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
      colorScheme: ColorScheme.fromSeed(seedColor: _burgundy,
        brightness: Brightness.light, surface: _cream),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: _burgundy, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16))),
    ),
    home: const FabulaShell(),
  );
}

class FabulaShell extends StatefulWidget {
  const FabulaShell({super.key});
  @override State<FabulaShell> createState() => _FabulaShellState();
}

class _FabulaShellState extends State<FabulaShell> {
  final api = Router1Api(baseUrl: 'https://router1.tech/api',
    token: const String.fromEnvironment('ROUTER1_APP_TOKEN'), demoFallback: false);
  final tunnel = AwgTunnelService();
  var tab = 0;
  var loading = true;
  var vpnBusy = false;
  String name = '';
  String phone = '';
  String birthday = '';
  String sign = 'libra';
  DateTime? accessUntil;
  Router1DailyHoroscope? forecast;
  AwgTunnelStatus vpn = const AwgTunnelStatus(state: 'down');
  AwgFailoverController? failover;
  int? failoverDeviceId;
  var failoverEvaluating = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    timer = Timer.periodic(const Duration(seconds: 4), (_) => unawaited(_refreshVpn()));
  }

  @override
  void dispose() { timer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('fabula_name') ?? '';
    phone = prefs.getString('fabula_phone') ?? '';
    birthday = prefs.getString('fabula_birthday') ?? '';
    sign = prefs.getString('fabula_sign') ?? 'libra';
    await Future.wait([
      _loadForecast(),
      _refreshVpn(),
      if (phone.trim().isNotEmpty) _refreshAccess(),
    ]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadForecast() async {
    try { final v = await api.dailyHoroscope(sign); if (mounted) setState(() => forecast = v); }
    catch (_) {}
  }

  Future<void> _refreshVpn() async {
    try {
      final value = await tunnel.status();
      if (mounted) setState(() => vpn = value);
      if (!vpnBusy) await _evaluateFailover(value);
    }
    catch (_) {}
  }

  Future<void> _refreshAccess() async {
    try {
      final lookup = await api.findClientByPhone(phone, deviceType: _deviceType);
      final configs = _fabulaConfigs(lookup);
      if (mounted && configs.isNotEmpty) {
        setState(() => accessUntil = configs.first.paidUntil);
      }
    } catch (_) {}
  }

  Future<void> _toggleVpn() async {
    if (vpnBusy) return;
    if (phone.trim().isEmpty) { await _editProfile(requirePhone: true); return; }
    setState(() => vpnBusy = true);
    try {
      if (vpn.connected) {
        vpn = await tunnel.disconnect();
      } else {
        Router1ClientConfig? config;
        Object? lookupError;
        try {
          final lookup = await _lookupOrCreateTrial();
          config = _selectFabulaConfig(lookup);
        } catch (error) {
          lookupError = error;
        }
        final deviceId = config?.id ?? _fabulaDemoDeviceId;
        if (deviceId <= 0) {
          if (lookupError != null) throw lookupError;
          throw const FormatException('no_config');
        }
        if (mounted && config != null) {
          setState(() => accessUntil = config!.paidUntil);
        }
        final text = await api.fetchClientConfigText(
          phone: phone,
          deviceId: deviceId,
        );
        await _initializeFailover(deviceId);
        final prepared = await tunnel.prepare();
        if (!prepared) throw PlatformException(code: 'VPN_DENIED');
        vpn = await tunnel.connect(
          text,
          serverCode: config?.serverCode ?? 'fr',
        );
        vpn = await _waitForHandshake();
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fabulaConnectionErrorMessage(error))));
    } finally { if (mounted) setState(() => vpnBusy = false); }
  }

  String get _deviceType =>
    Platform.isWindows ? 'laptop_test' : 'smartphone_test';

  Future<Router1ClientLookup> _lookupOrCreateTrial() async {
    try {
      final current = await api.findClientByPhone(phone, deviceType: _deviceType);
      if (_fabulaConfigs(current).isNotEmpty) return current;
    } catch (_) {}
    await api.createFabulaAccess(
      product: _deviceType,
      name: name,
      phone: phone,
    );
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final lookup = await api.findClientByPhone(phone, deviceType: _deviceType);
        if (_fabulaConfigs(lookup).isNotEmpty) return lookup;
      } catch (_) {}
    }
    throw const FormatException('config_generation_timeout');
  }

  List<Router1ClientConfig> _fabulaConfigs(Router1ClientLookup lookup) =>
    (lookup.configs.where((config) {
      final status = config.status.toLowerCase();
      final paidUntil = config.paidUntil;
      return !config.routerCandidate && config.hasConfig &&
        const {'active', 'paid'}.contains(status) &&
        (paidUntil == null || paidUntil.isAfter(DateTime.now()));
    }).toList(growable: true)
      ..sort((left, right) {
        int score(Router1ClientConfig value) {
          var result = value.id == lookup.recommendedConfigId ? 100 : 0;
          if (value.recommended) result += 50;
          return result;
        }
        final byScore = score(right).compareTo(score(left));
        return byScore != 0 ? byScore : right.id.compareTo(left.id);
      })).toList(growable: false);

  Router1ClientConfig? _selectFabulaConfig(Router1ClientLookup lookup) {
    final available = _fabulaConfigs(lookup);
    final platform = available.where((config) {
      final text = '${config.productType} ${config.deviceName}'.toLowerCase();
      return Platform.isWindows
        ? text.contains('windows') || text.contains('pc') || text.contains('пк')
        : text.contains('android') || text.contains('smartphone') || text.contains('смартфон');
    }).toList(growable: false);
    return platform.isNotEmpty ? platform.first
      : (available.isNotEmpty ? available.first : null);
  }

  Future<void> _initializeFailover(int deviceId) async {
    if (Platform.isWindows || failoverDeviceId == deviceId) return;
    final controller = AwgFailoverController(
      api: api,
      tunnel: tunnel,
      phone: phone,
      deviceId: deviceId,
    );
    try {
      await controller.initialize();
      failover = controller;
      failoverDeviceId = deviceId;
    } catch (_) {
      failover = null;
      failoverDeviceId = null;
    }
  }

  Future<void> _evaluateFailover(AwgTunnelStatus status) async {
    final controller = failover;
    if (controller == null || failoverEvaluating || !status.connected) return;
    failoverEvaluating = true;
    try {
      final result = await controller.evaluate(status);
      if (result.switched) {
        final current = await tunnel.status();
        if (mounted) {
          setState(() => vpn = current);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message ?? 'Выбран резервный сервер')),
          );
        }
      }
    } catch (_) {
      // Ошибка резервного маршрута не должна оставлять приложение без управления.
    } finally {
      failoverEvaluating = false;
    }
  }

  Future<AwgTunnelStatus> _waitForHandshake() async {
    if (Platform.isWindows) return tunnel.status();
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      var status = await tunnel.status();
      if (status.handshake > 0) return status;
      await _evaluateFailover(status);
      status = await tunnel.status();
      if (status.handshake > 0) return status;
    }
    await tunnel.disconnect();
    throw const FormatException('tunnel_handshake_timeout');
  }

  Future<void> _chooseSign() async {
    final value = await showModalBottomSheet<String>(context: context,
      backgroundColor: _cream, builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Ваш знак', style: TextStyle(fontFamily: 'Serif', fontSize: 28)),
          const SizedBox(height: 14),
          GridView.count(shrinkWrap: true, crossAxisCount: 3, childAspectRatio: 1.55,
            mainAxisSpacing: 8, crossAxisSpacing: 8,
            children: zodiacSigns.map((z) => OutlinedButton(
              onPressed: () => Navigator.pop(context, z.$1), child: Text('${z.$3} ${z.$2}'))).toList()),
        ]))));
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
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true,
      backgroundColor: _cream, builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Профиль Fabula', style: TextStyle(fontFamily: 'Serif', fontSize: 30)),
          const SizedBox(height: 18),
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Имя (необязательно)')),
          const SizedBox(height: 12),
      TextField(controller: phoneController, keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'Телефон${requirePhone ? ' для подключения' : ''}')),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить')),
        ])));
    if (saved != true) return;
    name = nameController.text.trim(); phone = phoneController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fabula_name', name); await prefs.setString('fabula_phone', phone);
    if (mounted) setState(() => accessUntil = null);
    if (phone.isNotEmpty) await _refreshAccess();
  }

  Future<void> _completeOnboarding(String valueName, String valuePhone, DateTime valueBirthday) async {
    name = valueName.trim();
    phone = valuePhone.trim();
    birthday = '${valueBirthday.year.toString().padLeft(4, '0')}-'
      '${valueBirthday.month.toString().padLeft(2, '0')}-'
      '${valueBirthday.day.toString().padLeft(2, '0')}';
    sign = _zodiacFor(valueBirthday.month, valueBirthday.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fabula_name', name);
    await prefs.setString('fabula_phone', phone);
    await prefs.setString('fabula_birthday', birthday);
    await prefs.setString('fabula_sign', sign);
    if (mounted) setState(() { forecast = null; accessUntil = null; });
    await _loadForecast();
  }

  Future<void> _share() async {
    final f = forecast; if (f == null) return;
    await SharePlus.instance.share(ShareParams(text:
      '${f.symbol} ${f.signTitle} — сегодня\n\n${f.overview}\n\n'
      'Карта дня: ${f.tarotTitle}\n${f.tarotMeaning}\n\nFabula'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: loading ? const Center(child: CircularProgressIndicator())
      : name.isEmpty || phone.isEmpty || birthday.isEmpty
        ? _OnboardingPage(onComplete: _completeOnboarding)
      : IndexedStack(index: tab, children: [
          _TodayPage(name: name, forecast: forecast, vpn: vpn, vpnBusy: vpnBusy,
            accessUntil: accessUntil, onSign: _chooseSign,
            onForecast: () => setState(() => tab = 1), onVpn: _toggleVpn, onShare: _share),
          _ForecastPage(forecast: forecast, onSign: _chooseSign),
          _ConnectionPage(vpn: vpn, busy: vpnBusy,
            accessUntil: accessUntil, onToggle: _toggleVpn),
          _ProfilePage(name: name, phone: phone, sign: sign, onEdit: _editProfile),
        ])),
    bottomNavigationBar: loading || name.isEmpty || phone.isEmpty || birthday.isEmpty ? null
      : NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Сегодня'),
        NavigationDestination(icon: Icon(Icons.dark_mode_outlined), label: 'Прогноз'),
        NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'VPN'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Профиль'),
      ]),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.children}); final List<Widget> children;
  @override Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) =>
    Align(alignment: Alignment.topCenter, child: SizedBox(width: constraints.maxWidth > 840 ? 840 : constraints.maxWidth,
      child: ListView(padding: const EdgeInsets.fromLTRB(24, 22, 24, 30), children: children))));
}

class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({required this.onComplete});
  final Future<void> Function(String, String, DateTime) onComplete;
  @override State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  DateTime? birthday;
  var saving = false;

  Future<void> _save() async {
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty || birthday == null) {
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
      Center(child: Image.asset('assets/fabula/logo.png', width: 92, height: 92)),
      const SizedBox(height: 20),
      Center(child: _editorial('Добро пожаловать в Fabula', size: 34)),
      const SizedBox(height: 10),
      const Text(
        'Познакомимся, чтобы сделать ежедневные материалы персональными.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, height: 1.45),
      ),
      const SizedBox(height: 28),
      _Card(child: Column(children: [
        TextField(controller: name, textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Ваше имя')),
        const SizedBox(height: 14),
        TextField(controller: phone, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Номер телефона')),
        const SizedBox(height: 14),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Дата рождения'),
          subtitle: Text(birthday == null ? 'Не выбрана'
            : '${birthday!.day.toString().padLeft(2, '0')}.${birthday!.month.toString().padLeft(2, '0')}.${birthday!.year}'),
          trailing: const Icon(Icons.calendar_month_outlined, color: _burgundy),
          onTap: () async {
            final value = await showDatePicker(context: context,
              firstDate: DateTime(1920), lastDate: DateTime.now(),
              initialDate: birthday ?? DateTime(1990, 1, 1));
            if (value != null) setState(() => birthday = value);
          },
        ),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Сохраняем...' : 'Продолжить'),
        )),
      ])),
      const SizedBox(height: 14),
      const Text('Данные используются для персонализации Fabula и подключения сервиса.',
        textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(24)});
  final Widget child; final EdgeInsets padding;
  @override Widget build(BuildContext context) => Container(padding: padding,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26),
      border: Border.all(color: _line), boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 18, offset: Offset(0, 6))]), child: child);
}

Text _editorial(String text, {double size = 30}) => Text(text,
  style: TextStyle(fontFamily: 'Serif', color: _ink, fontSize: size, height: 1.08, fontWeight: FontWeight.w500));

class _TodayPage extends StatelessWidget {
  const _TodayPage({required this.name, required this.forecast, required this.vpn,
    required this.vpnBusy, required this.accessUntil, required this.onSign,
    required this.onForecast, required this.onVpn, required this.onShare});
  final String name; final Router1DailyHoroscope? forecast; final AwgTunnelStatus vpn; final bool vpnBusy;
  final DateTime? accessUntil;
  final VoidCallback onSign, onForecast, onVpn, onShare;
  @override Widget build(BuildContext context) { final f = forecast; return _Page(children: [
    Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _editorial(name.isEmpty ? 'Доброе утро' : 'Доброе утро, $name', size: 28),
      const SizedBox(height: 4), Text(_date(), style: const TextStyle(color: _muted, fontSize: 13)),
    ])), ClipOval(child: Image.asset('assets/fabula/logo.png', width: 52, height: 52, fit: BoxFit.cover))]),
    Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: onSign,
      style: TextButton.styleFrom(foregroundColor: _muted, padding: const EdgeInsets.symmetric(horizontal: 4)),
      icon: Text(f?.symbol ?? '✦', style: const TextStyle(color: _burgundy)), label: Text(f?.signTitle ?? 'Выбрать знак'))),
    const SizedBox(height: 4),
    _Card(padding: const EdgeInsets.all(20), child: f == null ? const Center(child: CircularProgressIndicator()) : Stack(children: [
      Positioned(right: -36, top: -18, bottom: -30, child: Opacity(opacity: .58,
        child: Image.asset('assets/fabula/branch.png', width: 190, fit: BoxFit.cover))),
      Padding(padding: const EdgeInsets.only(right: 92), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionLabel('ВАШ ДЕНЬ'), const SizedBox(height: 10),
        Text(f.overview, maxLines: 5, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'Serif', color: _ink, fontSize: 21, height: 1.17)),
        const SizedBox(height: 16), Row(children: [
          _DayMetric(icon: Icons.sentiment_satisfied_alt_outlined, label: 'Настроение', value: _mood(f.number)),
          const SizedBox(width: 12), _DayMetric(icon: Icons.auto_awesome, label: 'Энергия дня', value: '${76 + (f.number * 3) % 19}%'),
        ]),
      ])),
    ])),
    const SizedBox(height: 10),
    _Card(padding: const EdgeInsets.all(20), child: f == null ? const SizedBox() : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionLabel('КАРТА ДНЯ'), const SizedBox(height: 10), _editorial(f.tarotTitle, size: 27), const SizedBox(height: 10),
        Text(f.tarotMeaning, maxLines: 4, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 14), OutlinedButton(onPressed: onForecast, child: const Text('Открыть толкование')),
      ])), const SizedBox(width: 14), _TarotArtwork(title: f.tarotTitle, width: 122)])),
    const SizedBox(height: 12),
    if (f != null) Row(children: [Expanded(child: _Card(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel('ЦВЕТ ДНЯ'), const SizedBox(height: 12), Row(children: [Container(width: 40, height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _colorForName(f.color))), const SizedBox(width: 10),
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(f.color, style: const TextStyle(fontSize: 15))))])]))),
      const SizedBox(width: 10), Expanded(child: _Card(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionLabel('ЧИСЛО ДНЯ'), const SizedBox(height: 5), Row(children: [Text('${f.number}', style: const TextStyle(color: _burgundy, fontFamily: 'Serif', fontSize: 40)),
          const SizedBox(width: 10), const Expanded(child: Text('Внимание\nк деталям', style: TextStyle(color: _muted, fontSize: 11, height: 1.25)))])])))]),
    const SizedBox(height: 12), _VpnCard(vpn: vpn, busy: vpnBusy,
      accessUntil: accessUntil, onToggle: onVpn),
    const SizedBox(height: 12), _Card(child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('АФФИРМАЦИЯ ДНЯ', style: TextStyle(color: _burgundy, fontSize: 11)), const SizedBox(height: 8),
      _editorial('Сегодня я выбираю ясность вместо спешки.', size: 22)])), IconButton(onPressed: onShare, icon: const Icon(Icons.ios_share, color: _burgundy))])),
  ]); }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text); final String text;
  @override Widget build(BuildContext context) => Text(text,
    style: const TextStyle(color: _burgundy, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.05));
}

class _DayMetric extends StatelessWidget {
  const _DayMetric({required this.icon, required this.label, required this.value});
  final IconData icon; final String label, value;
  @override Widget build(BuildContext context) => Expanded(child: Row(children: [
    Container(width: 30, height: 30, decoration: const BoxDecoration(color: Color(0xFFE8E9DE), shape: BoxShape.circle),
      child: Icon(icon, size: 15, color: _muted)), const SizedBox(width: 7),
    Expanded(child: Text('$label:\n$value', maxLines: 2, style: const TextStyle(color: _muted, fontSize: 9.5, height: 1.25))),
  ]));
}

String _mood(int number) => switch (number % 4) {
  0 => 'ясность', 1 => 'лёгкость', 2 => 'уверенность', _ => 'гармония',
};

class _VpnCard extends StatelessWidget {
  const _VpnCard({required this.vpn, required this.busy,
    required this.accessUntil, required this.onToggle});
  final AwgTunnelStatus vpn; final bool busy; final DateTime? accessUntil;
  final VoidCallback onToggle;
  @override Widget build(BuildContext context) {
    final confirmed = vpn.connected && (Platform.isWindows || vpn.handshake > 0);
    final title = busy ? 'Подключаемся'
      : confirmed ? 'Всё работает'
      : vpn.connected ? 'Проверяем соединение' : 'Подключить';
    final subtitle = busy ? 'Ждём ответ защищённого сервера'
      : confirmed ? 'Соединение защищено'
      : vpn.connected ? 'Сервер ещё не ответил' : 'Нажмите на кнопку справа';
    return _Card(padding: const EdgeInsets.all(20), child: Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ЗАЩИЩЁННОЕ ПОДКЛЮЧЕНИЕ', style: TextStyle(color: _burgundy, fontSize: 11)),
      const SizedBox(height: 7), _editorial(title, size: 22),
      const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 5), Text(fabulaAccessLabel(accessUntil),
        style: const TextStyle(color: _burgundy, fontSize: 11)),
    ])), const SizedBox(width: 12),
    InkWell(onTap: busy ? null : onToggle, borderRadius: BorderRadius.circular(50), child: Container(width: 72, height: 72,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: vpn.connected ? _sage : _line, width: 7)),
      child: busy ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())
        : Icon(Icons.shield_outlined, color: vpn.connected ? _sage : _burgundy, size: 30))),
  ]));
  }
}

class _ForecastPage extends StatelessWidget {
  const _ForecastPage({required this.forecast, required this.onSign}); final Router1DailyHoroscope? forecast; final VoidCallback onSign;
  @override Widget build(BuildContext context) { final f = forecast; return _Page(children: [
    _editorial('Ваш прогноз'), TextButton(onPressed: onSign, child: Text('${f?.symbol ?? ''} ${f?.signTitle ?? 'Выбрать знак'}')),
    if (f != null) ...[
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _editorial(f.overview, size: 27), const SizedBox(height: 18),
        _detail('Дела', f.work), _detail('Деньги', f.money), _detail('Отношения', f.love), _detail('Совет', f.advice),
      ])), const SizedBox(height: 12),
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('КАРТА ТАРО', style: TextStyle(color: _burgundy, fontSize: 12)), const SizedBox(height: 10),
        Center(child: _TarotArtwork(title: f.tarotTitle, width: 260)), const SizedBox(height: 18),
        _editorial(f.tarotTitle), const SizedBox(height: 10), Text(f.tarotMeaning, style: const TextStyle(color: _muted, height: 1.4)),
      ])),
    ]
  ]); }
  Widget _detail(String title, String text) => Padding(padding: const EdgeInsets.only(top: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(title.toUpperCase(), style: const TextStyle(color: _burgundy, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(text, style: const TextStyle(color: _muted, height: 1.4))]));
}

class _TarotArtwork extends StatelessWidget {
  const _TarotArtwork({required this.title, required this.width});
  final String title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final asset = switch (title.toLowerCase()) {
      'звезда' => 'assets/fabula/tarot/star.png',
      'луна' => 'assets/fabula/tarot/moon.png',
      'императрица' => 'assets/fabula/tarot/empress.png',
      'император' => 'assets/fabula/tarot/emperor.webp',
      'башня' => 'assets/fabula/tarot/tower.png',
      'шут' => 'assets/fabula/tarot/fool.png',
      _ => null,
    };
    if (asset == null) {
      return Container(width: width, height: width * 1.5,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B2023), Color(0xFF7A3045)]),
          border: Border.all(color: const Color(0xFFB8A17B), width: 2),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: Opacity(opacity: .14,
            child: Image.asset('assets/fabula/branch.png', fit: BoxFit.cover))),
          Padding(padding: const EdgeInsets.all(14), child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFD7C29A), size: 42),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontFamily: 'Serif',
                  fontSize: 18, height: 1.1)),
            ])),
        ]));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset(
      asset, width: width, height: width * 1.5, fit: BoxFit.cover));
  }
}

class _ConnectionPage extends StatelessWidget {
  const _ConnectionPage({required this.vpn, required this.busy,
    required this.accessUntil, required this.onToggle});
  final AwgTunnelStatus vpn; final bool busy; final DateTime? accessUntil;
  final VoidCallback onToggle;
  @override Widget build(BuildContext context) => _Page(children: [
    _editorial('Защищённая связь'), const SizedBox(height: 8),
    const Text('Для привычных сайтов, сервисов и приложений.', style: TextStyle(color: _muted)),
    const SizedBox(height: 22), _VpnCard(vpn: vpn, busy: busy,
      accessUntil: accessUntil, onToggle: onToggle),
    const SizedBox(height: 16), const _Card(child: Text('Fabula автоматически проверяет соединение и выбирает доступный защищённый сервер.', style: TextStyle(color: _muted, height: 1.45))),
  ]);
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.name, required this.phone, required this.sign, required this.onEdit});
  final String name, phone, sign; final VoidCallback onEdit;
  @override Widget build(BuildContext context) { final z = zodiacSigns.firstWhere((e) => e.$1 == sign); return _Page(children: [
    _editorial('Профиль'), const SizedBox(height: 18), _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name.isEmpty ? 'Гость Fabula' : name, style: const TextStyle(fontFamily: 'Serif', fontSize: 28)), const SizedBox(height: 8),
      Text('${z.$3} ${z.$2}', style: const TextStyle(color: _burgundy)), const SizedBox(height: 6),
      Text(phone.isEmpty ? 'Телефон не указан' : phone, style: const TextStyle(color: _muted)), const SizedBox(height: 18),
      FilledButton(onPressed: onEdit, child: const Text('Изменить профиль')),
    ])), const SizedBox(height: 16), Text('Fabula $fabulaVersion', textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12)),
  ]); }
}

String _date() {
  const months = ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря'];
  const weekdays = ['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье'];
  final d = DateTime.now(); return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
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
  if ((month == 10 && day >= 23) || (month == 11 && day <= 21)) return 'scorpio';
  if ((month == 11 && day >= 22) || (month == 12 && day <= 21)) return 'sagittarius';
  if ((month == 12 && day >= 22) || (month == 1 && day <= 19)) return 'capricorn';
  if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return 'aquarius';
  return 'pisces';
}
