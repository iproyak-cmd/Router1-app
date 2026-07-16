import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'router1_api.dart';
import 'services/awg_tunnel_service.dart';

const fabulaVersion = '0.1.2+3';
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
  Router1DailyHoroscope? forecast;
  AwgTunnelStatus vpn = const AwgTunnelStatus(state: 'down');
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
    await Future.wait([_loadForecast(), _refreshVpn()]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadForecast() async {
    try { final v = await api.dailyHoroscope(sign); if (mounted) setState(() => forecast = v); }
    catch (_) {}
  }

  Future<void> _refreshVpn() async {
    try { final v = await tunnel.status(); if (mounted) setState(() => vpn = v); }
    catch (_) {}
  }

  Future<void> _toggleVpn() async {
    if (vpnBusy) return;
    if (phone.trim().isEmpty) { await _editProfile(requirePhone: true); return; }
    setState(() => vpnBusy = true);
    try {
      if (vpn.connected) {
        vpn = await tunnel.disconnect();
      } else {
        final lookup = await _lookupOrCreateTrial();
        final candidates = lookup.gadgetConfigs.where((c) {
          final text = '${c.productType} ${c.deviceName}'.toLowerCase();
          return Platform.isWindows ? text.contains('windows') || text.contains('pc') || text.contains('пк')
            : text.contains('android') || text.contains('smartphone') || text.contains('смартфон');
        }).toList();
        final config = candidates.isNotEmpty ? candidates.first
          : (lookup.gadgetConfigs.isNotEmpty ? lookup.gadgetConfigs.first : null);
        if (config == null) throw const FormatException('no_config');
        final text = await api.fetchClientConfigText(phone: phone, deviceId: config.id);
        await tunnel.prepare();
        vpn = await tunnel.connect(text, serverCode: config.serverCode);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Подключение пока не оформлено'),
        action: SnackBarAction(label: 'Оформить', onPressed: () => launchUrl(
          Uri.parse('https://router1.tech/download'), mode: LaunchMode.externalApplication))));
    } finally { if (mounted) setState(() => vpnBusy = false); }
  }

  Future<Router1ClientLookup> _lookupOrCreateTrial() async {
    try {
      final current = await api.findClientByPhone(phone);
      if (current.gadgetConfigs.isNotEmpty) return current;
    } catch (_) {}
    await api.createFabulaAccess(
      product: Platform.isWindows ? 'laptop_test' : 'smartphone_test',
      name: name,
      phone: phone,
    );
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final lookup = await api.findClientByPhone(phone);
        if (lookup.gadgetConfigs.isNotEmpty) return lookup;
      } catch (_) {}
    }
    throw const FormatException('config_generation_timeout');
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
    if (mounted) setState(() {});
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
    if (mounted) setState(() { forecast = null; });
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
            onSign: _chooseSign, onVpn: _toggleVpn, onShare: _share),
          _ForecastPage(forecast: forecast, onSign: _chooseSign),
          _ConnectionPage(vpn: vpn, busy: vpnBusy, onToggle: _toggleVpn),
          const _CompatibilityPage(),
          _ProfilePage(name: name, phone: phone, sign: sign, onEdit: _editProfile),
        ])),
    bottomNavigationBar: loading || name.isEmpty || phone.isEmpty || birthday.isEmpty ? null
      : NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Сегодня'),
        NavigationDestination(icon: Icon(Icons.dark_mode_outlined), label: 'Прогноз'),
        NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Связь'),
        NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Совместимость'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Профиль'),
      ]),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.children}); final List<Widget> children;
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(24, 22, 24, 30), children: children);
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
    required this.vpnBusy, required this.onSign, required this.onVpn, required this.onShare});
  final String name; final Router1DailyHoroscope? forecast; final AwgTunnelStatus vpn; final bool vpnBusy;
  final VoidCallback onSign, onVpn, onShare;
  @override Widget build(BuildContext context) { final f = forecast; return _Page(children: [
    Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _editorial(name.isEmpty ? 'Доброе утро' : 'Доброе утро, $name', size: 31),
      const SizedBox(height: 5), Text(_date(), style: const TextStyle(color: _muted)),
    ])), Image.asset('assets/fabula/logo.png', width: 58, height: 58)]),
    TextButton.icon(onPressed: onSign, icon: Text(f?.symbol ?? '✦'), label: Text(f?.signTitle ?? 'Выбрать знак')),
    const SizedBox(height: 10),
    _Card(child: f == null ? const SizedBox() : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('КАРТА ДНЯ', style: TextStyle(color: _burgundy, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 12), _editorial(f.tarotTitle), const SizedBox(height: 10),
      Text(f.tarotMeaning, style: const TextStyle(color: _muted, height: 1.4)),
    ])), const SizedBox(width: 14), _TarotArtwork(title: f.tarotTitle, width: 112)])),
    const SizedBox(height: 12),
    _Card(child: f == null ? const Center(child: CircularProgressIndicator()) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ПРОГНОЗ ЗНАКА', style: TextStyle(color: _burgundy, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 14), _editorial(f.overview, size: 23),
    ])),
    const SizedBox(height: 12),
    if (f != null) Row(children: [Expanded(child: _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ЦВЕТ ДНЯ', style: TextStyle(color: _burgundy, fontSize: 11)), const SizedBox(height: 12),
      Row(children: [const CircleAvatar(backgroundColor: _burgundy), const SizedBox(width: 10), Expanded(child: Text(f.color))])]))),
      const SizedBox(width: 10), Expanded(child: _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ЧИСЛО ДНЯ', style: TextStyle(color: _burgundy, fontSize: 11)), const SizedBox(height: 6),
        Text('${f.number}', style: const TextStyle(color: _burgundy, fontFamily: 'Serif', fontSize: 42))])))]),
    const SizedBox(height: 12), _VpnCard(vpn: vpn, busy: vpnBusy, onToggle: onVpn),
    const SizedBox(height: 12), _Card(child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('АФФИРМАЦИЯ ДНЯ', style: TextStyle(color: _burgundy, fontSize: 11)), const SizedBox(height: 8),
      _editorial('Сегодня я выбираю ясность вместо спешки.', size: 22)])), IconButton(onPressed: onShare, icon: const Icon(Icons.ios_share, color: _burgundy))])),
  ]); }
}

class _VpnCard extends StatelessWidget {
  const _VpnCard({required this.vpn, required this.busy, required this.onToggle});
  final AwgTunnelStatus vpn; final bool busy; final VoidCallback onToggle;
  @override Widget build(BuildContext context) => _Card(child: Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ЗАЩИЩЁННОЕ ПОДКЛЮЧЕНИЕ', style: TextStyle(color: _burgundy, fontSize: 11)),
      const SizedBox(height: 8), _editorial(vpn.connected ? 'Всё работает' : 'Подключение выключено', size: 24),
      const SizedBox(height: 5), Text(vpn.connected ? 'Соединение защищено' : 'Нажмите, чтобы подключиться', style: const TextStyle(color: _muted)),
      const SizedBox(height: 5), const Text('Тестовый доступ действует до 20 июля', style: TextStyle(color: _burgundy, fontSize: 11)),
    ])), const SizedBox(width: 12),
    InkWell(onTap: busy ? null : onToggle, borderRadius: BorderRadius.circular(50), child: Container(width: 72, height: 72,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: vpn.connected ? _sage : _line, width: 7)),
      child: busy ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())
        : Icon(Icons.shield_outlined, color: vpn.connected ? _sage : _burgundy, size: 30))),
  ]));
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
      _ => null,
    };
    if (asset == null) {
      return SizedBox(width: width, height: width * 1.5,
        child: const Center(child: Icon(Icons.auto_awesome,
          color: Color(0xFFB8A17B), size: 55)));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset(
      asset, width: width, height: width * 1.5, fit: BoxFit.cover));
  }
}

class _ConnectionPage extends StatelessWidget {
  const _ConnectionPage({required this.vpn, required this.busy, required this.onToggle});
  final AwgTunnelStatus vpn; final bool busy; final VoidCallback onToggle;
  @override Widget build(BuildContext context) => _Page(children: [
    _editorial('Защищённая связь'), const SizedBox(height: 8),
    const Text('Для привычных сайтов, сервисов и приложений.', style: TextStyle(color: _muted)),
    const SizedBox(height: 22), _VpnCard(vpn: vpn, busy: busy, onToggle: onToggle),
    const SizedBox(height: 16), const _Card(child: Text('Fabula использует защищённое подключение Router1. Технические настройки выполняются автоматически.', style: TextStyle(color: _muted, height: 1.45))),
  ]);
}

class _CompatibilityPage extends StatelessWidget {
  const _CompatibilityPage();
  @override Widget build(BuildContext context) => _Page(children: [
    _editorial('Совместимость'), const SizedBox(height: 8),
    const Text('Новый раздел скоро появится', style: TextStyle(color: _muted)), const SizedBox(height: 22),
    const _Card(child: Column(children: [Icon(Icons.favorite_border, color: _burgundy, size: 54), SizedBox(height: 14),
      Text('Вы сможете сравнить два знака и получить подсказки для отношений и общения.', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.45))])),
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
