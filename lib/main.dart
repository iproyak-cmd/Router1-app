import 'dart:math' as math;
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/keenetic_router.dart';
import 'router1_api.dart';
import 'services/keenetic_discovery.dart';
import 'services/keenetic_setup_service.dart';

const router1AppVersion = '0.1.41+44';

void main() {
  runApp(const Router1App());
}

class Router1Theme {
  static const bg = Color(0xFF020B10);
  static const panel = Color(0xCC07151D);
  static const panel2 = Color(0xAA0A1E28);
  static const border = Color(0xFF1B3340);
  static const green = Color(0xFF7BE33C);
  static const green2 = Color(0xFF28B84F);
  static const blue = Color(0xFF2F69FF);
  static const purple = Color(0xFF9B6BFF);
  static const gold = Color(0xFFD8A21C);
  static const muted = Color(0xFFA8B2BC);
  static const white = Color(0xFFF9FAFB);

  static const title = TextStyle(
      color: white, fontSize: 34, height: 1.1, fontWeight: FontWeight.w900);
  static const subtitle = TextStyle(
      color: muted, fontSize: 19, height: 1.35, fontWeight: FontWeight.w500);
}

class Router1App extends StatelessWidget {
  const Router1App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Router1',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Router1Theme.green,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Router1Theme.bg,
        fontFamily: 'Manrope',
        useMaterial3: true,
      ),
      home: const FirstRunShell(),
    );
  }
}

enum FirstRunPath { router, gadget }

enum Router1RunMode { demo, real }

class FirstRunShell extends StatefulWidget {
  const FirstRunShell({super.key});

  @override
  State<FirstRunShell> createState() => _FirstRunShellState();
}

class _FirstRunShellState extends State<FirstRunShell> {
  var step = 0;
  FirstRunPath? path;
  var platform = 'Android';
  var runMode = Router1RunMode.real;
  KeeneticRouter? router;
  KeeneticAccess? routerAccess;
  String? awgConfig;
  String? paidOrderId;
  String? gadgetConfigText;
  String? gadgetConfigFilename;
  String clientName = 'Клиент Router1';
  String clientPhone = '';
  RouterRoutingProfile routerRoutingProfile = RouterRoutingProfile.selective;
  Router1RouteProfileKind routerRouteProfileKind =
      Router1RouteProfileKind.goldStandard;
  var testPaymentMode = false;
  var paid = false;
  final setupService = KeeneticSetupService();
  final appApi = Router1Api(
    baseUrl: 'https://router1.tech/api',
    token: const String.fromEnvironment('ROUTER1_APP_TOKEN'),
    demoFallback: false,
  );
  final setupLogs = <SetupLogEntry>[];
  final discoveryLogs = <String>[];
  Timer? splashTimer;

  void next() => setState(() => step++);
  void back() => setState(() => step = step > 0 ? step - 1 : 0);
  void goTo(int value) => setState(() => step = value);
  void openHome() => setState(() => step = 100);
  void addSetupLog(SetupLogEntry entry) => setState(() => setupLogs.add(entry));
  bool get demoMode => runMode == Router1RunMode.demo;

  Future<void> openHomeAfterSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('router1_configured', true);
    await prefs.setString('router1_router_model', router?.model ?? '');
    await prefs.setString('router1_client_phone', clientPhone);
    await prefs.setString(
        'router1_route_profile_kind', routerRouteProfileKind.name);
    if (mounted) openHome();
  }

  void startRouterSetupFromHome() {
    setState(() {
      path = FirstRunPath.router;
      router = null;
      routerAccess = null;
      awgConfig = null;
      paidOrderId = null;
      paid = false;
      setupLogs.clear();
      discoveryLogs.clear();
      step = 2;
    });
  }

  void startGadgetSetupFromHome() {
    setState(() {
      path = FirstRunPath.gadget;
      gadgetConfigText = null;
      gadgetConfigFilename = null;
      step = 2;
    });
  }

  void openPaymentFromHome() {
    setState(() {
      path = FirstRunPath.router;
      step = routerAccess == null ? 2 : 60;
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(loadInitialScreen());
    splashTimer = Timer(const Duration(milliseconds: 3200), () {
      if (!mounted || step != 0) return;
      next();
    });
  }

  Future<void> loadInitialScreen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || step != 0) return;
    if (prefs.getBool('router1_configured') == true) {
      splashTimer?.cancel();
      setState(() {
        final savedModel = prefs.getString('router1_router_model') ?? '';
        final savedPhone = prefs.getString('router1_client_phone') ?? '';
        final savedKind = prefs.getString('router1_route_profile_kind');
        if (savedKind != null) {
          routerRouteProfileKind = Router1RouteProfileKind.values.firstWhere(
              (k) => k.name == savedKind,
              orElse: () => Router1RouteProfileKind.goldStandard);
        }
        if (savedPhone.isNotEmpty) clientPhone = savedPhone;
        if (savedModel.isNotEmpty) {
          router = KeeneticRouter(
            model: savedModel,
            ip: '',
            hostname: savedModel,
            firmware: null,
            compatible: true,
            apiAuthenticated: true,
          );
        }
        step = 100;
      });
    }
  }

  @override
  void dispose() {
    splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (step == 100) {
      return HomeScreen(
        router: router,
        clientPhone: clientPhone,
        paid: paid || clientPhone.isNotEmpty,
        routeProfileKind: routerRouteProfileKind,
        onSetupRouter: startRouterSetupFromHome,
        onSetupGadget: startGadgetSetupFromHome,
        onPay: openPaymentFromHome,
      );
    }
    return Scaffold(
      body: Router1Background(
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: buildStep(context),
          ),
        ),
      ),
    );
  }

  Widget buildStep(BuildContext context) {
    if (step == 0) {
      return const FirstRunPage(
        key: ValueKey('splash'),
        icon: Icons.route,
        title: 'Router1',
        subtitle: 'Умный интернет.',
      );
    }

    if (step == 1) {
      return ListView(
        key: const ValueKey('choice'),
        padding: const EdgeInsets.fromLTRB(22, 42, 22, 24),
        children: [
          const Center(child: _CompactLogo()),
          const SizedBox(height: 34),
          const Text('Что хотите настроить?',
              textAlign: TextAlign.center, style: Router1Theme.title),
          const SizedBox(height: 26),
          ChoiceCard(
            icon: Icons.home_rounded,
            title: 'Роутер',
            description: 'Для дома, офиса, родителей или дачи.',
            button: 'Настроить роутер',
            onTap: () {
              path = FirstRunPath.router;
              next();
            },
          ),
          const SizedBox(height: 22),
          ChoiceCard(
            icon: Icons.phone_android_rounded,
            title: 'Гаджет',
            description: 'Смартфон, ноутбук или компьютер.',
            button: 'Настроить гаджет / комп',
            onTap: () {
              path = FirstRunPath.gadget;
              next();
            },
          ),
          const SizedBox(height: 30),
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0xFF20323B))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text('Уже всё настроено?',
                    style: TextStyle(
                        color: Router1Theme.muted,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
              Expanded(child: Divider(color: Color(0xFF20323B))),
            ],
          ),
          Center(
            child: TextButton.icon(
              onPressed: openHome,
              icon: const Text(''),
              label: const Text('Открыть Router1  ›',
                  style: TextStyle(
                      color: Color(0xFF4B7DFF),
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 28),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, color: Router1Theme.green, size: 25),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                    'Ваши данные защищены.\nПодключение безопасно и конфиденциально.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Router1Theme.muted, fontSize: 17, height: 1.35)),
              ),
            ],
          ),
        ],
      );
    }

    if (path == FirstRunPath.gadget) {
      return buildGadgetFlow();
    }
    if (step == 30) {
      return DeveloperSettingsPage(
        mode: runMode,
        onModeChanged: (value) {
          setState(() {
            runMode = value;
            testPaymentMode = value == Router1RunMode.demo;
            router = null;
            routerAccess = null;
            discoveryLogs.clear();
            setupLogs.clear();
          });
        },
        onBack: () => goTo(1),
      );
    }
    return buildRouterFlow();
  }

  Widget buildRouterFlow() {
    return switch (step) {
      2 => RouterConnectPage(
          service: setupService,
          onAccess: (value) {
            routerAccess = value;
            router = value.router;
            goTo(5);
          },
          onLog: addSetupLog,
          onBack: back,
        ),
      5 => RouterReadyForPaymentPage(
          access: routerAccess,
          onNext: () => goTo(6),
          onBack: back,
        ),
      6 => ClientPhoneLookupPage(
          api: appApi,
          initialName: clientName,
          initialPhone: clientPhone,
          onExistingConfig: (name, phone, configText) {
            clientName = name;
            clientPhone = phone;
            awgConfig = configText;
            paid = true;
            goTo(7);
          },
          onNeedsPayment: (name, phone) {
            clientName = name;
            clientPhone = phone;
            goTo(60);
          },
          onLog: addSetupLog,
          onBack: back,
        ),
      60 => PaymentPage(
          api: appApi,
          testMode: testPaymentMode,
          initialName: clientName,
          initialPhone: clientPhone,
          onTestModeChanged: null,
          onExistingConfig: (name, phone, configText) {
            clientName = name;
            clientPhone = phone;
            awgConfig = configText;
            paid = true;
            goTo(7);
          },
          onPaid: (name, phone, orderId) {
            clientName = name;
            clientPhone = phone;
            paidOrderId = orderId;
            paid = true;
            goTo(7);
          },
          onBack: back,
        ),
      7 => WireGuardComponentPage(
          access: routerAccess,
          service: setupService,
          demoMode: demoMode,
          onReady: () => awgConfig == null ? goTo(8) : goTo(9),
          onLog: addSetupLog,
          onBack: back,
        ),
      8 => PaidConfigLoadPage(
          api: appApi,
          orderId: paidOrderId,
          demoMode: demoMode,
          onConfig: (value) {
            awgConfig = value;
            goTo(9);
          },
          onLog: addSetupLog,
          onBack: back,
        ),
      9 => RouterRoutingProfilePage(
          profile: routerRoutingProfile,
          routeProfileKind: routerRouteProfileKind,
          onChanged: (value) => setState(() => routerRoutingProfile = value),
          onRouteProfileChanged: (value) => setState(() {
            routerRouteProfileKind = value;
            routerRoutingProfile = RouterRoutingProfile.selective;
          }),
          onNext: () => goTo(10),
          onBack: back,
        ),
      10 => RouterSetupProgressPage(
          access: routerAccess,
          awgConfig: awgConfig,
          paid: paid,
          routingProfile: routerRoutingProfile,
          routeProfileKind: routerRouteProfileKind,
          api: appApi,
          service: setupService,
          logs: setupLogs,
          onLog: addSetupLog,
          onDone: () => unawaited(openHomeAfterSetup()),
          onBack: back,
        ),
      _ => PaymentPage(
          api: appApi,
          testMode: testPaymentMode,
          initialName: clientName,
          initialPhone: clientPhone,
          onTestModeChanged: null,
          onExistingConfig: (name, phone, configText) {
            clientName = name;
            clientPhone = phone;
            awgConfig = configText;
            paid = true;
            goTo(7);
          },
          onPaid: (name, phone, orderId) {
            clientName = name;
            clientPhone = phone;
            paidOrderId = orderId;
            paid = true;
            goTo(7);
          },
          onBack: back,
        ),
    };
  }

  Widget buildGadgetFlow() {
    return switch (step) {
      2 => PlatformPage(
          selected: platform,
          onSelect: (value) => setState(() => platform = value),
          onNext: next,
          onBack: back,
        ),
      3 => GadgetPaymentPage(
          api: appApi,
          platform: platform,
          initialName: clientName,
          initialPhone: clientPhone,
          onPaid: (name, phone, configText, filename) {
            clientName = name;
            clientPhone = phone;
            gadgetConfigText = configText;
            gadgetConfigFilename = filename;
            paid = true;
            goTo(4);
          },
          onBack: back,
        ),
      4 => GadgetInstructionPage(
          platform: platform,
          configText: gadgetConfigText ?? '',
          filename: gadgetConfigFilename ?? 'router1.conf',
          onBack: back,
        ),
      _ => HomeScreen(
          router: router,
          clientPhone: clientPhone,
          paid: paid || clientPhone.isNotEmpty,
          routeProfileKind: routerRouteProfileKind,
          onSetupRouter: startRouterSetupFromHome,
          onSetupGadget: startGadgetSetupFromHome,
          onPay: openPaymentFromHome,
        ),
    };
  }
}

class FirstRunPage extends StatelessWidget {
  const FirstRunPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.primaryText,
    this.onPrimary,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? primaryText;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final compact = height < 760;
        final logoSize = compact ? 48.0 : 58.0;
        final orbSize = math.min(compact ? 230.0 : 310.0, height * 0.34);
        final topGap = compact ? 24.0 : 70.0;
        final betweenGap = compact ? 14.0 : 24.0;

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  28, compact ? 20 : 34, 28, compact ? 18 : 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(height: topGap),
                  Column(
                    children: [
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                                text: 'Router',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: logoSize,
                                    fontWeight: FontWeight.w900)),
                            TextSpan(
                                text: '1',
                                style: TextStyle(
                                    color: Router1Theme.green,
                                    fontSize: logoSize,
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('УМНЫЙ ИНТЕРНЕТ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Router1Theme.green,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  SizedBox(height: betweenGap),
                  SizedBox(
                    width: orbSize,
                    height: orbSize,
                    child: Image.asset('assets/illustrations/globe.png',
                        fit: BoxFit.contain),
                  ),
                  SizedBox(height: betweenGap),
                  Column(
                    children: [
                      Text('Ваш интернет.\nВаши правила.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 27 : 31,
                              height: 1.15,
                              fontWeight: FontWeight.w900)),
                      SizedBox(height: compact ? 12 : 18),
                      Text(
                          'Подключайте роутеры и устройства,\nуправляйте сетью и оставайтесь на связи.',
                          textAlign: TextAlign.center,
                          style: Router1Theme.subtitle
                              .copyWith(fontSize: compact ? 17 : 19)),
                      SizedBox(height: compact ? 22 : 34),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _PagerDot(active: true),
                          _PagerDot(active: false),
                          _PagerDot(active: false),
                        ],
                      ),
                    ],
                  ),
                  if (primaryText != null && onPrimary != null) ...[
                    SizedBox(height: compact ? 18 : 24),
                    PrimaryButton(text: primaryText!, onPressed: onPrimary!),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class Router1Background extends StatelessWidget {
  const Router1Background({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.0,
          colors: [Color(0xFF08241F), Router1Theme.bg],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _StarGlowPainter())),
          child,
        ],
      ),
    );
  }
}

class SetupHeader extends StatelessWidget {
  const SetupHeader({required this.title, this.onBack, super.key});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded, onTap: onBack!),
            ),
          Text(title,
              style: const TextStyle(
                  color: Router1Theme.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({required this.icon, required this.onTap, super.key});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0x66112029),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF18313D)),
        ),
        child: Icon(icon, color: Colors.white, size: 25),
      ),
    );
  }
}

class Router1Card extends StatelessWidget {
  const Router1Card(
      {required this.child,
      this.green = false,
      this.blue = false,
      this.accentColor,
      this.padding = const EdgeInsets.all(20),
      super.key});

  final Widget child;
  final bool green;
  final bool blue;
  final Color? accentColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final highlighted = green || blue || accentColor != null;
    final borderColor = accentColor ??
        (green ? Router1Theme.green : (blue ? Router1Theme.blue : Router1Theme.border));
    List<Color> gradientColors;
    if (green) {
      gradientColors = const [Color(0xCC0D5B2D), Color(0x6610212A)];
    } else if (blue) {
      gradientColors = const [Color(0xAA0A2D74), Color(0x5510212A)];
    } else if (accentColor != null) {
      gradientColors = [
        Color.alphaBlend(accentColor!.withValues(alpha: 0.34),
            const Color(0xFF0A1218)),
        const Color(0x6610212A),
      ];
    } else {
      gradientColors = const [Router1Theme.panel2, Color(0x88101C24)];
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: borderColor.withValues(alpha: highlighted ? 0.85 : 0.75),
            width: highlighted ? 1.7 : 1.0),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                    color: borderColor.withValues(alpha: 0.16), blurRadius: 28)
              ]
            : const [BoxShadow(color: Colors.black38, blurRadius: 20)],
      ),
      child: child,
    );
  }
}

class StatusOrb extends StatelessWidget {
  const StatusOrb(
      {this.size = 230,
      this.text = 'Интернет\nработает',
      this.accent = Router1Theme.green,
      super.key});

  final double size;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: accent.withValues(alpha: 0.5),
                    blurRadius: size * 0.32,
                    spreadRadius: size * 0.02),
              ],
            ),
          ),
          Image.asset('assets/illustrations/globe.png',
              width: size, height: size, fit: BoxFit.contain),
          if (text.isNotEmpty)
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Colors.black87, blurRadius: 12),
                      Shadow(color: Colors.black54, blurRadius: 22),
                    ])),
        ],
      ),
    );
  }
}

class RouterIllustration extends StatelessWidget {
  const RouterIllustration({this.size = 132, this.light = false, super.key});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child:
          Image.asset('assets/illustrations/router.png', fit: BoxFit.contain),
    );
  }
}

class GadgetIllustration extends StatelessWidget {
  const GadgetIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child:
          Image.asset('assets/illustrations/gadget.png', fit: BoxFit.contain),
    );
  }
}

class _StarGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Router1Theme.green.withValues(alpha: 0.16);
    for (var i = 0; i < 18; i++) {
      final x = (math.sin(i * 12.989) * 0.5 + 0.5) * size.width;
      final y = (math.cos(i * 7.77) * 0.5 + 0.5) * size.height;
      canvas.drawCircle(Offset(x, y), i.isEven ? 1.8 : 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2.25;
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        Router1Theme.green.withValues(alpha: 0.85),
        Router1Theme.green.withValues(alpha: 0.05)
      ]).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glow);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Router1Theme.green.withValues(alpha: 0.9);
    canvas.drawCircle(center, radius * 0.96, stroke);
    for (var i = 0; i < 26; i++) {
      final a = i * math.pi / 13;
      final r = radius * (0.25 + (i % 5) * 0.13);
      canvas.drawCircle(center + Offset(math.cos(a) * r, math.sin(a) * r), 1.5,
          Paint()..color = Router1Theme.green.withValues(alpha: 0.5));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RouterPainter extends CustomPainter {
  _RouterPainter({required this.light});

  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.08, size.height * 0.48, size.width * 0.84,
            size.height * 0.28),
        const Radius.circular(10));
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: light
            ? const [Color(0xFFECEFF2), Color(0xFF7C8791)]
            : const [Color(0xFF242A2E), Color(0xFF07090B)],
      ).createShader(body.outerRect);
    canvas.drawRRect(body, bodyPaint);
    final antenna = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(colors: [Colors.white, Color(0xFF6B7280)])
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawLine(Offset(size.width * 0.28, size.height * 0.5),
        Offset(size.width * 0.28, size.height * 0.1), antenna);
    canvas.drawLine(Offset(size.width * 0.72, size.height * 0.5),
        Offset(size.width * 0.72, size.height * 0.1), antenna);
    final lights = Paint()..color = Router1Theme.green;
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
          Offset(size.width * (0.43 + i * 0.08), size.height * 0.62),
          2.2,
          lights);
    }
  }

  @override
  bool shouldRepaint(covariant _RouterPainter oldDelegate) =>
      oldDelegate.light != light;
}

class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.button,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String button;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRouter = title == 'Роутер';
    return Router1Card(
      green: isRouter,
      blue: !isRouter,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (isRouter)
                const RouterIllustration(size: 150)
              else
                const GadgetIllustration(),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(title,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              letterSpacing: -0.5,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 8),
                    Text(description,
                        style: const TextStyle(
                            color: Color(0xFFD4D9DE),
                            fontSize: 19,
                            height: 1.35,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PrimaryButton(text: '$button  ›', onPressed: onTap, blue: !isRouter),
        ],
      ),
    );
  }
}

class DeveloperSettingsPage extends StatelessWidget {
  const DeveloperSettingsPage({
    required this.mode,
    required this.onModeChanged,
    required this.onBack,
    super.key,
  });

  final Router1RunMode mode;
  final ValueChanged<Router1RunMode> onModeChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final demo = mode == Router1RunMode.demo;
    return FlowScaffold(
      title: 'Настройки разработчика',
      subtitle:
          'TEST_MODE управляет тем, используем ли mock Keenetic или реальные запросы к роутеру.',
      onBack: onBack,
      primaryText: 'Готово',
      onPrimary: onBack,
      children: [
        Router1Card(
          child: Column(
            children: [
              SwitchListTile(
                value: demo,
                onChanged: (value) => onModeChanged(
                    value ? Router1RunMode.demo : Router1RunMode.real),
                activeThumbColor: Router1Theme.green,
                contentPadding: EdgeInsets.zero,
                title: const Text('Demo mode',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                subtitle: const Text(
                    'Mock: Router1 Keenetic Test / KN-xxxx / 192.168.1.1. Все шаги можно пройти без роутера.',
                    style: TextStyle(
                        color: Router1Theme.muted, fontSize: 16, height: 1.3)),
              ),
              const Divider(color: Color(0x221A3340)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(demo ? Icons.science : Icons.router,
                    color: demo ? Router1Theme.green : Router1Theme.blue),
                title: Text(
                    demo
                        ? 'Сейчас включен Demo mode'
                        : 'Сейчас включен Real mode',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                subtitle: Text(
                  demo
                      ? 'Реальные сетевые ошибки скрыты mock-ответами.'
                      : 'Успех засчитывается только после реального ответа Keenetic/API.',
                  style: const TextStyle(
                      color: Router1Theme.muted, fontSize: 16, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RouterConnectPage extends StatefulWidget {
  const RouterConnectPage({
    required this.service,
    required this.onAccess,
    required this.onLog,
    required this.onBack,
    super.key,
  });

  final KeeneticSetupService service;
  final ValueChanged<KeeneticAccess> onAccess;
  final ValueChanged<SetupLogEntry> onLog;
  final VoidCallback onBack;

  @override
  State<RouterConnectPage> createState() => _RouterConnectPageState();
}

class _RouterConnectPageState extends State<RouterConnectPage> {
  final address = TextEditingController();
  final login = TextEditingController(text: 'admin');
  final password = TextEditingController();
  var loading = false;
  String? error;

  @override
  void dispose() {
    address.dispose();
    login.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final host = address.text.trim();
    final user = login.text.trim().isEmpty ? 'admin' : login.text.trim();
    final pass = password.text;
    final valid =
        RegExp(r'^([a-zA-Z0-9.-]+|\d{1,3}(?:\.\d{1,3}){3})$').hasMatch(host);
    if (!valid) {
      setState(() => error = 'Введите адрес роутера или KeenDNS.');
      return;
    }
    if (pass.isEmpty) {
      setState(() => error = 'Введите пароль администратора роутера.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final access = await widget.service.authenticate(
        router: KeeneticRouter.manual(ip: host),
        login: user,
        password: pass,
        testMode: false,
      );
      widget.onLog(SetupLogEntry(
          title: 'Роутер найден',
          message: '${access.router.model}, ${access.router.ip}',
          level: SetupLogLevel.success,
          time: DateTime.now()));
      widget.onAccess(access);
    } catch (e) {
      final message = e is KeeneticSetupException ? e.message : e.toString();
      widget.onLog(SetupLogEntry(
          title: 'Ошибка подключения',
          message: message,
          level: SetupLogLevel.error,
          time: DateTime.now()));
      setState(() =>
          error = 'Не удалось подключиться. Проверьте адрес, логин и пароль.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Подключение\nк роутеру',
      subtitle: 'Введите данные администратора Keenetic.',
      onBack: widget.onBack,
      primaryText: loading ? 'Подключаемся...' : 'Подключиться',
      onPrimary: loading ? () {} : submit,
      children: [
        Router1Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RouterInputField(
                controller: address,
                label: 'Адрес роутера / KeenDNS',
                helper: 'например 192.168.1.1 или yu5re.keenetic.net',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 18),
              _RouterInputField(
                controller: login,
                label: 'Логин',
                helper: 'например admin',
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 18),
              _RouterInputField(
                controller: password,
                label: 'Пароль',
                helper: '',
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFFFB4B4),
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Диагностика сохранена для поддержки Router1.',
                    style: TextStyle(
                        color: Router1Theme.muted, fontSize: 14, height: 1.3)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RouterInputField extends StatelessWidget {
  const _RouterInputField({
    required this.controller,
    required this.label,
    required this.helper,
    required this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final TextInputType keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0x66112029),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        if (helper.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(helper,
              style: const TextStyle(
                  color: Router1Theme.muted, fontSize: 13, height: 1.25)),
        ],
      ],
    );
  }
}

class SearchRouterPage extends StatefulWidget {
  const SearchRouterPage(
      {required this.demoMode,
      required this.onFound,
      required this.onLogs,
      required this.onManual,
      required this.onBack,
      super.key});

  final bool demoMode;
  final ValueChanged<KeeneticRouter> onFound;
  final ValueChanged<List<String>> onLogs;
  final VoidCallback onManual;
  final VoidCallback onBack;

  @override
  State<SearchRouterPage> createState() => _SearchRouterPageState();
}

class _SearchRouterPageState extends State<SearchRouterPage> {
  final service = const KeeneticDiscoveryService();
  Future<KeeneticDiscoveryResult>? search;

  @override
  void initState() {
    super.initState();
    search = service.discover(demoMode: widget.demoMode);
  }

  void retry() {
    setState(() {
      search = service.discover(demoMode: widget.demoMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<KeeneticDiscoveryResult>(
      future: search,
      builder: (context, state) {
        final waiting = state.connectionState != ConnectionState.done;
        final result = state.data;
        final routers = result?.routers ?? const <KeeneticRouter>[];

        if (result != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onLogs(result.logs);
          });
        }

        if (routers.isNotEmpty) {
          return FlowScaffold(
            title: routers.length == 1
                ? 'Роутер найден'
                : 'Найдено роутеров: ${routers.length}',
            subtitle: 'Выберите устройство для диагностики',
            onBack: widget.onBack,
            primaryText: 'Продолжить настройку',
            onPrimary: () => widget.onFound(routers.first),
            children: [
              const Center(child: GlowingCheck(size: 108)),
              const SizedBox(height: 8),
              for (final item in routers)
                FoundRouterCard(
                    router: item, onTap: () => widget.onFound(item)),
              const OrDivider(),
              ActionGlassRow(
                  icon: Icons.search, title: 'Это не мой роутер', onTap: retry),
              ActionGlassRow(
                  icon: Icons.help_outline,
                  title: 'Не знаете какой выбрать?',
                  subtitle:
                      'Мы поможем определить ваш роутер\nи настроить его правильно.',
                  onTap: widget.onManual),
            ],
          );
        }

        return FlowScaffold(
          title: waiting ? 'Ищем роутер...' : 'Роутер не найден',
          subtitle: waiting
              ? widget.demoMode
                  ? 'Demo mode: используем mock Keenetic'
                  : 'Проверяем локальные адреса и KeenDNS'
              : 'Проверьте подключение к Wi-Fi роутера или введите адрес вручную',
          onBack: widget.onBack,
          primaryText: waiting ? 'Отменить поиск' : 'Повторить поиск',
          onPrimary: waiting ? () {} : retry,
          secondaryText: waiting ? null : 'Указать вручную',
          onSecondary: waiting ? null : widget.onManual,
          children: [
            const RadarRouter(),
            Router1Card(
              child: Column(
                children: [
                  const StepTile(
                      done: true,
                      title:
                          'Проверьте, что ваш телефон\nподключен к Wi‑Fi роутера'),
                  const StepTile(
                      done: true, title: 'Роутер должен быть включен'),
                  StepTile(
                      done: !waiting,
                      loading: waiting,
                      title: waiting
                          ? 'Проверяем 192.168.1.1, 192.168.0.1, my.keenetic.net, ir7ge.keenetic.pro'
                          : 'Поиск завершён'),
                ],
              ),
            ),
            if (result != null) DiagnosticLogCard(logs: result.logs),
          ],
        );
      },
    );
  }
}

class ManualRouterPage extends StatefulWidget {
  const ManualRouterPage(
      {required this.demoMode,
      required this.onRouter,
      required this.onLogs,
      required this.onBack,
      super.key});

  final bool demoMode;
  final ValueChanged<KeeneticRouter> onRouter;
  final ValueChanged<List<String>> onLogs;
  final VoidCallback onBack;

  @override
  State<ManualRouterPage> createState() => _ManualRouterPageState();
}

class _ManualRouterPageState extends State<ManualRouterPage> {
  final controller = TextEditingController();
  final service = const KeeneticDiscoveryService();
  var loading = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final value = controller.text.trim();
    final valid =
        RegExp(r'^([a-zA-Z0-9.-]+|\d{1,3}(?:\.\d{1,3}){3})$').hasMatch(value);
    if (!valid) {
      setState(() => error = 'Введите IP или доменное имя роутера.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final result = await service.probeManual(value, demoMode: widget.demoMode);
    widget.onLogs(result.logs);
    if (!mounted) return;
    setState(() => loading = false);
    if (result.router == null) {
      setState(() => error =
          widget.demoMode ? null : 'Роутер не ответил как Keenetic/API.');
      if (widget.demoMode) widget.onRouter(KeeneticRouter.demo());
      return;
    }
    widget.onRouter(result.router!);
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Укажите роутер вручную',
      subtitle:
          'Если авто-поиск не сработал, введите адрес KeenDNS или IP роутера.',
      onBack: widget.onBack,
      primaryText: loading ? 'Проверяем...' : 'Проверить роутер',
      onPrimary: loading ? () {} : submit,
      children: [
        Router1Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Адрес KeenDNS или IP роутера',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'Напишите адрес KeenDNS',
                  errorText: error,
                  filled: true,
                  fillColor: const Color(0x66112029),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                  'Авто-поиск проверяет локальные адреса и my.keenetic.net. Если у роутера есть удалённый доступ, введите его KeenDNS-адрес.',
                  style: TextStyle(
                      color: Router1Theme.muted, fontSize: 16, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

class SetupDiagnosticsPage extends StatelessWidget {
  const SetupDiagnosticsPage({
    required this.router,
    required this.logs,
    required this.demoMode,
    required this.onRetry,
    required this.onNext,
    required this.onBack,
    super.key,
  });

  final KeeneticRouter? router;
  final List<String> logs;
  final bool demoMode;
  final VoidCallback onRetry;
  final VoidCallback onNext;
  final VoidCallback onBack;

  Future<void> exportLog(BuildContext context) async {
    final text = [
      'Router1 diagnostics export',
      'mode=${demoMode ? 'demo' : 'real'}',
      'created_at=${DateTime.now().toIso8601String()}',
      if (router != null) ...[
        'router.address=${router!.ip}',
        'router.name=${router!.hostname ?? ''}',
        'router.model=${router!.model}',
        'router.keenetic_os=${router!.firmware ?? ''}',
        'router.api_available=${router!.apiAvailable}',
        'router.connection_type=${router!.connectionType}',
      ],
      '',
      ...logs,
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лог диагностики скопирован')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = router;
    final ok = item != null;
    final lastError = item?.lastError ??
        (item == null
            ? 'Роутер не найден'
            : item.readyForAutoSetup
                ? 'Нет'
                : item.compatibilityMessage);
    final apiStatus = demoMode
        ? 'mock: доступен'
        : item?.apiAuthenticated == true
            ? 'авторизован'
            : item?.apiAuthRequired == true
                ? 'требуется логин и пароль'
                : item?.apiAvailable == true
                    ? 'ответил'
                    : 'не подтвержден';

    return FlowScaffold(
      title: 'Диагностика настройки',
      subtitle: demoMode
          ? 'Demo mode показывает mock-статус.'
          : 'Real mode показывает только реальные ответы роутера.',
      onBack: onBack,
      primaryText: ok
          ? (item.readyForAutoSetup
              ? 'Продолжить настройку'
              : 'Продолжить к авторизации')
          : 'Повторить проверку',
      onPrimary: ok ? onNext : onRetry,
      secondaryText: 'Экспортировать лог',
      onSecondary: () => exportLog(context),
      children: [
        Router1Card(
          green: item?.readyForAutoSetup == true,
          child: Column(
            children: [
              DiagnosticRow(label: 'Адрес роутера', value: item?.ip ?? '-'),
              DiagnosticRow(
                  label: 'Название роутера', value: item?.hostname ?? '-'),
              DiagnosticRow(label: 'Модель', value: item?.model ?? '-'),
              DiagnosticRow(
                  label: 'KeeneticOS', value: item?.firmware ?? 'не получено'),
              DiagnosticRow(
                  label: 'Web Panel',
                  value: item?.webPanelDetected == true ? 'найдена' : '-'),
              DiagnosticRow(label: 'Доступ к API', value: apiStatus),
              DiagnosticRow(
                  label: 'Способ подключения',
                  value: item?.connectionType ?? '-'),
              DiagnosticRow(
                  label: 'Компонент WireGuard',
                  value: demoMode
                      ? 'mock: доступен'
                      : 'проверяется после авторизации'),
              DiagnosticRow(
                  label: 'Импорт AWG',
                  value: demoMode
                      ? 'mock: возможен'
                      : 'нужны команды/API KeeneticOS'),
              DiagnosticRow(
                  label: 'Статус туннеля',
                  value: demoMode ? 'mock: активен' : 'не создан'),
              DiagnosticRow(
                  label: 'Handshake',
                  value: demoMode ? 'mock: ok' : 'не проверялся'),
              DiagnosticRow(label: 'Ошибка последнего шага', value: lastError),
            ],
          ),
        ),
        DiagnosticLogCard(logs: logs),
      ],
    );
  }
}

class DiagnosticRow extends StatelessWidget {
  const DiagnosticRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x221A3340)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label,
                style: const TextStyle(
                    color: Router1Theme.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(value,
                textAlign: TextAlign.right,
                softWrap: true,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class DiagnosticLogCard extends StatelessWidget {
  const DiagnosticLogCard({required this.logs, super.key});

  final List<String> logs;

  Future<void> export(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: logs.join('\n')));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лог скопирован')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();
    final visible = logs.length > 10 ? logs.sublist(logs.length - 10) : logs;
    return Router1Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Лог диагностики',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900)),
              ),
              IconButton(
                onPressed: () => export(context),
                tooltip: 'Экспортировать лог',
                icon: const Icon(Icons.copy, color: Router1Theme.green),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(item,
                  style: const TextStyle(
                      color: Router1Theme.muted,
                      fontSize: 13,
                      height: 1.25,
                      fontFamily: 'monospace')),
            ),
        ],
      ),
    );
  }
}

class CompatibilityPage extends StatelessWidget {
  const CompatibilityPage(
      {required this.router,
      required this.onNext,
      required this.onBack,
      super.key});

  final KeeneticRouter? router;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final item = router ?? KeeneticRouter.manual();
    final ready = item.readyForAutoSetup;
    return FlowScaffold(
      title: 'Проверка совместимости',
      subtitle: item.compatibilityMessage,
      onBack: onBack,
      primaryText:
          ready ? 'Всё отлично, продолжить' : 'Продолжить к авторизации',
      onPrimary: onNext,
      children: [
        CompatibilityCard(router: item),
        ActionGlassRow(
            icon: Icons.info_outline,
            title: 'Почему мы это проверяем?',
            subtitle:
                'Это помогает убедиться, что ваш роутер\nготов к безопасной и стабильной работе.',
            onTap: () {}),
      ],
    );
  }
}

class BenefitsPage extends StatelessWidget {
  const BenefitsPage({required this.onNext, required this.onBack, super.key});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'С Router1\nвы получаете',
      subtitle: '',
      onBack: onBack,
      primaryText: 'Подключить Router1',
      onPrimary: onNext,
      children: const [
        Center(child: GlowingCheck(size: 108)),
        BenefitTile(
            icon: Icons.public,
            title: 'Стабильный и быстрый интернет',
            text: ''),
        BenefitTile(
            icon: Icons.sports_esports,
            title: 'Игровой режим без задержек',
            text: ''),
        BenefitTile(
            icon: Icons.auto_awesome,
            title: 'Нейросети без ограничений',
            text: ''),
        BenefitTile(
            icon: Icons.shield, title: 'Защита и конфиденциальность', text: ''),
        BenefitTile(
            icon: Icons.devices, title: 'Управление устройствами', text: ''),
        BenefitTile(
            icon: Icons.support_agent,
            title: 'Диагностика и поддержка 24/7',
            text: ''),
      ],
    );
  }
}

class RouterReadyForPaymentPage extends StatelessWidget {
  const RouterReadyForPaymentPage({
    required this.access,
    required this.onNext,
    required this.onBack,
    super.key,
  });

  final KeeneticAccess? access;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final router = access?.router ?? KeeneticRouter.manual();
    return FlowScaffold(
      title: 'Всё готово\nк установке',
      subtitle:
          'Роутер найден, доступ подтверждён. Если конфиг уже оплачен, Router1 сразу начнёт установку.',
      onBack: onBack,
      primaryText: 'Проверить оплату',
      onPrimary: onNext,
      children: [
        const Center(child: GlowingCheck(size: 108)),
        Router1Card(
          green: true,
          child: Column(
            children: [
              DiagnosticRow(
                  label: 'Название роутера',
                  value: router.hostname ?? router.model),
              DiagnosticRow(label: 'Модель', value: router.model),
              DiagnosticRow(label: 'Адрес', value: router.ip),
              DiagnosticRow(
                  label: 'KeeneticOS',
                  value: router.firmware ?? 'доступ подтверждён'),
              DiagnosticRow(
                  label: 'Доступ',
                  value: access == null ? 'не подтверждён' : 'подключено'),
            ],
          ),
        ),
        const BenefitTile(
            icon: Icons.route,
            title: 'Обычный интернет останется напрямую',
            text: ''),
        const BenefitTile(
            icon: Icons.play_circle,
            title:
                'YouTube, Telegram, Instagram, WhatsApp и нейронки пойдут через VPN',
            text: ''),
      ],
    );
  }
}

class ClientPhoneLookupPage extends StatefulWidget {
  const ClientPhoneLookupPage({
    required this.api,
    required this.initialName,
    required this.initialPhone,
    required this.onExistingConfig,
    required this.onNeedsPayment,
    required this.onLog,
    required this.onBack,
    super.key,
  });

  final Router1Api api;
  final String initialName;
  final String initialPhone;
  final void Function(String name, String phone, String configText)
      onExistingConfig;
  final void Function(String name, String phone) onNeedsPayment;
  final ValueChanged<SetupLogEntry> onLog;
  final VoidCallback onBack;

  @override
  State<ClientPhoneLookupPage> createState() => _ClientPhoneLookupPageState();
}

class _ClientPhoneLookupPageState extends State<ClientPhoneLookupPage> {
  late final TextEditingController nameController;
  late final TextEditingController phoneController;
  var loading = false;
  String? error;
  String? status;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(
        text: widget.initialName == 'Клиент Router1' ? '' : widget.initialName);
    phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final name = nameController.text.trim().isEmpty
        ? 'Клиент Router1'
        : nameController.text.trim();
    final phone = phoneController.text.trim();
    if (phone.replaceAll(RegExp(r'\D+'), '').length < 10) {
      setState(() => error = 'Введите телефон клиента.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
      status = 'Проверяем активный конфиг Router1...';
    });
    try {
      final lookup = await widget.api.findClientByPhone(phone);
      final config = lookup.recommendedConfig;
      if (config != null) {
        final text = await widget.api
            .fetchClientConfigText(phone: phone, deviceId: config.id);
        widget.onLog(SetupLogEntry(
            title: 'Активный конфиг',
            message: 'Найден активный конфиг ${config.deviceName}.',
            level: SetupLogLevel.success,
            time: DateTime.now()));
        widget.onExistingConfig(
            lookup.clientName.isEmpty ? name : lookup.clientName, phone, text);
        return;
      }
      widget.onLog(SetupLogEntry(
          title: 'Активный конфиг',
          message: 'Активный конфиг по телефону не найден.',
          level: SetupLogLevel.info,
          time: DateTime.now()));
      widget.onNeedsPayment(name, phone);
    } catch (_) {
      widget.onLog(SetupLogEntry(
          title: 'Активный конфиг',
          message: 'Клиент не найден или конфиг не активен.',
          level: SetupLogLevel.info,
          time: DateTime.now()));
      widget.onNeedsPayment(name, phone);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Кто\nподключается?',
      subtitle:
          'Если у клиента уже есть активный конфиг, установка начнётся без новой оплаты.',
      onBack: widget.onBack,
      primaryText: loading ? 'Проверяем...' : 'Продолжить',
      onPrimary: loading ? () {} : submit,
      children: [
        Router1Card(
          child: Column(
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Имя клиента',
                  hintStyle: const TextStyle(color: Router1Theme.muted),
                  filled: true,
                  fillColor: const Color(0x66112029),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Телефон клиента',
                  hintStyle: const TextStyle(color: Router1Theme.muted),
                  errorText: error,
                  filled: true,
                  fillColor: const Color(0x66112029),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: 12),
                Text(status!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Router1Theme.green,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class PaymentPage extends StatefulWidget {
  const PaymentPage({
    required this.api,
    required this.testMode,
    required this.initialName,
    required this.initialPhone,
    required this.onTestModeChanged,
    required this.onExistingConfig,
    required this.onPaid,
    required this.onBack,
    super.key,
  });

  final Router1Api api;
  final bool testMode;
  final String initialName;
  final String initialPhone;
  final ValueChanged<bool>? onTestModeChanged;
  final void Function(String name, String phone, String configText)
      onExistingConfig;
  final void Function(String name, String phone, String orderId) onPaid;
  final VoidCallback onBack;

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> with WidgetsBindingObserver {
  late final TextEditingController nameController;
  late final TextEditingController phoneController;
  Router1Order? order;
  String? error;
  String? status;
  var loading = false;
  Timer? pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    nameController = TextEditingController(
        text: widget.initialName == 'Клиент Router1' ? '' : widget.initialName);
    phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pollTimer?.cancel();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && order != null && !loading) {
      unawaited(checkPayment(manual: true));
    }
  }

  Future<void> pay() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    if (phone.isEmpty || phone.replaceAll(RegExp(r'\D+'), '').length < 10) {
      setState(() => error = 'Введите телефон клиента.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
      status = 'Сначала проверяем, нет ли уже оплаченного конфига...';
    });
    try {
      try {
        final lookup = await widget.api.findClientByPhone(phone);
        final config = lookup.recommendedConfig;
        if (config != null) {
          final text = await widget.api
              .fetchClientConfigText(phone: phone, deviceId: config.id);
          widget.onExistingConfig(
            lookup.clientName.isEmpty
                ? (name.isEmpty ? 'Клиент Router1' : name)
                : lookup.clientName,
            phone,
            text,
          );
          return;
        }
      } catch (_) {
        // No active config found, continue with a new payment.
      }
      if (mounted) {
        setState(() => status = 'Активный конфиг не найден. Создаём оплату...');
      }
      final created = await widget.api.createRouterOrder(
        name: name.isEmpty ? 'Клиент Router1' : name,
        phone: phone,
        testMode: widget.testMode,
      );
      setState(() {
        order = created;
        status =
            'Оплатите в браузере, вернитесь сюда и нажмите «Я оплатил — продолжить».';
      });
      final uri = Uri.tryParse(created.paymentUrl);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        setState(() {
          status =
              'Ссылка оплаты создана, но приложение не смогло открыть браузер.';
          error = null;
        });
      } else {
        try {
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!opened && mounted) {
            setState(() {
              status =
                  'Откройте ссылку ниже, оплатите и нажмите «Я оплатил — продолжить».';
              error = null;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              status =
                  'Откройте ссылку ниже, оплатите и нажмите «Я оплатил — продолжить».';
              error = null;
            });
          }
        }
      }
      startPolling();
    } catch (_) {
      setState(() {
        error =
            'Не удалось создать оплату. Проверьте интернет и попробуйте ещё раз.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void startPolling() {
    pollTimer?.cancel();
    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(checkPayment());
    });
    unawaited(checkPayment());
  }

  Future<void> checkPayment({bool manual = false}) async {
    final current = order;
    if (current == null) return;
    if (manual) {
      setState(() {
        loading = true;
        error = null;
        status = 'Проверяем оплату...';
      });
    }
    try {
      final value = await widget.api.orderStatus(current.orderId);
      if (value.paid && value.configReady) {
        pollTimer?.cancel();
        widget.onPaid(
          nameController.text.trim().isEmpty
              ? 'Клиент Router1'
              : nameController.text.trim(),
          phoneController.text.trim(),
          current.orderId,
        );
        return;
      }
      setState(() {
        status = value.paid
            ? 'Оплата получена. Готовим конфиг и запускаем установку.'
            : manual
                ? 'Оплата пока не подтверждена. Если платёж прошёл, подождите несколько секунд и нажмите ещё раз.'
                : 'Ждём подтверждение оплаты.';
      });
    } catch (_) {
      setState(() => status = manual
          ? 'Не удалось проверить оплату. Попробуйте ещё раз.'
          : 'Ждём подтверждение оплаты.');
    } finally {
      if (manual && mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Оплата Router1',
      subtitle:
          'После оплаты Router1 сам установит VPN на роутер и включит маршрутизацию: обычный интернет напрямую, YouTube, Telegram и нейросети через VPN.',
      onBack: widget.onBack,
      primaryText: loading
          ? order == null
              ? 'Проверяем...'
              : 'Проверяем оплату...'
          : order == null
              ? 'Проверить оплату или оплатить'
              : 'Я оплатил — продолжить',
      onPrimary: loading
          ? () {}
          : order == null
              ? pay
              : () => unawaited(checkPayment(manual: true)),
      children: [
        const PricePanel(title: 'Router1 для роутера', price: '10 ₽'),
        const BenefitTile(
            icon: Icons.install_mobile,
            title: 'Если уже оплатили, новая оплата не нужна',
            text:
                'Введите тот же телефон. Router1 найдёт активный конфиг и сразу начнёт установку. Если конфига нет — откроется оплата.'),
        Router1Card(
          child: Column(
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Имя клиента',
                  hintStyle: const TextStyle(color: Router1Theme.muted),
                  filled: true,
                  fillColor: const Color(0x66112029),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Телефон клиента',
                  errorText: error == null ? null : 'Ошибка ниже',
                  hintStyle: const TextStyle(color: Router1Theme.muted),
                  filled: true,
                  fillColor: const Color(0x66112029),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                SelectableText(
                  error!,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: Color(0xFFFFB4B4),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
              if (status != null) ...[
                const SizedBox(height: 10),
                Text(status!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Router1Theme.green,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
              if (order != null) ...[
                const SizedBox(height: 10),
                SelectableText(order!.paymentUrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Router1Theme.muted, fontSize: 13)),
              ],
            ],
          ),
        ),
        const Text(
          'Нажимая оплатить, вы соглашаетесь\nс офертой и политикой конфиденциальности',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: Router1Theme.muted, fontSize: 17, height: 1.35),
        ),
      ],
    );
  }
}

class RouterAccessPage extends StatefulWidget {
  const RouterAccessPage({
    required this.router,
    required this.service,
    required this.testMode,
    required this.onAccess,
    required this.onLog,
    required this.onBack,
    super.key,
  });

  final KeeneticRouter router;
  final KeeneticSetupService service;
  final bool testMode;
  final ValueChanged<KeeneticAccess> onAccess;
  final ValueChanged<SetupLogEntry> onLog;
  final VoidCallback onBack;

  @override
  State<RouterAccessPage> createState() => _RouterAccessPageState();
}

class _RouterAccessPageState extends State<RouterAccessPage> {
  final login = TextEditingController(text: 'admin');
  final password = TextEditingController();
  var loading = false;
  String? error;

  @override
  void dispose() {
    login.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final access = await widget.service.authenticate(
        router: widget.router,
        login: login.text.trim().isEmpty ? 'admin' : login.text.trim(),
        password: password.text,
        testMode: widget.testMode,
      );
      widget.onLog(SetupLogEntry(
          title: 'Доступ к роутеру',
          message: 'Авторизация выполнена: ${widget.router.ip}',
          level: SetupLogLevel.success,
          time: DateTime.now()));
      widget.onAccess(access);
    } catch (e) {
      final message = e is KeeneticSetupException ? e.message : e.toString();
      widget.onLog(SetupLogEntry(
          title: 'Ошибка доступа',
          message: message,
          level: SetupLogLevel.error,
          time: DateTime.now()));
      setState(() => error = message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Доступ к роутеру',
      subtitle: 'Введите логин и пароль администратора Keenetic.',
      onBack: widget.onBack,
      primaryText: loading ? 'Проверяем...' : 'Подключиться',
      onPrimary: loading ? () {} : submit,
      children: [
        FoundRouterCard(router: widget.router),
        Router1Card(
          child: Column(
            children: [
              TextField(
                controller: login,
                style: const TextStyle(color: Colors.white, fontSize: 20),
                decoration: InputDecoration(
                    labelText: 'Логин',
                    filled: true,
                    fillColor: const Color(0x66112029),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16))),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: password,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 20),
                decoration: InputDecoration(
                    labelText: 'Пароль',
                    errorText: error,
                    filled: true,
                    fillColor: const Color(0x66112029),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16))),
              ),
              if (widget.testMode) ...[
                const SizedBox(height: 14),
                const Text(
                    'Тестовый режим включен: можно продолжить без реального роутера.',
                    style: TextStyle(
                        color: Router1Theme.green, fontSize: 16, height: 1.3)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class WireGuardComponentPage extends StatefulWidget {
  const WireGuardComponentPage({
    required this.access,
    required this.service,
    required this.demoMode,
    required this.onReady,
    required this.onLog,
    required this.onBack,
    super.key,
  });

  final KeeneticAccess? access;
  final KeeneticSetupService service;
  final bool demoMode;
  final VoidCallback onReady;
  final ValueChanged<SetupLogEntry> onLog;
  final VoidCallback onBack;

  @override
  State<WireGuardComponentPage> createState() => _WireGuardComponentPageState();
}

class _WireGuardComponentPageState extends State<WireGuardComponentPage> {
  WireGuardComponentStatus? status;
  var loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    final access = widget.access;
    if (access == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.service.checkWireGuardComponent(access);
      widget.onLog(SetupLogEntry(
          title: 'WireGuard',
          message: value.message,
          level:
              value.installed ? SetupLogLevel.success : SetupLogLevel.warning,
          time: DateTime.now()));
      setState(() => status = value);
    } catch (e) {
      final message = e is KeeneticSetupException ? e.message : e.toString();
      widget.onLog(SetupLogEntry(
          title: 'Ошибка WireGuard',
          message: message,
          level: SetupLogLevel.error,
          time: DateTime.now()));
      setState(() => error = message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> install() async {
    final access = widget.access;
    if (access == null) return;
    setState(() => loading = true);
    try {
      final value = await widget.service.installWireGuardComponent(access);
      widget.onLog(SetupLogEntry(
          title: 'WireGuard',
          message: value.message,
          level: SetupLogLevel.success,
          time: DateTime.now()));
      setState(() => status = value);
    } catch (e) {
      final message = e is KeeneticSetupException ? e.message : e.toString();
      widget.onLog(SetupLogEntry(
          title: 'Установка WireGuard',
          message: message,
          level: SetupLogLevel.warning,
          time: DateTime.now()));
      setState(() => error = message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = status;
    return FlowScaffold(
      title: 'Компонент WireGuard',
      subtitle: 'Проверяем, готов ли Keenetic принять AmneziaWG-конфиг.',
      onBack: widget.onBack,
      primaryText: item?.installed == true
          ? 'Компонент готов'
          : (loading ? 'Проверяем...' : 'Установить WireGuard'),
      onPrimary: item?.installed == true
          ? widget.onReady
          : (loading ? () {} : install),
      secondaryText: item?.installed == true || !widget.demoMode
          ? null
          : 'Продолжить с подсказкой',
      onSecondary:
          item?.installed == true || !widget.demoMode ? null : widget.onReady,
      children: [
        Router1Card(
          green: item?.installed == true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StepTile(
                  done: item != null,
                  loading: loading,
                  title: 'Проверка компонента WireGuard'),
              StepTile(
                  done: item?.installed == true,
                  title: item?.message ?? 'Ожидаем ответ роутера'),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFFFB86B), fontSize: 16, height: 1.35)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class AwgImportPage extends StatefulWidget {
  const AwgImportPage(
      {required this.api,
      required this.initialPhone,
      required this.onConfig,
      required this.onBack,
      super.key});

  final Router1Api api;
  final String initialPhone;
  final ValueChanged<String> onConfig;
  final VoidCallback onBack;

  @override
  State<AwgImportPage> createState() => _AwgImportPageState();
}

class _AwgImportPageState extends State<AwgImportPage> {
  final controller = TextEditingController(text: sampleAwgConfig);
  late final TextEditingController phoneController;
  String? error;
  String? status;
  var loadingClientConfig = false;

  @override
  void initState() {
    super.initState();
    phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    controller.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> loadClientConfig() async {
    final phone = phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => error = 'Введите телефон клиента.');
      return;
    }
    if (const String.fromEnvironment('ROUTER1_APP_TOKEN').isEmpty) {
      setState(() => error =
          'В этой сборке нет токена Router1 API. Соберите APK с ROUTER1_APP_TOKEN.');
      return;
    }
    setState(() {
      loadingClientConfig = true;
      error = null;
      status = null;
    });
    try {
      final lookup = await widget.api.findClientByPhone(phone);
      final config = lookup.recommendedConfig;
      if (config == null) {
        setState(() => error = 'У клиента нет активного конфига для роутера.');
        return;
      }
      final text = await widget.api
          .fetchClientConfigText(phone: phone, deviceId: config.id);
      setState(() {
        controller.text = text;
        status = 'Загружен конфиг: ${lookup.clientName}, ${config.deviceName}.';
      });
    } catch (e) {
      setState(() => error = 'Не удалось получить конфиг Router1: $e');
    } finally {
      if (mounted) {
        setState(() => loadingClientConfig = false);
      }
    }
  }

  void submit() {
    final text = controller.text.trim();
    final looksValid = text.toLowerCase().contains('[interface]') &&
        text.toLowerCase().contains('[peer]') &&
        text.toLowerCase().contains('endpoint');
    if (!looksValid) {
      setState(() => error = 'Вставьте полный AmneziaWG/WireGuard конфиг.');
      return;
    }
    widget.onConfig(text);
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Загрузка AWG-конфига',
      subtitle: 'В MVP можно вставить тестовый или выданный сервером конфиг.',
      onBack: widget.onBack,
      primaryText: 'Создать подключение AWG',
      onPrimary: submit,
      children: [
        Router1Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Телефон клиента',
                  hintStyle: const TextStyle(color: Router1Theme.muted),
                  filled: true,
                  fillColor: const Color(0x66112029),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: loadingClientConfig ? null : loadClientConfig,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Router1Theme.border),
                    foregroundColor: Router1Theme.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    loadingClientConfig
                        ? 'Загружаем...'
                        : 'Получить конфиг из Router1',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: 10),
                Text(status!,
                    style: const TextStyle(
                        color: Router1Theme.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
        Router1Card(
          child: TextField(
            controller: controller,
            minLines: 10,
            maxLines: 16,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontFamily: 'monospace'),
            decoration: InputDecoration(
              errorText: error,
              filled: true,
              fillColor: const Color(0x66112029),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }
}

class PaidConfigLoadPage extends StatefulWidget {
  const PaidConfigLoadPage({
    required this.api,
    required this.orderId,
    required this.demoMode,
    required this.onConfig,
    required this.onLog,
    required this.onBack,
    super.key,
  });

  final Router1Api api;
  final String? orderId;
  final bool demoMode;
  final ValueChanged<String> onConfig;
  final ValueChanged<SetupLogEntry> onLog;
  final VoidCallback onBack;

  @override
  State<PaidConfigLoadPage> createState() => _PaidConfigLoadPageState();
}

class _PaidConfigLoadPageState extends State<PaidConfigLoadPage> {
  var loading = true;
  String? error;
  String? status;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      status = 'Получаем оплаченный AWG-конфиг...';
    });
    try {
      if (widget.demoMode) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        widget.onLog(SetupLogEntry(
            title: 'Оплаченный конфиг',
            message: 'Demo mode: используется тестовый AWG-конфиг.',
            level: SetupLogLevel.success,
            time: DateTime.now()));
        widget.onConfig(sampleAwgConfig);
        return;
      }
      final orderId = widget.orderId;
      if (orderId == null || orderId.isEmpty) {
        throw const FormatException('Нет номера оплаченного заказа.');
      }
      final text = await widget.api.fetchOrderConfigText(orderId);
      widget.onLog(SetupLogEntry(
          title: 'Оплаченный конфиг',
          message: 'Конфиг заказа $orderId загружен.',
          level: SetupLogLevel.success,
          time: DateTime.now()));
      widget.onConfig(text);
    } catch (e) {
      final message = 'Не удалось получить оплаченный конфиг: $e';
      widget.onLog(SetupLogEntry(
          title: 'Ошибка конфига',
          message: message,
          level: SetupLogLevel.error,
          time: DateTime.now()));
      setState(() {
        error = message;
        status = null;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Готовим установку',
      subtitle:
          'Оплата получена. Загружаем конфиг, который будет установлен на роутер.',
      onBack: widget.onBack,
      primaryText: error == null
          ? (loading ? 'Загружаем...' : 'Продолжить')
          : 'Повторить',
      onPrimary: error == null
          ? () {}
          : () {
              unawaited(load());
            },
      children: [
        Router1Card(
          green: error == null,
          child: Column(
            children: [
              StepTile(
                  done: !loading && error == null,
                  loading: loading,
                  title: status ?? error ?? 'Конфиг готов'),
            ],
          ),
        ),
      ],
    );
  }
}

class RouterRoutingProfilePage extends StatelessWidget {
  const RouterRoutingProfilePage({
    required this.profile,
    required this.routeProfileKind,
    required this.onChanged,
    required this.onRouteProfileChanged,
    required this.onNext,
    required this.onBack,
    super.key,
  });

  final RouterRoutingProfile profile;
  final Router1RouteProfileKind routeProfileKind;
  final ValueChanged<RouterRoutingProfile> onChanged;
  final ValueChanged<Router1RouteProfileKind> onRouteProfileChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Режим роутера',
      subtitle: 'Выберите, как Router1 будет направлять интернет.',
      onBack: onBack,
      primaryText: 'Применить настройку',
      onPrimary: onNext,
      children: [
        _RouteModeCard(
          icon: Icons.workspace_premium_rounded,
          accent: Router1Theme.gold,
          title: 'Gold Standard',
          description:
              'Telegram, WhatsApp и YouTube идут через VPN. Остальной интернет работает напрямую.',
          selected: profile == RouterRoutingProfile.selective &&
              routeProfileKind == Router1RouteProfileKind.goldStandard,
          onTap: () {
            onChanged(RouterRoutingProfile.selective);
            onRouteProfileChanged(Router1RouteProfileKind.goldStandard);
          },
        ),
        const SizedBox(height: 16),
        _RouteModeCard(
          icon: Icons.auto_awesome_rounded,
          accent: Router1Theme.purple,
          title: '+AI',
          description:
              'Gold Standard плюс ChatGPT, Claude, Gemini и другие нейросети. Может быть медленнее.',
          selected: profile == RouterRoutingProfile.selective &&
              routeProfileKind == Router1RouteProfileKind.ai,
          onTap: () {
            onChanged(RouterRoutingProfile.selective);
            onRouteProfileChanged(Router1RouteProfileKind.ai);
          },
        ),
        const SizedBox(height: 16),
        _RouteModeCard(
          icon: Icons.sports_esports_rounded,
          accent: Router1Theme.blue,
          title: 'For Gamers',
          description:
              'Gold Standard плюс игровые сервисы. Нейросети в этом режиме не добавляются.',
          selected: profile == RouterRoutingProfile.selective &&
              routeProfileKind == Router1RouteProfileKind.gamers,
          onTap: () {
            onChanged(RouterRoutingProfile.selective);
            onRouteProfileChanged(Router1RouteProfileKind.gamers);
          },
        ),
      ],
    );
  }
}

class _RouteModeCard extends StatelessWidget {
  const _RouteModeCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Router1Card(
        accentColor: selected ? accent : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: selected ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_circle_rounded,
                            color: accent, size: 18),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(description,
                      style: const TextStyle(
                          color: Router1Theme.muted,
                          fontSize: 14,
                          height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RouterSetupProgressPage extends StatefulWidget {
  const RouterSetupProgressPage({
    required this.access,
    required this.awgConfig,
    required this.paid,
    required this.routingProfile,
    required this.routeProfileKind,
    required this.api,
    required this.service,
    required this.logs,
    required this.onLog,
    required this.onDone,
    required this.onBack,
    super.key,
  });

  final KeeneticAccess? access;
  final String? awgConfig;
  final bool paid;
  final RouterRoutingProfile routingProfile;
  final Router1RouteProfileKind routeProfileKind;
  final Router1Api api;
  final KeeneticSetupService service;
  final List<SetupLogEntry> logs;
  final ValueChanged<SetupLogEntry> onLog;
  final VoidCallback onDone;
  final VoidCallback onBack;

  @override
  State<RouterSetupProgressPage> createState() =>
      _RouterSetupProgressPageState();
}

class _RouterSetupProgressPageState extends State<RouterSetupProgressPage> {
  var started = false;
  var imported = false;
  var created = false;
  var startedTunnel = false;
  var routingApplied = false;
  AwgConfigDetails? awgDetails;
  TunnelStatus? tunnel;
  String? error;
  String? manualScript;

  @override
  void initState() {
    super.initState();
    unawaited(run());
  }

  Future<void> run() async {
    if (started && error == null && tunnel == null) return;
    started = true;
    setState(() {
      error = null;
      imported = false;
      created = false;
      startedTunnel = false;
      routingApplied = false;
      awgDetails = null;
      tunnel = null;
      manualScript = null;
    });
    final access = widget.access;
    final config = widget.awgConfig;
    if (access == null || config == null || !widget.paid) {
      setState(() => error =
          'Не хватает данных для настройки: проверьте оплату, доступ и AWG-конфиг.');
      return;
    }
    Router1RouteProfile? routeProfile;
    try {
      final details = await widget.service.importAwgConfig(access, config);
      widget.onLog(SetupLogEntry(
          title: 'AWG-конфиг',
          message: details.summary,
          level: SetupLogLevel.success,
          time: DateTime.now()));
      for (final warning in details.warnings) {
        widget.onLog(SetupLogEntry(
            title: 'Проверка AWG',
            message: warning,
            level: SetupLogLevel.warning,
            time: DateTime.now()));
      }
      if (!details.hasIpv6Address) {
        widget.onLog(SetupLogEntry(
            title: 'IPv6-safe режим',
            message:
                'Конфиг IPv4-only. Для доменных маршрутов будет включён reject/auto, чтобы сервисы не уходили мимо VPN по IPv6.',
            level: SetupLogLevel.warning,
            time: DateTime.now()));
      }
      setState(() {
        imported = true;
        awgDetails = details;
      });

      await widget.service.createAwgConnection(access, config);
      widget.onLog(SetupLogEntry(
          title: 'Подключение AWG',
          message: 'Подключение создано на роутере.',
          level: SetupLogLevel.success,
          time: DateTime.now()));
      setState(() => created = true);

      final value = await widget.service.startAndCheckTunnel(access);
      widget.onLog(SetupLogEntry(
          title: 'Handshake',
          message: value.message,
          level:
              value.handshakeOk ? SetupLogLevel.success : SetupLogLevel.warning,
          time: DateTime.now()));
      setState(() {
        startedTunnel = value.active;
        tunnel = value;
      });

      if (value.handshakeOk) {
        if (widget.routingProfile == RouterRoutingProfile.selective) {
          try {
            routeProfile = await widget.api.routerRouteProfile(
              profile: widget.routeProfileKind,
            );
            widget.onLog(SetupLogEntry(
                title: 'Профиль маршрутов',
                message:
                    'Получен серверный профиль ${routeProfile.profileId} ${routeProfile.version}: ${widget.routeProfileKind.title}.',
                level: SetupLogLevel.success,
                time: DateTime.now()));
          } catch (_) {
            widget.onLog(SetupLogEntry(
                title: 'Профиль маршрутов',
                message:
                    'Серверный профиль недоступен, применяем встроенный fallback.',
                level: SetupLogLevel.warning,
                time: DateTime.now()));
          }
        }
        await widget.service.applyRoutingProfile(
          access,
          widget.routingProfile,
          routeProfile,
        );
        widget.onLog(SetupLogEntry(
            title: 'Маршрутизация Router1',
            message: widget.routingProfile == RouterRoutingProfile.fullTunnel
                ? 'Включен экспериментальный full tunnel: весь интернет идёт через VPN.'
                : '${widget.routeProfileKind.title}: ${widget.routeProfileKind.description}',
            level: SetupLogLevel.success,
            time: DateTime.now()));
        setState(() => routingApplied = true);
        await sendRouterDiagnostics(
          access: access,
          routeProfile: routeProfile,
          stage: 'success',
        );
      }
    } catch (e) {
      final message = e is KeeneticSetupException ? e.message : e.toString();
      String? fallback;
      if (!access.testMode) {
        try {
          fallback = widget.service.buildKeeneticManualScript(config);
        } catch (_) {
          fallback = null;
        }
      }
      widget.onLog(SetupLogEntry(
          title: 'Ошибка настройки',
          message: message,
          level: SetupLogLevel.error,
          time: DateTime.now()));
      await sendRouterDiagnostics(
        access: access,
        routeProfile: routeProfile,
        stage: 'error',
        error: message,
      );
      setState(() {
        error = message;
        manualScript = fallback;
      });
    }
  }

  Future<void> sendRouterDiagnostics({
    required KeeneticAccess access,
    required Router1RouteProfile? routeProfile,
    required String stage,
    String? error,
  }) async {
    try {
      final payload = await widget.service.collectDiagnostics(
        access,
        routingProfile: widget.routingProfile,
        routeProfile: routeProfile,
        appVersion: router1AppVersion,
        stage: stage,
        error: error,
      );
      final id = await widget.api.submitRouterDiagnostics(payload);
      if (id.isNotEmpty) {
        widget.onLog(SetupLogEntry(
            title: 'Диагностика',
            message: 'Отправлена на сервер: $id.',
            level: SetupLogLevel.success,
            time: DateTime.now()));
      }
    } catch (e) {
      widget.onLog(SetupLogEntry(
          title: 'Диагностика',
          message: 'Не удалось отправить диагностику: $e.',
          level: SetupLogLevel.warning,
          time: DateTime.now()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = tunnel?.handshakeOk == true && routingApplied;
    return FlowScaffold(
      title: done ? 'Интернет работает' : 'Настраиваем роутер',
      subtitle: done
          ? 'Нужные сервисы идут через VPN, остальной интернет не перехвачен.'
          : 'Создаем подключение, проверяем туннель и применяем маршрутизацию.',
      onBack: widget.onBack,
      primaryText: done ? 'Открыть Router1' : 'Повторить проверку',
      onPrimary: done ? widget.onDone : run,
      children: [
        Router1Card(
          green: done,
          child: Column(
            children: [
              StepTile(done: widget.paid, title: 'Оплата получена'),
              StepTile(
                  done: imported,
                  loading: !imported && error == null,
                  title: awgDetails?.summary ?? 'AWG-конфиг загружен'),
              StepTile(
                  done: created,
                  loading: imported && !created && error == null,
                  title: 'Подключение AWG создано'),
              StepTile(
                  done: startedTunnel,
                  loading: created && !startedTunnel && error == null,
                  title: tunnel?.message ??
                      'Проверка handshake / статуса туннеля'),
              StepTile(
                  done: routingApplied,
                  loading: startedTunnel && !routingApplied && error == null,
                  title:
                      'Маршруты для YouTube, Telegram, Instagram, WhatsApp и нейронок'),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFFF8A80), fontSize: 16, height: 1.35)),
              ],
            ],
          ),
        ),
        if (manualScript != null) ManualScriptCard(script: manualScript!),
        SetupLogPanel(logs: widget.logs),
      ],
    );
  }
}

class ManualScriptCard extends StatelessWidget {
  const ManualScriptCard({required this.script, super.key});

  final String script;

  @override
  Widget build(BuildContext context) {
    return Router1Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Ручной fallback для Keenetic',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
              ),
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: script)),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Копировать'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x66112029),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Router1Theme.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(script,
                  style: const TextStyle(
                      color: Router1Theme.muted,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.35)),
            ),
          ),
        ],
      ),
    );
  }
}

class SetupLogPanel extends StatelessWidget {
  const SetupLogPanel({required this.logs, super.key});

  final List<SetupLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();
    final visible = logs.reversed.take(6).toList();
    return Router1Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Журнал ошибок и событий',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Text('${item.title}: ${item.message}',
                  style: TextStyle(
                      color: _logColor(item.level), fontSize: 15, height: 1.3)),
            ),
        ],
      ),
    );
  }

  Color _logColor(SetupLogLevel level) {
    return switch (level) {
      SetupLogLevel.success => Router1Theme.green,
      SetupLogLevel.warning => const Color(0xFFFFD166),
      SetupLogLevel.error => const Color(0xFFFF8A80),
      SetupLogLevel.info => Router1Theme.muted,
    };
  }
}

const sampleAwgConfig = '''
[Interface]
PrivateKey = test_private_key_replace_me
Address = 10.66.66.2/32
DNS = 1.1.1.1
Jc = 3
Jmin = 10
Jmax = 50
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = test_public_key_replace_me
PresharedKey = test_psk_replace_me
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 213.176.93.13:51820
PersistentKeepalive = 25
''';

class AutoSetupPage extends StatelessWidget {
  const AutoSetupPage({required this.onNext, required this.onBack, super.key});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Автонастройка',
      subtitle: 'Показываем каждый шаг, чтобы было понятно, что происходит.',
      onBack: onBack,
      primaryText: 'Завершить',
      onPrimary: onNext,
      children: const [
        StepTile(done: true, title: 'Создаём устройство'),
        StepTile(done: true, title: 'Добавляем маршрут'),
        StepTile(done: true, title: 'Включаем режим Нейросети'),
        StepTile(done: false, title: 'Проверяем подключение'),
      ],
    );
  }
}

class PlatformPage extends StatelessWidget {
  const PlatformPage(
      {required this.selected,
      required this.onSelect,
      required this.onNext,
      required this.onBack,
      super.key});

  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    const platforms = ['Android', 'iPhone', 'Windows', 'macOS', 'Linux'];
    return FlowScaffold(
      title: 'Выберите платформу',
      subtitle: 'Подготовим понятную инструкцию для вашего устройства.',
      onBack: onBack,
      primaryText: 'Продолжить',
      onPrimary: onNext,
      children: [
        for (final item in platforms)
          ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor:
                item == selected ? const Color(0xFFE7F7EF) : Colors.white,
            leading: Icon(item == selected ? Icons.check_circle : Icons.devices,
                color: const Color(0xFF0D7C66)),
            title:
                Text(item, style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => onSelect(item),
          ),
      ],
    );
  }
}

class GadgetPaymentPage extends StatefulWidget {
  const GadgetPaymentPage({
    required this.api,
    required this.platform,
    required this.initialName,
    required this.initialPhone,
    required this.onPaid,
    required this.onBack,
    super.key,
  });

  final Router1Api api;
  final String platform;
  final String initialName;
  final String initialPhone;
  final void Function(
    String name,
    String phone,
    String configText,
    String filename,
  ) onPaid;
  final VoidCallback onBack;

  @override
  State<GadgetPaymentPage> createState() => _GadgetPaymentPageState();
}

class _GadgetPaymentPageState extends State<GadgetPaymentPage>
    with WidgetsBindingObserver {
  late final TextEditingController nameController;
  late final TextEditingController phoneController;
  Router1Order? order;
  String? error;
  String? status;
  List<Router1ClientConfig> existingConfigs = const [];
  var buyNewConfirmed = false;
  var loading = false;
  Timer? pollTimer;

  bool get _isPhone =>
      widget.platform == 'Android' || widget.platform == 'iPhone';
  String get _product => _isPhone ? 'smartphone' : 'laptop';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    nameController = TextEditingController(
        text: widget.initialName == 'Клиент Router1' ? '' : widget.initialName);
    phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pollTimer?.cancel();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && order != null && !loading) {
      unawaited(checkPayment(manual: true));
    }
  }

  Future<void> pay() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    if (phone.isEmpty || phone.replaceAll(RegExp(r'\D+'), '').length < 10) {
      setState(() => error = 'Введите телефон клиента.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
      status = buyNewConfirmed
          ? 'Создаём оплату...'
          : 'Проверяем оплаченные конфиги...';
    });
    try {
      if (!buyNewConfirmed) {
        try {
          final lookup = await widget.api.findClientByPhone(phone);
          final configs = lookup.gadgetConfigs;
          if (configs.isNotEmpty) {
            setState(() {
              existingConfigs = configs;
              status =
                  'У этого телефона уже есть оплаченный конфиг. Можно скачать его или купить новый для другого устройства.';
            });
            return;
          }
        } catch (_) {
          // Клиент может быть новым, тогда продолжаем обычную оплату.
        }
      }
      final created = await widget.api.createDeviceOrder(
        product: _product,
        name: name.isEmpty ? 'Клиент Router1' : name,
        phone: phone,
      );
      setState(() {
        order = created;
        existingConfigs = const [];
        buyNewConfirmed = false;
        status =
            'Оплатите в браузере, вернитесь сюда и нажмите «Я оплатил — получить конфиг».';
      });
      final uri = Uri.tryParse(created.paymentUrl);
      if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      startPolling();
    } catch (_) {
      setState(() {
        error = 'Не удалось создать оплату. Попробуйте ещё раз.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> downloadExisting(Router1ClientConfig config) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    setState(() {
      loading = true;
      error = null;
      status = 'Загружаем оплаченный конфиг...';
    });
    try {
      final configText = await widget.api.fetchClientConfigText(
        phone: phone,
        deviceId: config.id,
      );
      widget.onPaid(
        name.isEmpty ? 'Клиент Router1' : name,
        phone,
        configText,
        config.filename.isEmpty ? 'router1-${config.id}.conf' : config.filename,
      );
    } catch (_) {
      setState(() => error = 'Не удалось скачать оплаченный конфиг.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void buyNewDeviceConfig() {
    setState(() {
      buyNewConfirmed = true;
      existingConfigs = const [];
    });
    unawaited(pay());
  }

  void startPolling() {
    pollTimer?.cancel();
    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(checkPayment());
    });
    unawaited(checkPayment());
  }

  Future<void> checkPayment({bool manual = false}) async {
    final current = order;
    if (current == null) return;
    if (manual) {
      setState(() {
        loading = true;
        error = null;
        status = 'Проверяем оплату...';
      });
    }
    try {
      final value = await widget.api.orderStatus(current.orderId);
      if (value.paid && value.configReady) {
        final configText =
            await widget.api.fetchOrderConfigText(current.orderId);
        pollTimer?.cancel();
        widget.onPaid(
          nameController.text.trim().isEmpty
              ? 'Клиент Router1'
              : nameController.text.trim(),
          phoneController.text.trim(),
          configText,
          value.filename.isEmpty ? 'router1.conf' : value.filename,
        );
        return;
      }
      setState(() {
        status = value.paid
            ? 'Оплата получена. Готовим конфиг.'
            : manual
                ? 'Оплата пока не подтверждена. Подождите несколько секунд и нажмите ещё раз.'
                : 'Ждём подтверждение оплаты.';
      });
    } catch (_) {
      setState(() {
        status = manual
            ? 'Не удалось проверить оплату. Попробуйте ещё раз.'
            : 'Ждём подтверждение оплаты.';
      });
    } finally {
      if (manual && mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Подключение ${widget.platform}',
      subtitle:
          'После оплаты создадим персональный полный VPN-конфиг для всего устройства.',
      onBack: widget.onBack,
      primaryText: loading
          ? order == null
              ? 'Создаём оплату...'
              : 'Проверяем оплату...'
          : order == null
              ? 'Оплатить и получить конфиг'
              : 'Я оплатил — получить конфиг',
      onPrimary: loading
          ? () {}
          : order == null
              ? pay
              : () => unawaited(checkPayment(manual: true)),
      children: [
        PricePanel(
            title: _isPhone
                ? 'Router1 для смартфона'
                : 'Router1 для ноутбука / ПК',
            price: '5 ₽'),
        const BenefitTile(
            icon: Icons.vpn_key,
            title: 'Полный VPN для гаджета',
            text:
                'Весь интернет этого устройства будет идти через VPN. Для умной маршрутизации нужен роутер.'),
        if (existingConfigs.isNotEmpty)
          Router1Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Уже оплачено',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text(
                  'Один конфиг не может работать на двух устройствах одновременно.',
                  style: TextStyle(
                      color: Router1Theme.muted, fontSize: 14, height: 1.3),
                ),
                const SizedBox(height: 12),
                for (final config in existingConfigs) ...[
                  FilledButton.icon(
                    onPressed: loading
                        ? null
                        : () => unawaited(downloadExisting(config)),
                    icon: const Icon(Icons.download),
                    label: Text('Скачать: ${config.deviceName}'),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: loading ? null : buyNewDeviceConfig,
                  icon: const Icon(Icons.add),
                  label:
                      const Text('Купить новый конфиг для нового устройства'),
                ),
              ],
            ),
          ),
        Router1Card(
          child: Column(
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Имя клиента',
                  hintStyle: const TextStyle(color: Router1Theme.muted),
                  filled: true,
                  fillColor: const Color(0x66112029),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Телефон клиента',
                  hintStyle: const TextStyle(color: Router1Theme.muted),
                  filled: true,
                  fillColor: const Color(0x66112029),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFFFB4B4), fontSize: 13)),
              ],
              if (status != null) ...[
                const SizedBox(height: 10),
                Text(status!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Router1Theme.green,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
              if (order != null) ...[
                const SizedBox(height: 10),
                SelectableText(order!.paymentUrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Router1Theme.muted, fontSize: 13)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class GadgetInstructionPage extends StatelessWidget {
  const GadgetInstructionPage({
    required this.platform,
    required this.configText,
    required this.filename,
    required this.onBack,
    super.key,
  });

  final String platform;
  final String configText;
  final String filename;
  final VoidCallback onBack;

  Future<void> _shareConfigFile(BuildContext context) async {
    final dir = await getTemporaryDirectory();
    final safeName = filename.trim().isEmpty
        ? 'router1.conf'
        : filename.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsString(configText, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'Router1 AmneziaWG config',
        text: 'Откройте файл в AmneziaVPN: импорт из файла.',
      ),
    );
  }

  Uri get _clientAppUri {
    return Uri.parse('https://amnezia.org/downloads');
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Конфиг готов',
      subtitle: 'Сначала установите AmneziaVPN, затем импортируйте файл .conf.',
      onBack: onBack,
      primaryText: 'Скачать файл .conf',
      onPrimary: () => unawaited(_shareConfigFile(context)),
      secondaryText: 'Установить AmneziaVPN',
      onSecondary: () =>
          launchUrl(_clientAppUri, mode: LaunchMode.externalApplication),
      children: [
        PricePanel(title: filename, price: 'оплачено'),
        const BenefitTile(
            icon: Icons.install_mobile,
            title: 'Установите AmneziaVPN',
            text: 'Нажмите кнопку ниже, если приложение ещё не установлено.'),
        const BenefitTile(
            icon: Icons.description,
            title: 'Импортируйте файл',
            text:
                'В AmneziaVPN выберите импорт из файла и откройте скачанный .conf.'),
        const BenefitTile(
            icon: Icons.power_settings_new,
            title: 'Включите подключение',
            text: 'После импорта включите новый туннель Router1.'),
        Router1Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Технически',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text(
                'Если файл не открылся автоматически, скачайте его кнопкой выше и выберите AmneziaVPN вручную.',
                style: TextStyle(
                    color: Router1Theme.muted, fontSize: 14, height: 1.3),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: configText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Текст конфига скопирован')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Скопировать текст для поддержки'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SuccessPage extends StatelessWidget {
  const SuccessPage({required this.onNext, super.key});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return FirstRunPage(
      icon: Icons.check_circle,
      title: 'Готово',
      subtitle:
          'Router1 подключён. Теперь интернетом можно управлять из приложения.',
      primaryText: 'Открыть центр управления',
      onPrimary: onNext,
    );
  }
}

class FlowScaffold extends StatelessWidget {
  const FlowScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.primaryText,
    required this.onPrimary,
    required this.onBack,
    this.secondaryText,
    this.onSecondary,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final String primaryText;
  final VoidCallback onPrimary;
  final VoidCallback onBack;
  final String? secondaryText;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
      children: [
        SetupHeader(title: 'Настройка роутера', onBack: onBack),
        const SizedBox(height: 38),
        Text(title, textAlign: TextAlign.center, style: Router1Theme.title),
        const SizedBox(height: 10),
        Text(subtitle,
            textAlign: TextAlign.center, style: Router1Theme.subtitle),
        const SizedBox(height: 30),
        ...children.map((child) =>
            Padding(padding: const EdgeInsets.only(bottom: 10), child: child)),
        const SizedBox(height: 22),
        PrimaryButton(text: primaryText, onPressed: onPrimary),
        if (secondaryText != null && onSecondary != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: onSecondary,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Router1Theme.border),
                foregroundColor: const Color(0xFF7B86FF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(secondaryText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
      {required this.text,
      required this.onPressed,
      this.blue = false,
      super.key});

  final String text;
  final VoidCallback onPressed;
  final bool blue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: blue ? Router1Theme.blue : Router1Theme.green,
          foregroundColor: blue ? Colors.white : const Color(0xFF06100A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class StepTile extends StatelessWidget {
  const StepTile(
      {required this.done,
      required this.title,
      this.loading = false,
      super.key});

  final bool done;
  final String title;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x221A3340)))),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                    color: Router1Theme.green, strokeWidth: 4))
          else
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                  color: Router1Theme.green, shape: BoxShape.circle),
              child: Icon(done ? Icons.check : Icons.more_horiz,
                  color: const Color(0xFF051007), size: 28),
            ),
          const SizedBox(width: 18),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      height: 1.3,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Router1Card(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Router1Theme.muted, fontSize: 16))),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class BenefitTile extends StatelessWidget {
  const BenefitTile(
      {required this.icon, required this.title, required this.text, super.key});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Router1Card(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(icon,
              color: icon == Icons.sports_esports || icon == Icons.auto_awesome
                  ? const Color(0xFF9B6BFF)
                  : Router1Theme.green,
              size: 36),
          const SizedBox(width: 20),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class PricePanel extends StatelessWidget {
  const PricePanel({required this.title, required this.price, super.key});

  final String title;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Router1Card(
      green: true,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900))),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    color: Router1Theme.green.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12)),
                child: const Text('Выгодно',
                    style: TextStyle(
                        color: Router1Theme.green,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(price,
              style: const TextStyle(
                  color: Router1Theme.green,
                  fontSize: 43,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          const Divider(color: Color(0x334CFF7C)),
          const SizedBox(height: 14),
          const CheckLine(text: 'Все режимы и локации'),
          const CheckLine(text: 'Приоритетная поддержка'),
          const CheckLine(text: 'Первый месяц абонентской платы'),
        ],
      ),
    );
  }
}

class CheckLine extends StatelessWidget {
  const CheckLine({required this.text, this.ok = true, super.key});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? Router1Theme.green : const Color(0xFFFFB1A8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(ok ? Icons.check : Icons.priority_high,
                color: const Color(0xFF06100A), size: 26),
          ),
          const SizedBox(width: 18),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 22, height: 1.25))),
        ],
      ),
    );
  }
}

class GlowingCheck extends StatelessWidget {
  const GlowingCheck({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Router1Theme.green, width: 4),
        boxShadow: [
          BoxShadow(
              color: Router1Theme.green.withValues(alpha: 0.35), blurRadius: 28)
        ],
      ),
      child: const Icon(Icons.check, color: Router1Theme.green, size: 62),
    );
  }
}

class RadarRouter extends StatelessWidget {
  const RadarRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: const Size.square(330), painter: _RadarPainter()),
          const RouterIllustration(size: 170, light: true),
        ],
      ),
    );
  }
}

class FoundRouterCard extends StatelessWidget {
  const FoundRouterCard({required this.router, this.onTap, super.key});

  final KeeneticRouter router;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(router.hostname ?? router.model,
            softWrap: true,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(router.model,
            softWrap: true,
            style: const TextStyle(
                color: Router1Theme.muted,
                fontSize: 19,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.wifi, color: Router1Theme.green, size: 22),
            const SizedBox(width: 10),
            Expanded(
                child: Text(router.wifiName ?? router.connectionType,
                    softWrap: true,
                    style: const TextStyle(
                        color: Color(0xFFD5DCE1), fontSize: 20))),
          ],
        ),
        const SizedBox(height: 10),
        Text('${router.ip}\nдоступен\n${router.connectionType}',
            softWrap: true,
            style: const TextStyle(color: Color(0xFFD5DCE1), fontSize: 18)),
      ],
    );
    final card = Router1Card(
      green: router.readyForAutoSetup,
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: RouterIllustration(size: 140, light: true)),
                const SizedBox(height: 18),
                details,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RouterIllustration(size: 150, light: true),
              const SizedBox(width: 22),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: card,
    );
  }
}

class CompatibilityCard extends StatelessWidget {
  const CompatibilityCard({required this.router, super.key});

  final KeeneticRouter router;

  @override
  Widget build(BuildContext context) {
    final ready = router.readyForAutoSetup;
    return Router1Card(
      green: ready,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(router.model,
                      softWrap: true,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(router.firmware ?? router.compatibilityMessage,
                      softWrap: true,
                      style: const TextStyle(
                          color: Router1Theme.muted, fontSize: 22)),
                ],
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                        child: RouterIllustration(size: 140, light: true)),
                    const SizedBox(height: 18),
                    details,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const RouterIllustration(size: 150, light: true),
                  const SizedBox(width: 22),
                  Expanded(child: details),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Divider(color: Color(0x334CFF7C)),
          CheckLine(
              text: router.hasRealModel
                  ? 'Модель определена'
                  : 'Модель не определена',
              ok: router.hasRealModel),
          CheckLine(
              text: router.hasFirmware
                  ? 'Версия KeeneticOS получена'
                  : 'Версия KeeneticOS не получена',
              ok: router.hasFirmware),
          CheckLine(
              text: router.apiAuthenticated
                  ? 'API авторизован'
                  : router.needsAuth
                      ? 'Нужна авторизация администратора'
                      : 'API не подтвержден',
              ok: router.apiAuthenticated),
          CheckLine(
              text: ready
                  ? 'Автонастройка доступна'
                  : 'Автонастройка пока заблокирована',
              ok: ready),
        ],
      ),
    );
  }
}

class ActionGlassRow extends StatelessWidget {
  const ActionGlassRow(
      {required this.icon,
      required this.title,
      required this.onTap,
      this.subtitle,
      super.key});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Router1Card(
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: Router1Theme.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: Router1Theme.green, size: 34),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle!,
                        style: const TextStyle(
                            color: Router1Theme.muted,
                            fontSize: 17,
                            height: 1.35)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Router1Theme.muted, size: 32),
          ],
        ),
      ),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFF1C3038))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Text('или',
              style: TextStyle(
                  color: Router1Theme.muted,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ),
        Expanded(child: Divider(color: Color(0xFF1C3038))),
      ],
    );
  }
}

class _CompactLogo extends StatelessWidget {
  const _CompactLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                  text: 'ROUTER',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900)),
              TextSpan(
                  text: '1',
                  style: TextStyle(
                      color: Router1Theme.green,
                      fontSize: 38,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Умный интернет',
            style: TextStyle(
                color: Router1Theme.muted,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PagerDot extends StatelessWidget {
  const _PagerDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 24 : 16,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: active ? Router1Theme.green : const Color(0xFF1D3037),
        borderRadius: BorderRadius.circular(20),
        boxShadow: active
            ? [
                BoxShadow(
                    color: Router1Theme.green.withValues(alpha: 0.5),
                    blurRadius: 18)
              ]
            : null,
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width * 0.48;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Router1Theme.green.withValues(alpha: 0.75);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxR * i / 4, stroke);
    }
    final sweep = Paint()
      ..shader = SweepGradient(colors: [
        Router1Theme.green.withValues(alpha: 0),
        Router1Theme.green.withValues(alpha: 0.35)
      ]).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: maxR), -0.9, 0.7, true, sweep);
    canvas.drawCircle(center + Offset(maxR * 0.48, -maxR * 0.68), 10,
        Paint()..color = Router1Theme.green);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.router,
    required this.clientPhone,
    required this.paid,
    required this.onSetupRouter,
    required this.onSetupGadget,
    required this.onPay,
    this.routeProfileKind = Router1RouteProfileKind.goldStandard,
    super.key,
  });

  final KeeneticRouter? router;
  final String clientPhone;
  final bool paid;
  final VoidCallback onSetupRouter;
  final VoidCallback onSetupGadget;
  final VoidCallback onPay;
  final Router1RouteProfileKind routeProfileKind;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final api = Router1Api(
    baseUrl: 'https://router1.tech/api',
    token: const String.fromEnvironment('ROUTER1_APP_TOKEN'),
  );

  late Future<Router1Snapshot> snapshot;
  var localMode = RouterMode.ai;
  var refreshing = false;

  @override
  void initState() {
    super.initState();
    snapshot = api.snapshot().then((value) =>
        value.demoMode ? Router1Snapshot.demo(mode: localMode) : value);
  }

  Future<void> refresh() async {
    setState(() => refreshing = true);
    final next = api.snapshot().then((value) =>
        value.demoMode ? Router1Snapshot.demo(mode: localMode) : value);
    setState(() => snapshot = next);
    try {
      await next;
    } catch (_) {
      // ошибка уже показана как demo-фолбэк в snapshot()
    }
    if (!mounted) return;
    setState(() => refreshing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Проверка завершена'),
        duration: Duration(seconds: 2),
        backgroundColor: Router1Theme.panel2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Router1Background(
        child: SafeArea(
          child: FutureBuilder<Router1Snapshot>(
            future: snapshot,
            builder: (context, state) {
              final data = state.data ?? Router1Snapshot.demo();
              return DashboardPage(
                snapshot: data,
                router: widget.router,
                clientPhone: widget.clientPhone,
                paid: widget.paid,
                routeProfileKind: widget.routeProfileKind,
                refreshing: refreshing,
                onRefresh: refresh,
                onSetupRouter: widget.onSetupRouter,
                onSetupGadget: widget.onSetupGadget,
                onPay: widget.onPay,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> changeMode(RouterMode mode) async {
    localMode = mode;
    setState(() {
      snapshot = Future.value(Router1Snapshot.demo(mode: mode));
    });
    try {
      await api.setMode(mode);
      refresh();
    } catch (_) {
      setState(() {
        snapshot = Future.value(Router1Snapshot.demo(mode: mode));
      });
    }
  }
}

String routeModeShortTitle(Router1RouteProfileKind kind) {
  return switch (kind) {
    Router1RouteProfileKind.goldStandard => 'Standard',
    Router1RouteProfileKind.ai => '+AI',
    Router1RouteProfileKind.gamers => 'For Gamers',
  };
}

String routeModeTagline(Router1RouteProfileKind kind) {
  return switch (kind) {
    Router1RouteProfileKind.goldStandard =>
      'Обычный интернет + видеосервис + пару мессенджеров',
    Router1RouteProfileKind.ai =>
      'То же самое, плюс нейросети',
    Router1RouteProfileKind.gamers =>
      'То же самое, плюс игровые сервисы',
  };
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.snapshot,
    required this.router,
    required this.clientPhone,
    required this.paid,
    required this.onRefresh,
    required this.onSetupRouter,
    required this.onSetupGadget,
    required this.onPay,
    this.routeProfileKind = Router1RouteProfileKind.goldStandard,
    this.refreshing = false,
    super.key,
  });

  final Router1Snapshot snapshot;
  final KeeneticRouter? router;
  final String clientPhone;
  final bool paid;
  final VoidCallback onRefresh;
  final VoidCallback onSetupRouter;
  final VoidCallback onSetupGadget;
  final VoidCallback onPay;
  final Router1RouteProfileKind routeProfileKind;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final routerName = router?.hostname?.trim().isNotEmpty == true
        ? router!.hostname!.trim()
        : router?.model.trim().isNotEmpty == true
            ? router!.model.trim()
            : 'Keenetic';
    final serverName = snapshot.serverName == 'Оптимальный маршрут'
        ? 'NL2'
        : snapshot.serverName;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Router1',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(routerName,
                      style: const TextStyle(
                          color: Router1Theme.muted,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(
              onPressed: refreshing ? null : onRefresh,
              tooltip: 'Проверить сейчас',
              icon: refreshing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Router1Theme.green),
                    )
                  : const Icon(Icons.refresh, color: Router1Theme.green),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Router1Card(
          green: snapshot.connected,
          child: Column(
            children: [
              const StatusOrb(size: 190, text: 'Router1\nработает'),
              const SizedBox(height: 18),
              Text('Режим ${routeModeShortTitle(routeProfileKind)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(routeModeTagline(routeProfileKind),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Router1Theme.muted, fontSize: 14, height: 1.35)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Router1Card(
          child: Column(
            children: [
              HomeMetricLine(label: 'Сервер', value: serverName),
              const HomeMetricLine(
                  label: 'Последняя проверка', value: 'сейчас'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Router1Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Подписка',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                paid
                    ? 'Активна. Телефон ${clientPhone.isEmpty ? 'указан при оплате' : clientPhone}.'
                    : 'Подписку нужно оплатить или продлить.',
                style: const TextStyle(
                    color: Router1Theme.muted, fontSize: 16, height: 1.3),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onPay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Router1Theme.green,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(paid ? 'Продлить подписку' : 'Оплатить Router1',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: HomeActionCard(
                icon: Icons.router,
                color: Router1Theme.green,
                title: 'Обновить роутер',
                text: 'Переустановить конфиг или сменить режим',
                onTap: onSetupRouter,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: HomeActionCard(
                icon: Icons.devices,
                color: const Color(0xFF6EA8FF),
                title: 'Добавить гаджет',
                text: 'Ноутбук, ПК или телефон',
                onTap: onSetupGadget,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        HomeWideAction(
          icon: Icons.health_and_safety,
          title: 'Проверить и исправить',
          text: 'Диагностика сервера и доступности сервисов',
          onTap: refreshing ? () {} : onRefresh,
        ),
        const SizedBox(height: 12),
        HomeWideAction(
          icon: Icons.card_giftcard,
          title: 'Поделиться приложением с другом',
          text: 'Отправить ссылку на Router1',
          onTap: () {
            SharePlus.instance.share(
              ShareParams(
                subject: 'Router1 — умный интернет',
                text:
                    'Настрой домашний роутер за 5 минут с Router1: https://router1.tech/#download',
              ),
            );
          },
        ),
      ],
    );
  }
}

class HomeStatusLine extends StatelessWidget {
  const HomeStatusLine({
    required this.icon,
    required this.title,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Router1Theme.green, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Text(value,
              style: const TextStyle(
                  color: Router1Theme.green,
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class HomeMetricLine extends StatelessWidget {
  const HomeMetricLine({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: Router1Theme.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class HomeActionCard extends StatelessWidget {
  const HomeActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Router1Card(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 142,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const Spacer(),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.1,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Router1Theme.muted,
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeWideAction extends StatelessWidget {
  const HomeWideAction({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Router1Card(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Router1Theme.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Router1Theme.green, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(text,
                      style: const TextStyle(
                          color: Router1Theme.muted,
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Router1Theme.muted),
          ],
        ),
      ),
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({required this.onRefresh, super.key});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Router1 — умный интернет для Keenetic',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Режимы, диагностика и поддержка для всей домашней сети',
                  style: TextStyle(color: Color(0xFF66736F))),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Обновить',
        ),
      ],
    );
  }
}

class StatusPanel extends StatelessWidget {
  const StatusPanel({required this.snapshot, super.key});

  final Router1Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color =
        snapshot.connected ? const Color(0xFF0D7C66) : const Color(0xFFC2410C);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF10231F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                snapshot.connected ? 'Keenetic подключён' : 'Нет подключения',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(snapshot.serverName,
              style: const TextStyle(color: Color(0xFFDDE8E2), fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (snapshot.demoMode) ...[
                const Chip(
                  label: Text('Demo Mode'),
                  avatar: Icon(Icons.visibility, size: 18),
                  backgroundColor: Color(0xFFFFF7CC),
                ),
              ],
              Chip(
                label: Text(snapshot.mode.title),
                avatar: const Icon(Icons.auto_awesome, size: 18),
                backgroundColor: const Color(0xFFD9F99D),
              ),
              const Icon(Icons.router, color: Colors.white70),
            ],
          ),
        ],
      ),
    );
  }
}

class GridMetrics extends StatelessWidget {
  const GridMetrics({required this.snapshot, super.key});

  final Router1Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.55,
      children: [
        MetricCard(
            icon: Icons.download,
            label: 'Скорость',
            value: '${snapshot.downloadMbps.toStringAsFixed(1)} Мбит/с'),
        MetricCard(
            icon: Icons.network_ping,
            label: 'Задержка',
            value: '${snapshot.pingMs} мс'),
        MetricCard(
            icon: Icons.cloud_upload,
            label: 'Исходящая',
            value: '${snapshot.uploadMbps.toStringAsFixed(1)} Мбит/с'),
        MetricCard(
            icon: Icons.data_usage,
            label: 'Трафик',
            value: '${snapshot.trafficGb.toStringAsFixed(1)} ГБ'),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard(
      {required this.icon,
      required this.label,
      required this.value,
      super.key});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: const Color(0xFF0D7C66)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(color: Color(0xFF66736F), fontSize: 12)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class ModesPage extends StatelessWidget {
  const ModesPage({required this.snapshot, required this.onMode, super.key});

  final Router1Snapshot snapshot;
  final ValueChanged<RouterMode> onMode;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageTitle(title: 'Режимы'),
        const SizedBox(height: 12),
        for (final mode in RouterMode.values)
          ModeTile(
            mode: mode,
            active: mode == snapshot.mode,
            onTap: () => onMode(mode),
          ),
      ],
    );
  }
}

class ModeTile extends StatelessWidget {
  const ModeTile(
      {required this.mode,
      required this.active,
      required this.onTap,
      super.key});

  final RouterMode mode;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (mode) {
      RouterMode.normal => 'Для обычного интернета и стабильной работы',
      RouterMode.game => 'Минимальная задержка для игр и Discord',
      RouterMode.ai => 'ChatGPT, Claude, Gemini и другие нейросети',
      RouterMode.streaming =>
        'YouTube, видео и медиасервисы без лишних проблем',
      RouterMode.privacy => 'Повышенная приватность для всей домашней сети',
      RouterMode.domains => 'Свои правила для сайтов и сервисов',
    };
    return Card(
      elevation: 0,
      color: active ? const Color(0xFFE7F7EF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
            color: active ? const Color(0xFF0D7C66) : const Color(0xFFE2E8E5)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(_modeIcon(mode), color: const Color(0xFF0D7C66)),
        title: Text(mode.title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: active
            ? const Icon(Icons.check_circle, color: Color(0xFF0D7C66))
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  IconData _modeIcon(RouterMode mode) {
    return switch (mode) {
      RouterMode.normal => Icons.public,
      RouterMode.game => Icons.sports_esports,
      RouterMode.ai => Icons.auto_awesome,
      RouterMode.streaming => Icons.play_circle,
      RouterMode.privacy => Icons.shield,
      RouterMode.domains => Icons.rule,
    };
  }
}

class DevicesPage extends StatelessWidget {
  const DevicesPage({required this.snapshot, super.key});

  final Router1Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageTitle(title: 'Устройства'),
        const SizedBox(height: 12),
        for (final device in snapshot.devices)
          Card(
            elevation: 0,
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: ListTile(
              leading: Icon(_deviceIcon(device.type)),
              title: Text(device.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(device.online ? 'В сети' : 'Неактивно'),
              trailing: Icon(
                  device.online ? Icons.circle : Icons.circle_outlined,
                  size: 14,
                  color: device.online ? Colors.green : Colors.grey),
            ),
          ),
      ],
    );
  }

  IconData _deviceIcon(String type) {
    return switch (type) {
      'phone' => Icons.smartphone,
      'laptop' => Icons.laptop_mac,
      'tv' => Icons.tv,
      _ => Icons.router,
    };
  }
}

class SupportPage extends StatelessWidget {
  const SupportPage({required this.api, super.key});

  final Router1Api api;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageTitle(title: 'Поддержка'),
        const SizedBox(height: 12),
        ActionTile(
            icon: Icons.health_and_safety,
            title: 'Проверить подключение',
            subtitle: 'Понять, всё ли работает на Keenetic',
            onTap: () {}),
        ActionTile(
            icon: Icons.receipt_long,
            title: 'Отправить диагностику',
            subtitle: 'Передать логи и состояние Router1 в поддержку',
            onTap: () {}),
        ActionTile(
            icon: Icons.chat_bubble_outline,
            title: 'Написать в поддержку',
            subtitle: 'Получить помощь без технических объяснений',
            onTap: () {}),
        ActionTile(
            icon: Icons.restart_alt,
            title: 'Обновить подключение',
            subtitle: 'Мягко перезапустить соединение',
            onTap: api.restart),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.onRefresh, super.key});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageTitle(title: 'Настройки'),
        const SizedBox(height: 12),
        ActionTile(
            icon: Icons.router,
            title: 'Подключение к Keenetic',
            subtitle: 'Адрес роутера, токен и локальная диагностика',
            onTap: () {}),
        ActionTile(
            icon: Icons.dns,
            title: 'Выбор сервера',
            subtitle: 'Автоматический или ручной выбор ноды',
            onTap: () {}),
        ActionTile(
            icon: Icons.system_update_alt,
            title: 'Обновление',
            subtitle: 'Проверить компоненты Router1',
            onTap: onRefresh),
      ],
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      super.key});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0D7C66)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, required this.action, super.key});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800))),
        Text(action,
            style: const TextStyle(
                color: Color(0xFF0D7C66), fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800));
  }
}

class EventTile extends StatelessWidget {
  const EventTile({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8E5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF0D7C66)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
