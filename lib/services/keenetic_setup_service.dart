import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/keenetic_router.dart';
import '../router1_api.dart';

class _Ipv4Route {
  const _Ipv4Route(this.network, this.mask);

  final String network;
  final String mask;
}

class SetupLogEntry {
  const SetupLogEntry({
    required this.title,
    required this.message,
    required this.level,
    required this.time,
  });

  final String title;
  final String message;
  final SetupLogLevel level;
  final DateTime time;

  String get exportLine =>
      '${time.toIso8601String()} [$level] $title: $message';
}

enum SetupLogLevel { info, success, warning, error }

enum RouterRoutingProfile {
  selective,
  fullTunnel,
}

class KeeneticAccess {
  const KeeneticAccess({
    required this.router,
    required this.login,
    required this.password,
    required this.testMode,
  });

  final KeeneticRouter router;
  final String login;
  final String password;
  final bool testMode;
}

class WireGuardComponentStatus {
  const WireGuardComponentStatus({
    required this.available,
    required this.installed,
    required this.canInstall,
    required this.message,
  });

  final bool available;
  final bool installed;
  final bool canInstall;
  final String message;
}

class TunnelStatus {
  const TunnelStatus({
    required this.active,
    required this.handshakeOk,
    required this.message,
  });

  final bool active;
  final bool handshakeOk;
  final String message;
}

class AwgConfigDetails {
  const AwgConfigDetails({
    required this.interfaceAddress,
    required this.dns,
    required this.endpoint,
    required this.allowedIps,
    required this.persistentKeepalive,
    required this.hasAwgObfuscation,
    required this.warnings,
  });

  final String interfaceAddress;
  final String dns;
  final String endpoint;
  final String allowedIps;
  final String persistentKeepalive;
  final bool hasAwgObfuscation;
  final List<String> warnings;

  bool get fullTunnel =>
      allowedIps.split(',').map((item) => item.trim()).contains('0.0.0.0/0');

  bool get hasIpv6Address => interfaceAddress.contains(':');

  bool get routesIpv6 =>
      allowedIps.split(',').map((item) => item.trim()).contains('::/0');

  String get summary {
    final parts = <String>[
      'адрес $interfaceAddress',
      'endpoint $endpoint',
      fullTunnel ? 'full tunnel' : 'split tunnel',
      hasAwgObfuscation ? 'AWG параметры есть' : 'обычный WireGuard',
    ];
    return parts.join(', ');
  }
}

class KeeneticSetupService {
  KeeneticSetupService({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;
  final _selectedInterfaceByHost = <String, String>{};
  static const _telegramIpv4Routes = [
    _Ipv4Route('91.105.192.0', '255.255.254.0'),
    _Ipv4Route('91.108.0.0', '255.255.0.0'),
    _Ipv4Route('91.108.4.0', '255.255.252.0'),
    _Ipv4Route('91.108.8.0', '255.255.252.0'),
    _Ipv4Route('91.108.12.0', '255.255.252.0'),
    _Ipv4Route('91.108.16.0', '255.255.252.0'),
    _Ipv4Route('91.108.20.0', '255.255.252.0'),
    _Ipv4Route('91.108.56.0', '255.255.252.0'),
    _Ipv4Route('95.161.0.0', '255.255.0.0'),
    _Ipv4Route('95.161.64.0', '255.255.240.0'),
    _Ipv4Route('149.154.0.0', '255.255.0.0'),
    _Ipv4Route('149.154.160.0', '255.255.240.0'),
    _Ipv4Route('185.76.151.0', '255.255.255.0'),
  ];
  static const _telegramIpv6Routes = [
    '2001:67c:4e8::/48',
    '2001:b28:f23c::/47',
    '2001:b28:f23d::/48',
    '2001:b28:f23e::/48',
    '2001:b28:f23f::/48',
    '2a0a:f280::/32',
  ];
  // Статические IP-диапазоны Google (AS15169) и Cloudflare — маршрутизация
  // независимо от DNS клиента (десктопный DoH не ломает split-tunnel).
  // Источники: gstatic.com/ipranges/goog.json, cloudflare.com/ips-v4 (07.07.2026).
  static const _googleIpv4Routes = [
    _Ipv4Route('8.8.4.0', '255.255.255.0'),
    _Ipv4Route('8.8.8.0', '255.255.255.0'),
    _Ipv4Route('8.34.208.0', '255.255.240.0'),
    _Ipv4Route('8.35.192.0', '255.255.240.0'),
    _Ipv4Route('8.228.0.0', '255.252.0.0'),
    _Ipv4Route('8.232.0.0', '255.252.0.0'),
    _Ipv4Route('8.236.0.0', '255.254.0.0'),
    _Ipv4Route('23.236.48.0', '255.255.240.0'),
    _Ipv4Route('23.251.128.0', '255.255.224.0'),
    _Ipv4Route('34.0.0.0', '255.254.0.0'),
    _Ipv4Route('34.2.0.0', '255.255.0.0'),
    _Ipv4Route('34.3.0.0', '255.255.254.0'),
    _Ipv4Route('34.3.3.0', '255.255.255.0'),
    _Ipv4Route('34.3.4.0', '255.255.255.0'),
    _Ipv4Route('34.3.8.0', '255.255.248.0'),
    _Ipv4Route('34.3.16.0', '255.255.240.0'),
    _Ipv4Route('34.3.32.0', '255.255.224.0'),
    _Ipv4Route('34.3.64.0', '255.255.192.0'),
    _Ipv4Route('34.4.0.0', '255.252.0.0'),
    _Ipv4Route('34.8.0.0', '255.248.0.0'),
    _Ipv4Route('34.16.0.0', '255.240.0.0'),
    _Ipv4Route('34.32.0.0', '255.224.0.0'),
    _Ipv4Route('34.64.0.0', '255.192.0.0'),
    _Ipv4Route('34.128.0.0', '255.192.0.0'),
    _Ipv4Route('35.184.0.0', '255.248.0.0'),
    _Ipv4Route('35.192.0.0', '255.252.0.0'),
    _Ipv4Route('35.196.0.0', '255.254.0.0'),
    _Ipv4Route('35.198.0.0', '255.255.0.0'),
    _Ipv4Route('35.199.0.0', '255.255.128.0'),
    _Ipv4Route('35.199.128.0', '255.255.192.0'),
    _Ipv4Route('35.200.0.0', '255.248.0.0'),
    _Ipv4Route('35.208.0.0', '255.240.0.0'),
    _Ipv4Route('35.224.0.0', '255.240.0.0'),
    _Ipv4Route('35.240.0.0', '255.248.0.0'),
    _Ipv4Route('35.252.0.0', '255.252.0.0'),
    _Ipv4Route('64.15.112.0', '255.255.240.0'),
    _Ipv4Route('64.233.160.0', '255.255.224.0'),
    _Ipv4Route('66.102.0.0', '255.255.240.0'),
    _Ipv4Route('66.249.64.0', '255.255.224.0'),
    _Ipv4Route('70.32.128.0', '255.255.224.0'),
    _Ipv4Route('72.14.192.0', '255.255.192.0'),
    _Ipv4Route('74.114.24.0', '255.255.248.0'),
    _Ipv4Route('74.125.0.0', '255.255.0.0'),
    _Ipv4Route('104.154.0.0', '255.254.0.0'),
    _Ipv4Route('104.196.0.0', '255.252.0.0'),
    _Ipv4Route('104.237.160.0', '255.255.224.0'),
    _Ipv4Route('107.167.160.0', '255.255.224.0'),
    _Ipv4Route('107.178.192.0', '255.255.192.0'),
    _Ipv4Route('108.59.80.0', '255.255.240.0'),
    _Ipv4Route('108.170.192.0', '255.255.192.0'),
    _Ipv4Route('108.177.0.0', '255.255.128.0'),
    _Ipv4Route('130.211.0.0', '255.255.0.0'),
    _Ipv4Route('136.22.2.0', '255.255.254.0'),
    _Ipv4Route('136.22.4.0', '255.255.254.0'),
    _Ipv4Route('136.22.8.0', '255.255.252.0'),
    _Ipv4Route('136.22.160.0', '255.255.240.0'),
    _Ipv4Route('136.22.176.0', '255.255.248.0'),
    _Ipv4Route('136.22.184.0', '255.255.254.0'),
    _Ipv4Route('136.22.186.0', '255.255.255.0'),
    _Ipv4Route('136.23.48.0', '255.255.240.0'),
    _Ipv4Route('136.23.64.0', '255.255.192.0'),
    _Ipv4Route('136.64.0.0', '255.224.0.0'),
    _Ipv4Route('136.107.0.0', '255.255.0.0'),
    _Ipv4Route('136.108.0.0', '255.252.0.0'),
    _Ipv4Route('136.112.0.0', '255.248.0.0'),
    _Ipv4Route('136.120.0.0', '255.255.252.0'),
    _Ipv4Route('136.121.8.0', '255.255.248.0'),
    _Ipv4Route('136.124.0.0', '255.254.0.0'),
    _Ipv4Route('142.250.0.0', '255.254.0.0'),
    _Ipv4Route('146.148.0.0', '255.255.128.0'),
    _Ipv4Route('162.120.128.0', '255.255.128.0'),
    _Ipv4Route('162.216.148.0', '255.255.252.0'),
    _Ipv4Route('162.222.176.0', '255.255.248.0'),
    _Ipv4Route('172.110.32.0', '255.255.248.0'),
    _Ipv4Route('172.217.0.0', '255.255.0.0'),
    _Ipv4Route('172.253.0.0', '255.255.0.0'),
    _Ipv4Route('173.194.0.0', '255.255.0.0'),
    _Ipv4Route('173.255.112.0', '255.255.240.0'),
    _Ipv4Route('192.104.160.0', '255.255.254.0'),
    _Ipv4Route('192.158.28.0', '255.255.252.0'),
    _Ipv4Route('192.178.0.0', '255.254.0.0'),
    _Ipv4Route('193.186.4.0', '255.255.255.0'),
    _Ipv4Route('199.36.154.0', '255.255.254.0'),
    _Ipv4Route('199.36.156.0', '255.255.255.0'),
    _Ipv4Route('199.192.112.0', '255.255.252.0'),
    _Ipv4Route('199.223.232.0', '255.255.248.0'),
    _Ipv4Route('207.175.0.0', '255.255.0.0'),
    _Ipv4Route('207.223.160.0', '255.255.240.0'),
    _Ipv4Route('208.65.152.0', '255.255.252.0'),
    _Ipv4Route('208.68.108.0', '255.255.252.0'),
    _Ipv4Route('208.81.188.0', '255.255.252.0'),
    _Ipv4Route('208.117.224.0', '255.255.224.0'),
    _Ipv4Route('209.85.128.0', '255.255.128.0'),
    _Ipv4Route('216.58.192.0', '255.255.224.0'),
    _Ipv4Route('216.73.80.0', '255.255.240.0'),
    _Ipv4Route('216.239.32.0', '255.255.224.0'),
    _Ipv4Route('216.252.220.0', '255.255.252.0'),
  ];
  static const _cloudflareIpv4Routes = [
    _Ipv4Route('173.245.48.0', '255.255.240.0'),
    _Ipv4Route('103.21.244.0', '255.255.252.0'),
    _Ipv4Route('103.22.200.0', '255.255.252.0'),
    _Ipv4Route('103.31.4.0', '255.255.252.0'),
    _Ipv4Route('141.101.64.0', '255.255.192.0'),
    _Ipv4Route('108.162.192.0', '255.255.192.0'),
    _Ipv4Route('190.93.240.0', '255.255.240.0'),
    _Ipv4Route('188.114.96.0', '255.255.240.0'),
    _Ipv4Route('197.234.240.0', '255.255.252.0'),
    _Ipv4Route('198.41.128.0', '255.255.128.0'),
    _Ipv4Route('162.158.0.0', '255.254.0.0'),
    _Ipv4Route('104.16.0.0', '255.248.0.0'),
    _Ipv4Route('104.24.0.0', '255.252.0.0'),
    _Ipv4Route('172.64.0.0', '255.248.0.0'),
    _Ipv4Route('131.0.72.0', '255.255.252.0'),
  ];
  static const _mediaResolveDomains = [
    'www.youtube.com',
    'm.youtube.com',
    'youtubei.googleapis.com',
    'youtube.googleapis.com',
    'i.ytimg.com',
    'yt3.ggpht.com',
    'rr1---sn-n8v7kn7l.googlevideo.com',
    'rr2---sn-n8v7kn7l.googlevideo.com',
    'rr3---sn-n8v7kn7l.googlevideo.com',
    'rr4---sn-n8v7kn7l.googlevideo.com',
    'web.telegram.org',
    'venus.web.telegram.org',
    'pluto.web.telegram.org',
    'telegram.org',
    'api.telegram.org',
    'cdn1.telegram-cdn.org',
    'cdn2.telegram-cdn.org',
    'www.instagram.com',
    'scontent.cdninstagram.com',
    'web.whatsapp.com',
  ];
  static const _aiResolveDomains = [
    'chatgpt.com',
    'chat.openai.com',
    'ios.chat.openai.com',
    'auth.openai.com',
    'api.openai.com',
    'cdn.openai.com',
    'cdn.oaistatic.com',
    'persistent.oaistatic.com',
    'files.oaiusercontent.com',
    'challenges.cloudflare.com',
    'client-api.arkoselabs.com',
    'newassets.hcaptcha.com',
    'events.statsigapi.net',
    'claude.ai',
    'api.claude.ai',
    'claudeusercontent.com',
    'console.anthropic.com',
    'perplexity.ai',
    'gemini.google.com',
    'generativelanguage.googleapis.com',
    'copilot.microsoft.com',
    'edgeservices.bing.com',
  ];

  Future<KeeneticAccess> authenticate({
    required KeeneticRouter router,
    required String login,
    required String password,
    required bool testMode,
  }) async {
    if (testMode) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return KeeneticAccess(
          router: router, login: login, password: password, testMode: true);
    }

    final response = await _get(router.ip, '/rci/show/version',
        login: login, password: password);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const KeeneticSetupException('Роутер не принял логин или пароль.');
    }
    if (response.statusCode == 404) {
      throw const KeeneticSetupException(
          'RCI API Keenetic недоступен по этому адресу.');
    }
    if (response.statusCode >= 500) {
      throw KeeneticSetupException(
          'Keenetic ответил ошибкой ${response.statusCode}.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KeeneticSetupException(
          'Keenetic ответил HTTP ${response.statusCode}.');
    }
    final version = jsonDecode(response.body);
    final detectedRouter = version is Map<String, dynamic>
        ? _routerFromVersion(router, version)
        : router;
    return KeeneticAccess(
        router: detectedRouter,
        login: login,
        password: password,
        testMode: false);
  }

  Future<WireGuardComponentStatus> checkWireGuardComponent(
      KeeneticAccess access) async {
    if (access.testMode) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return const WireGuardComponentStatus(
        available: true,
        installed: false,
        canInstall: true,
        message: 'Компонент WireGuard можно установить автоматически.',
      );
    }

    final version = await _getJson(
      access.router.ip,
      '/rci/show/version',
      login: access.login,
      password: access.password,
    );
    final components =
        version is Map ? version['components']?.toString().toLowerCase() : '';
    var installed = _hasWireGuardComponent(components ?? '');
    if (!installed) {
      try {
        final interfaces = await _getJson(
          access.router.ip,
          '/rci/show/interface',
          login: access.login,
          password: access.password,
        );
        installed = _hasWireGuardInterface(interfaces);
      } catch (_) {
        installed = false;
      }
    }
    return WireGuardComponentStatus(
      available: true,
      installed: installed,
      canInstall: !installed,
      message: installed
          ? 'Компонент WireGuard уже установлен.'
          : 'Компонент WireGuard не найден.',
    );
  }

  Future<WireGuardComponentStatus> installWireGuardComponent(
    KeeneticAccess access, {
    void Function(String message)? onProgress,
  }) async {
    if (access.testMode) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return const WireGuardComponentStatus(
        available: true,
        installed: true,
        canInstall: false,
        message: 'WireGuard установлен в тестовом режиме.',
      );
    }

    var installQueued = false;
    KeeneticSetupException? lastUnavailable;
    for (var attempt = 0; attempt < 12; attempt++) {
      onProgress?.call(
        'Обновляем каталог компонентов Keenetic. Попытка ${attempt + 1} из 12...',
      );
      try {
        await _runCliCommands(access, ['components list'], ignoreErrors: true);
      } catch (e) {
        if (!_isTransientKeeneticError(e)) rethrow;
        onProgress
            ?.call('Keenetic ещё обновляет каталог. Продолжаем ожидание...');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
      try {
        onProgress?.call('Проверяем доступность WireGuard...');
        await _runCliCommands(access, ['components install wireguard']);
        installQueued = true;
        break;
      } on KeeneticSetupException catch (e) {
        final message = e.message.toLowerCase();
        if (!message.contains('unavailable') && !message.contains('недоступ')) {
          rethrow;
        }
        lastUnavailable = e;
      }
    }
    if (!installQueued) {
      final detail = lastUnavailable?.message ?? '';
      throw KeeneticSetupException(
        'Каталог Keenetic не предоставил компонент WireGuard после ожидания. $detail',
      );
    }

    try {
      onProgress?.call(
          'Компонент загружен. Keenetic применяет изменения и перезагрузится...');
      await _runCliCommands(access, ['components commit']);
    } on KeeneticSetupException catch (e) {
      final nothingToCommit =
          e.message.toLowerCase().contains('component list');
      if (_isTransientKeeneticError(e)) {
        onProgress?.call(
            'Связь временно пропала — ожидаем Keenetic после перезагрузки...');
      } else if (nothingToCommit) {
        onProgress?.call(
            'Keenetic не требует изменения набора. Проверяем компонент...');
      } else {
        throw KeeneticSetupException(
          'Автоустановка WireGuard не выполнена: ${e.message}. Откройте веб-интерфейс Keenetic -> Системные настройки -> Изменить набор компонентов -> WireGuard VPN.',
        );
      }
    }

    const attempts = 36;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final elapsed = (attempt + 1) * 5;
      onProgress?.call(
        'Ожидаем Keenetic после применения компонентов. Проверка ${attempt + 1} из $attempts, прошло около $elapsed сек...',
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      try {
        final status = await checkWireGuardComponent(access);
        if (status.installed) {
          onProgress?.call('WireGuard установлен. Продолжаем настройку...');
          return const WireGuardComponentStatus(
            available: true,
            installed: true,
            canInstall: false,
            message: 'Компонент WireGuard установлен.',
          );
        }
      } catch (_) {
        // During component commit Keenetic can briefly restart management API.
      }
    }

    throw const KeeneticSetupException(
      'Keenetic не подтвердил установку WireGuard за 3 минуты. Проверьте доступ роутера к интернету и повторите установку.',
    );
  }

  Future<AwgConfigDetails> importAwgConfig(
      KeeneticAccess access, String configText) async {
    final details = parseAwgConfig(configText);
    await Future<void>.delayed(access.testMode
        ? const Duration(milliseconds: 600)
        : const Duration(milliseconds: 250));
    return details;
  }

  Future<void> createAwgConnection(
      KeeneticAccess access, String configText) async {
    if (access.testMode) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      return;
    }
    final config = _parseConfig(configText);
    final interfaces = await _getJson(
      access.router.ip,
      '/rci/show/interface',
      login: access.login,
      password: access.password,
    );
    if (interfaces is! Map<String, dynamic>) {
      throw const KeeneticSetupException(
          'Keenetic не вернул список интерфейсов.');
    }
    var selected = _findMatchingWireGuardInterface(interfaces, config);
    final createdByImport = selected == null;
    final selectedWasUp = selected != null &&
        interfaces[selected] is Map &&
        (interfaces[selected] as Map)['state'] == 'up';
    selected ??= await _importWireGuardConfig(access, configText, config);
    _selectedInterfaceByHost[access.router.ip] = selected;

    final competing = _findCompetingWireGuardInterfaces(interfaces, selected);
    final rollback = _KeeneticRollbackPlan(
      selectedInterface: selected,
      createdByImport: createdByImport,
      selectedWasUp: selectedWasUp,
      competingInterfaces: competing,
    );

    try {
      await _runCliCommands(access, [
        'interface $selected no ip global',
        'interface $selected ip mtu 1280',
      ]);
      await _retryKeenetic(() => _postRci(
            access.router.ip,
            '/rci/interface/$selected/up',
            login: access.login,
            password: access.password,
          ));
      await Future<void>.delayed(const Duration(seconds: 3));

      for (final name in competing) {
        await _retryKeenetic(() => _postRci(
              access.router.ip,
              '/rci/interface/$name/down',
              login: access.login,
              password: access.password,
            ));
      }
      if (competing.isNotEmpty) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }

      final status = await _waitForHandshake(access, selected);
      if (!status.handshakeOk) {
        throw KeeneticSetupException(status.message);
      }

      for (final name in competing) {
        await _deleteRci(
          access.router.ip,
          '/rci/interface/$name',
          login: access.login,
          password: access.password,
        ).catchError((_) {});
      }
      await _saveConfiguration(access, ignoreTransient: true);
    } catch (e) {
      await _rollbackSetup(access, rollback);
      final message = e is KeeneticSetupException ? e.message : e.toString();
      throw KeeneticSetupException(
          'Настройка не применена: $message. Старый маршрут восстановлен.');
    }
  }

  Future<TunnelStatus> startAndCheckTunnel(KeeneticAccess access) async {
    if (access.testMode) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return const TunnelStatus(
        active: true,
        handshakeOk: true,
        message: 'Handshake получен. Туннель активен.',
      );
    }
    final name = _selectedInterfaceByHost[access.router.ip];
    if (name == null) {
      throw const KeeneticSetupException(
          'Не выбран WireGuard-интерфейс для проверки.');
    }
    return _readTunnelStatus(access, name);
  }

  Future<TunnelStatus> attachAndCheckExistingTunnel(
      KeeneticAccess access) async {
    final interfaces = await _getJson(
      access.router.ip,
      '/rci/show/interface',
      login: access.login,
      password: access.password,
    );
    if (interfaces is! Map) {
      throw const KeeneticSetupException(
          'Keenetic не вернул список подключений.');
    }
    const router1Endpoints = {
      '213.176.93.13',
      '201.51.23.60',
      '92.51.46.27',
    };
    String? selected;
    for (final entry in interfaces.entries) {
      final name = entry.key.toString();
      if (!name.startsWith('Wireguard')) continue;
      final endpoint = _wireGuardEndpoint(interfaces, name);
      if (endpoint != null && router1Endpoints.contains(endpoint)) {
        selected = name;
        final value = entry.value;
        if (value is Map && value['state'] == 'up') break;
      }
    }
    if (selected == null) {
      throw const KeeneticSetupException(
          'Подключение Router1 на этом роутере не найдено.');
    }
    _selectedInterfaceByHost[access.router.ip] = selected;
    return _readTunnelStatus(access, selected);
  }

  Future<void> setSelectedTunnelEnabled(
      KeeneticAccess access, bool enabled) async {
    final name = _selectedInterfaceByHost[access.router.ip];
    if (name == null) {
      throw const KeeneticSetupException(
          'Сначала откройте Router1 в сети этого роутера и выполните проверку подключения.');
    }
    await _retryKeenetic(() => _postRci(
          access.router.ip,
          '/rci/interface/$name/${enabled ? 'up' : 'down'}',
          login: access.login,
          password: access.password,
        ));
    await _saveConfiguration(access, ignoreTransient: true);
  }

  Future<void> restartSelectedTunnel(KeeneticAccess access) async {
    await setSelectedTunnelEnabled(access, false);
    await Future<void>.delayed(const Duration(seconds: 2));
    await setSelectedTunnelEnabled(access, true);
  }

  Future<void> applyRoutingProfile(
    KeeneticAccess access,
    RouterRoutingProfile profile,
    Router1RouteProfile? routeProfile,
  ) async {
    if (profile == RouterRoutingProfile.fullTunnel) {
      await applyFullTunnelRouting(access, routeProfile: routeProfile);
    } else {
      await applySelectiveDnsRouting(access, routeProfile: routeProfile);
    }
  }

  Future<bool> verifyFullTunnelRouting(KeeneticAccess access) async {
    if (access.testMode) return true;
    final selected = _selectedInterfaceByHost[access.router.ip];
    if (selected == null) return false;
    final routes = await _getJson(
      access.router.ip,
      '/rci/show/ip/route',
      login: access.login,
      password: access.password,
    );
    final text = jsonEncode(routes);
    final firstHalf = text.contains('0.0.0.0') &&
        (text.contains('128.0.0.0') || text.contains('0.0.0.0/1'));
    final secondHalf = text.contains('128.0.0.0') &&
        (text.contains('128.0.0.0/1') || text.contains('128.0.0.0'));
    return firstHalf && secondHalf && text.contains(selected);
  }

  Future<void> clearRouter1Routing(
    KeeneticAccess access, {
    Router1RouteProfile? routeProfile,
  }) async {
    if (access.testMode) return;
    const mediaGroup = 'router1vpn0';
    const aiGroup = 'router1ai0';
    final profileIpv4Routes = <Router1Ipv4Route>[
      ...?routeProfile?.telegramIpv4Routes,
      ...?routeProfile?.mediaIpv4Routes,
      ...?routeProfile?.aiIpv4Routes,
    ];
    final profileIpv6Routes =
        routeProfile?.telegramIpv6Routes ?? const <String>[];
    final profileHosts = <String>[
      for (final values in routeProfile?.mediaResolvedHosts.values ??
          const Iterable<List<String>>.empty())
        ...values,
      for (final values in routeProfile?.aiResolvedHosts.values ??
          const Iterable<List<String>>.empty())
        ...values,
    ];
    await _runCliCommands(
      access,
      [
        'no dns-proxy route object-group $mediaGroup',
        'no dns-proxy route object-group $aiGroup',
        'no object-group fqdn $mediaGroup',
        'no object-group fqdn $aiGroup',
        for (final domain in _mediaDomains)
          'no object-group fqdn $mediaGroup include $domain',
        for (final domain in _mediaDomains)
          'no object-group fqdn $aiGroup include $domain',
        for (final domain in _aiDomains)
          'no object-group fqdn $mediaGroup include $domain',
        for (final domain in _aiDomains)
          'no object-group fqdn $aiGroup include $domain',
        for (final route in _telegramIpv4Routes)
          'no ip route ${route.network} ${route.mask}',
        for (final route in _googleIpv4Routes)
          'no ip route ${route.network} ${route.mask}',
        for (final route in _cloudflareIpv4Routes)
          'no ip route ${route.network} ${route.mask}',
        'no ip route 0.0.0.0 128.0.0.0',
        'no ip route 128.0.0.0 128.0.0.0',
        for (final route in profileIpv4Routes)
          'no ip route ${route.network} ${route.mask}',
        for (final route in _telegramIpv6Routes) 'no ipv6 route $route',
        'no ipv6 route ::/1',
        'no ipv6 route 8000::/1',
        for (final route in profileIpv6Routes) 'no ipv6 route $route',
        for (final host in profileHosts)
          if (InternetAddress.tryParse(host)?.type == InternetAddressType.IPv4)
            'no ip route $host 255.255.255.255'
          else if (InternetAddress.tryParse(host)?.type ==
              InternetAddressType.IPv6)
            'no ipv6 route $host/128',
      ],
      ignoreErrors: true,
    );
  }

  Future<void> applyFullTunnelRouting(
    KeeneticAccess access, {
    Router1RouteProfile? routeProfile,
  }) async {
    if (access.testMode) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return;
    }
    final selected = _selectedInterfaceByHost[access.router.ip];
    if (selected == null) {
      throw const KeeneticSetupException(
          'Не выбран WireGuard-интерфейс для full tunnel.');
    }
    await clearRouter1Routing(access, routeProfile: routeProfile);
    await _runCliCommands(
      access,
      [
        'interface $selected ip global',
        'interface $selected ipv6 global',
        'interface $selected ip mtu 1280',
        'no ip route 0.0.0.0 0.0.0.0 $selected',
        'ip route 0.0.0.0 128.0.0.0 $selected auto',
        'ip route 128.0.0.0 128.0.0.0 $selected auto',
        'ipv6 route ::/1 $selected auto',
        'ipv6 route 8000::/1 $selected auto',
      ],
      ignoreErrors: true,
    );
    await _runCliCommands(access, ['system configuration save'],
        ignoreErrors: true);
  }

  Future<void> applySelectiveDnsRouting(
    KeeneticAccess access, {
    Router1RouteProfile? routeProfile,
  }) async {
    if (access.testMode) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return;
    }
    final selected = _selectedInterfaceByHost[access.router.ip];
    if (selected == null) {
      throw const KeeneticSetupException(
          'Не выбран WireGuard-интерфейс для маршрутизации.');
    }

    final interfaces = await _getJson(
      access.router.ip,
      '/rci/show/interface',
      login: access.login,
      password: access.password,
    );
    final interfaceMap =
        interfaces is Map<String, dynamic> ? interfaces['interface'] : null;
    final frInterface = _findHealthyWireGuardByEndpoint(
      interfaceMap,
      const {'213.176.93.13'},
    );
    final nl2Interface = _findHealthyWireGuardByEndpoint(
      interfaceMap,
      const {'201.51.23.60'},
    );
    final selectedEndpoint = _wireGuardEndpoint(interfaceMap, selected);
    final selectedIsFr = selectedEndpoint == '213.176.93.13';
    final selectedIsNl2 = selectedEndpoint == '201.51.23.60';

    final mediaInterface =
        selectedIsFr && nl2Interface != null ? nl2Interface : selected;
    final aiInterface =
        selectedIsNl2 && frInterface != null ? frInterface : selected;

    const mediaGroup = 'router1vpn0';
    const aiGroup = 'router1ai0';
    final mediaDomains = routeProfile?.mediaDomains.isNotEmpty == true
        ? routeProfile!.mediaDomains
        : _mediaDomains;
    final aiDomains = routeProfile?.aiDomains.isNotEmpty == true
        ? routeProfile!.aiDomains
        : _aiDomains;
    final allManagedDomains = [...mediaDomains, ...aiDomains];
    await clearRouter1Routing(access, routeProfile: routeProfile);
    await _runCliCommands(
        access,
        [
          'interface $selected no ip global',
          'interface $selected no ipv6 global',
          'interface $selected ip mtu 1280',
          'no ip route 0.0.0.0 0.0.0.0 $selected',
          'no ipv6 route ::/0 $selected',
          if (frInterface != null) 'interface $frInterface no ip global',
          if (frInterface != null) 'interface $frInterface no ipv6 global',
          if (nl2Interface != null) 'interface $nl2Interface no ip global',
          if (nl2Interface != null) 'interface $nl2Interface no ipv6 global',
        ],
        ignoreErrors: true);
    await _runCliCommands(
      access,
      [
        'object-group fqdn $mediaGroup',
        'object-group fqdn $aiGroup',
        for (final domain in allManagedDomains)
          'object-group fqdn ${aiDomains.contains(domain) ? aiGroup : mediaGroup} include $domain',
        'dns-proxy route object-group $mediaGroup $mediaInterface auto',
        'dns-proxy route object-group $aiGroup $aiInterface auto',
      ],
      ignoreErrors: false,
    );
    await _runCliCommands(
        access,
        [
          for (final route in _telegramIpv4Routes)
            'ip route ${route.network} ${route.mask} $mediaInterface auto',
          for (final route in _googleIpv4Routes)
            'ip route ${route.network} ${route.mask} $mediaInterface auto',
          for (final route in _cloudflareIpv4Routes)
            'ip route ${route.network} ${route.mask} $aiInterface auto',
          for (final route
              in routeProfile?.telegramIpv4Routes ?? const <Router1Ipv4Route>[])
            'ip route ${route.network} ${route.mask} $mediaInterface auto',
          for (final route
              in routeProfile?.mediaIpv4Routes ?? const <Router1Ipv4Route>[])
            'ip route ${route.network} ${route.mask} $mediaInterface auto',
          for (final route
              in routeProfile?.aiIpv4Routes ?? const <Router1Ipv4Route>[])
            'ip route ${route.network} ${route.mask} $aiInterface auto',
          for (final route in _telegramIpv6Routes)
            'ipv6 route $route $mediaInterface auto',
          for (final route
              in routeProfile?.telegramIpv6Routes ?? const <String>[])
            'ipv6 route $route $mediaInterface auto',
        ],
        ignoreErrors: true);
    final resolvedRoutes = await _buildResolvedHostRoutes(
      mediaDomains: routeProfile?.mediaProbeDomains.isNotEmpty == true
          ? routeProfile!.mediaProbeDomains
          : _mediaResolveDomains,
      mediaInterface: mediaInterface,
      aiDomains: routeProfile?.aiProbeDomains.isNotEmpty == true
          ? routeProfile!.aiProbeDomains
          : _aiResolveDomains,
      aiInterface: aiInterface,
      mediaResolvedHosts: routeProfile?.mediaResolvedHosts ?? const {},
      aiResolvedHosts: routeProfile?.aiResolvedHosts ?? const {},
    );
    if (resolvedRoutes.isNotEmpty) {
      await _runCliCommands(access, resolvedRoutes, ignoreErrors: true);
    }
    await _runCliCommands(access, ['system configuration save'],
        ignoreErrors: true);
  }

  Future<Map<String, Object?>> collectDiagnostics(
    KeeneticAccess access, {
    required RouterRoutingProfile routingProfile,
    Router1RouteProfile? routeProfile,
    String appVersion = '',
    String stage = 'unknown',
    String? error,
  }) async {
    final selected = _selectedInterfaceByHost[access.router.ip];
    final result = <String, Object?>{
      'stage': stage,
      'error': error,
      'app': {
        'version': appVersion,
      },
      'router': {
        'host': access.router.ip,
        'model': access.router.model,
        'hostname': access.router.hostname,
        'firmware': access.router.firmware,
      },
      'routing_profile': routingProfile.name,
      'selected_interface': selected,
      'server_profile': routeProfile == null
          ? null
          : {
              'profile_id': routeProfile.profileId,
              'version': routeProfile.version,
              'media_domains': routeProfile.mediaDomains.length,
              'ai_domains': routeProfile.aiDomains.length,
              'media_resolved_hosts': routeProfile.mediaResolvedHosts.values
                  .fold<int>(0, (sum, item) => sum + item.length),
              'ai_resolved_hosts': routeProfile.aiResolvedHosts.values
                  .fold<int>(0, (sum, item) => sum + item.length),
              'media_ipv4_routes': routeProfile.mediaIpv4Routes.length,
              'ai_ipv4_routes': routeProfile.aiIpv4Routes.length,
              'telegram_ipv4_routes': routeProfile.telegramIpv4Routes.length,
              'telegram_ipv6_routes': routeProfile.telegramIpv6Routes.length,
            },
      'checks': <String, Object?>{},
    };

    if (access.testMode) return result;

    final checks = result['checks'] as Map<String, Object?>;
    for (final entry in const <String, String>{
      'version': '/rci/show/version',
      'interfaces': '/rci/show/interface',
      'selected_interface': '',
      'ip_route': '/rci/show/ip/route',
      'ipv6_route': '/rci/show/ipv6/route',
      'dns_proxy': '/rci/show/dns-proxy',
      'object_group': '/rci/show/object-group',
    }.entries) {
      final path = entry.key == 'selected_interface' && selected != null
          ? '/rci/show/interface/$selected'
          : entry.value;
      if (path.isEmpty) continue;
      checks[entry.key] = await _diagnosticGet(access, path);
    }
    return _redactDiagnostics(result) as Map<String, Object?>;
  }

  Future<Object?> _diagnosticGet(KeeneticAccess access, String path) async {
    try {
      final value = await _retryKeenetic(() => _get(
            access.router.ip,
            path,
            login: access.login,
            password: access.password,
          ));
      Object? body;
      try {
        body = jsonDecode(value.body);
      } catch (_) {
        body = value.body.length > 4000
            ? '${value.body.substring(0, 4000)}...'
            : value.body;
      }
      return {
        'ok': value.statusCode >= 200 && value.statusCode < 300,
        'status': value.statusCode,
        'body': body,
      };
    } catch (e) {
      return {
        'ok': false,
        'error': e.toString(),
      };
    }
  }

  Object? _redactDiagnostics(Object? value) {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final normalized = key.toLowerCase();
        if (normalized.contains('password') ||
            normalized.contains('private') ||
            normalized.contains('preshared') ||
            normalized == 'key' ||
            normalized.endsWith('-key')) {
          result[key] = '<redacted>';
        } else {
          result[key] = _redactDiagnostics(entry.value);
        }
      }
      return result;
    }
    if (value is List) {
      return value.map(_redactDiagnostics).toList(growable: false);
    }
    if (value is String && value.length > 8000) {
      return '${value.substring(0, 8000)}...';
    }
    return value;
  }

  Future<List<String>> _buildResolvedHostRoutes({
    required List<String> mediaDomains,
    required String mediaInterface,
    required List<String> aiDomains,
    required String aiInterface,
    required Map<String, List<String>> mediaResolvedHosts,
    required Map<String, List<String>> aiResolvedHosts,
  }) async {
    final commands = <String>[];
    final seen = <String>{};

    void addAddress(String value, String interface) {
      final address = value.trim();
      if (address.isEmpty) return;
      final type = InternetAddress.tryParse(address)?.type;
      if (type == InternetAddressType.IPv4) {
        final key = '4:$address:$interface';
        if (seen.add(key)) {
          commands.add('ip route $address 255.255.255.255 $interface auto');
        }
      } else if (type == InternetAddressType.IPv6) {
        final key = '6:$address:$interface';
        if (seen.add(key)) {
          commands.add('ipv6 route $address/128 $interface auto');
        }
      }
    }

    void addResolvedMap(Map<String, List<String>> hosts, String interface) {
      for (final values in hosts.values) {
        for (final address in values) {
          if (commands.length >= 170) return;
          addAddress(address, interface);
        }
      }
    }

    addResolvedMap(mediaResolvedHosts, mediaInterface);
    addResolvedMap(aiResolvedHosts, aiInterface);

    Future<void> addDomain(
        String domain, String interface, int maxPerDomain) async {
      List<InternetAddress> addresses;
      try {
        addresses = await InternetAddress.lookup(domain)
            .timeout(const Duration(seconds: 2), onTimeout: () => const []);
      } catch (_) {
        return;
      }
      var added = 0;
      for (final address in addresses) {
        if (added >= maxPerDomain) break;
        if (address.type == InternetAddressType.IPv4) {
          final before = commands.length;
          addAddress(address.address, interface);
          if (commands.length > before) added++;
        } else if (address.type == InternetAddressType.IPv6) {
          final before = commands.length;
          addAddress(address.address, interface);
          if (commands.length > before) added++;
        }
      }
    }

    for (final domain in mediaDomains) {
      if (commands.length >= 90) break;
      await addDomain(domain, mediaInterface, 4);
    }
    for (final domain in aiDomains) {
      if (commands.length >= 170) break;
      await addDomain(domain, aiInterface, 4);
    }
    return commands.take(170).toList(growable: false);
  }

  static const _mediaDomains = [
    'youtube.com',
    'youtu.be',
    'www.youtube.com',
    'm.youtube.com',
    'googlevideo.com',
    'ggpht.com',
    'ytimg.com',
    'yt3.ggpht.com',
    'youtubei.googleapis.com',
    'youtube.googleapis.com',
    'youtube-nocookie.com',
    'telegram.org',
    'api.telegram.org',
    'core.telegram.org',
    'desktop.telegram.org',
    'web.telegram.org',
    'venus.web.telegram.org',
    'pluto.web.telegram.org',
    'flora.web.telegram.org',
    'k.web.telegram.org',
    'z.web.telegram.org',
    'updates.tdesktop.com',
    'telegramusercontent.com',
    't.me',
    'telegram.me',
    'telegram.dog',
    'tdesktop.com',
    'tdesktop.org',
    'telegram-cdn.org',
    'cdn1.telegram-cdn.org',
    'cdn2.telegram-cdn.org',
    'cdn3.telegram-cdn.org',
    'cdn4.telegram-cdn.org',
    'cdn5.telegram-cdn.org',
    'cdn-telegram.org',
    'cdn1.cdn-telegram.org',
    'cdn2.cdn-telegram.org',
    'cdn3.cdn-telegram.org',
    'cdn4.cdn-telegram.org',
    'cdn5.cdn-telegram.org',
    'telegra.ph',
    'telesco.pe',
    'instagram.com',
    'www.instagram.com',
    'cdninstagram.com',
    'scontent.cdninstagram.com',
    'fbcdn.net',
    'facebook.com',
    'facebook.net',
    'messenger.com',
    'whatsapp.com',
    'whatsapp.net',
    'wa.me',
    'web.whatsapp.com',
  ];
  static const _aiDomains = [
    'chatgpt.com',
    'chat.com',
    'chat.openai.com',
    'ios.chat.openai.com',
    'ab.chatgpt.com',
    'cdn.chatgpt.com',
    'openai.com',
    'auth.openai.com',
    'auth0.openai.com',
    'api.openai.com',
    'cdn.openai.com',
    'oaistatic.com',
    'cdn.oaistatic.com',
    'persistent.oaistatic.com',
    'oaiusercontent.com',
    'files.oaiusercontent.com',
    'challenges.cloudflare.com',
    'arkoselabs.com',
    'client-api.arkoselabs.com',
    'funcaptcha.com',
    'hcaptcha.com',
    'newassets.hcaptcha.com',
    'statsigapi.net',
    'events.statsigapi.net',
    'featuregates.org',
    'browser-intake-datadoghq.com',
    'intercom.io',
    'intercomcdn.com',
    'sentry.io',
    'openaiapi-site.azureedge.net',
    'claude.ai',
    'api.claude.ai',
    'claudeusercontent.com',
    'anthropic.com',
    'console.anthropic.com',
    'api.anthropic.com',
    'statsig.anthropic.com',
    'perplexity.ai',
    'gemini.google.com',
    'generativelanguage.googleapis.com',
    'ai.google.dev',
    'bard.google.com',
    'copilot.microsoft.com',
    'bing.com',
    'edgeservices.bing.com',
    'sydney.bing.com',
  ];

  AwgConfigDetails parseAwgConfig(String value) {
    final config = _parseConfig(value);
    return config.details;
  }

  bool _hasWireGuardComponent(String components) {
    final normalized = components
        .split(RegExp(r'[\s,;]+'))
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalized.contains('wireguard') ||
        normalized.contains('awg') ||
        normalized.contains('amneziawg')) {
      return true;
    }
    // Некоторые прошивки Keenetic отдают components в другом формате
    // (JSON-массив, другие разделители, кавычки/скобки вокруг имён) —
    // строгое разбиение на токены выше может не сматчить. Подстраховка:
    // ищем подстроку прямо в исходной (уже lowercase) строке.
    final raw = components.toLowerCase();
    return raw.contains('wireguard') ||
        raw.contains('amneziawg') ||
        raw.contains('awg');
  }

  bool _hasWireGuardInterface(Object? interfaces) {
    if (interfaces is! Map) return false;
    return interfaces.keys
        .map((key) => key.toString().toLowerCase())
        .any((key) => key.startsWith('wireguard'));
  }

  Set<String> _findCompetingWireGuardInterfaces(
    Map<String, dynamic> interfaces,
    String selected,
  ) {
    const router1Endpoints = {
      '213.176.93.13',
      '201.51.23.60',
      '92.51.46.27',
    };
    final result = <String>{};
    for (final entry in interfaces.entries) {
      final name = entry.key;
      if (name == selected || !name.startsWith('Wireguard')) continue;
      final endpoint = _wireGuardEndpoint(interfaces, name);
      if (endpoint != null && router1Endpoints.contains(endpoint)) {
        result.add(name);
      }
    }
    return result;
  }

  String? _findHealthyWireGuardByEndpoint(
    Object? interfaces,
    Set<String> endpoints,
  ) {
    if (interfaces is! Map) return null;
    for (final entry in interfaces.entries) {
      final name = entry.key.toString();
      final value = entry.value;
      if (!name.startsWith('Wireguard') || value is! Map) continue;
      if (value['connected'] != 'yes' || value['state'] != 'up') continue;
      final endpoint = _wireGuardEndpoint(interfaces, name);
      if (endpoint != null && endpoints.contains(endpoint)) return name;
    }
    return null;
  }

  String? _wireGuardEndpoint(Object? interfaces, String name) {
    if (interfaces is! Map) return null;
    final value = interfaces[name];
    if (value is! Map) return null;
    final topLevel = value['remote-endpoint-address']?.toString().trim();
    if (topLevel != null && topLevel.isNotEmpty) return topLevel;
    final wireguard = value['wireguard'];
    final peers = wireguard is Map ? wireguard['peer'] : null;
    if (peers is List && peers.isNotEmpty && peers.first is Map) {
      final peer = peers.first as Map;
      final nested = peer['remote-endpoint-address']?.toString().trim();
      if (nested != null && nested.isNotEmpty) return nested;
    }
    return null;
  }

  KeeneticRouter _routerFromVersion(
      KeeneticRouter base, Map<String, dynamic> version) {
    final device = version['device']?.toString().trim() ?? '';
    final model = version['model']?.toString().trim() ?? '';
    final description = version['description']?.toString().trim() ?? '';
    final displayModel = device.isNotEmpty
        ? 'Keenetic $device'
        : model.isNotEmpty
            ? 'Keenetic $model'
            : description.isNotEmpty
                ? description
                : base.model;
    final firmware = version['release']?.toString().trim().isNotEmpty == true
        ? version['release']?.toString().trim()
        : version['title']?.toString().trim();
    return KeeneticRouter(
      model: displayModel,
      ip: base.ip,
      firmware: firmware,
      hostname: version['hostname']?.toString(),
      wifiName: base.wifiName,
      compatible: true,
      apiAvailable: true,
      apiAuthenticated: true,
      webPanelDetected: true,
      connectionType: base.connectionType,
      source: base.source,
    );
  }

  _ParsedAwgConfig _parseConfig(String value) {
    final sections = <String, Map<String, String>>{};
    var section = '';
    for (final rawLine in const LineSplitter().convert(value)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).toLowerCase();
        sections.putIfAbsent(section, () => <String, String>{});
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0 || section.isEmpty) continue;
      final key = line.substring(0, separator).trim().toLowerCase();
      final val = line.substring(separator + 1).trim();
      sections.putIfAbsent(section, () => <String, String>{})[key] = val;
    }

    final iface = sections['interface'];
    final peer = sections['peer'];
    if (iface == null ||
        peer == null ||
        (iface['privatekey'] ?? '').isEmpty ||
        (peer['publickey'] ?? '').isEmpty ||
        (peer['endpoint'] ?? '').isEmpty) {
      throw const KeeneticSetupException(
          'Файл не похож на полный AmneziaWG/WireGuard конфиг.');
    }

    final warnings = <String>[];
    final address = iface['address'] ?? '';
    final dns = iface['dns'] ?? '';
    final allowedIps = peer['allowedips'] ?? '';
    final keepalive = peer['persistentkeepalive'] ?? '';
    final hasAwg = ['jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4']
        .any((key) => iface.containsKey(key));

    if (address.isEmpty) warnings.add('В конфиге нет Address.');
    if (dns.isEmpty) warnings.add('В конфиге нет DNS.');
    if (allowedIps.isEmpty) warnings.add('В конфиге нет AllowedIPs.');
    if (allowedIps.contains('::/0') && !address.contains(':')) {
      warnings.add('Маршрут IPv6 включен, но IPv6-адрес интерфейса не указан.');
    }
    if (keepalive.isEmpty) {
      warnings
          .add('PersistentKeepalive пустой; на мобильных сетях лучше 25-30.');
    }

    final details = AwgConfigDetails(
      interfaceAddress: address,
      dns: dns,
      endpoint: peer['endpoint'] ?? '',
      allowedIps: allowedIps,
      persistentKeepalive: keepalive,
      hasAwgObfuscation: hasAwg,
      warnings: warnings,
    );
    return _ParsedAwgConfig(
      details: details,
      privateKey: iface['privatekey'] ?? '',
      peerPublicKey: peer['publickey'] ?? '',
      presharedKey: peer['presharedkey'] ?? '',
    );
  }

  String buildKeeneticManualScript(String configText) {
    final details = parseAwgConfig(configText);
    final lines = <String>[
      '# Router1 Keenetic manual fallback',
      '# Импортируйте AWG/WireGuard конфиг через веб-интерфейс Keenetic.',
      '# Затем проверьте параметры подключения:',
      'Endpoint: ${details.endpoint}',
      'Address: ${details.interfaceAddress}',
      'DNS: ${details.dns.isEmpty ? 'не указан' : details.dns}',
      'AllowedIPs: ${details.allowedIps}',
      'PersistentKeepalive: ${details.persistentKeepalive.isEmpty ? 'не указан' : details.persistentKeepalive}',
      'Use for accessing the Internet: ${details.fullTunnel ? 'enable' : 'check manually'}',
      if (details.routesIpv6 && !details.hasIpv6Address)
        'Warning: добавьте IPv6 Address или уберите ::/0.',
      'system configuration save',
    ];
    return lines.join('\n');
  }

  Future<_KeeneticHttpResponse> _get(
    String host,
    String path, {
    required String login,
    required String password,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.badCertificateCallback = (_, __, ___) => true;
    try {
      final base = _baseUri(host);
      final authHeaderCandidates = await _buildAuthHeaderCandidates(
        client,
        base,
        login: login,
        password: password,
      );

      _KeeneticHttpResponse? lastAuthFailure;
      for (final authHeaders in authHeaderCandidates) {
        final request = await client
            .getUrl(base.replace(path: path, query: ''))
            .timeout(timeout);
        request.followRedirects = false;
        for (final entry in authHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'Router1');
        final response = await request.close().timeout(timeout);
        final responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(timeout, onTimeout: () => '');
        final result = _KeeneticHttpResponse(response.statusCode, responseBody);
        if (response.statusCode != 401 && response.statusCode != 403) {
          return result;
        }
        lastAuthFailure = result;
      }
      return lastAuthFailure ?? const _KeeneticHttpResponse(401, '');
    } on TimeoutException {
      throw const KeeneticSetupException(
          'Роутер не ответил за 15 секунд. Проверьте KeenDNS или локальный адрес.');
    } on SocketException {
      throw const KeeneticSetupException(
          'Адрес роутера недоступен: DNS или соединение не установлены.');
    } finally {
      client.close(force: true);
    }
  }

  Future<dynamic> _getJson(
    String host,
    String path, {
    required String login,
    required String password,
  }) async {
    final response = await _retryKeenetic(
        () => _get(host, path, login: login, password: password));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KeeneticSetupException(
          'Keenetic ответил HTTP ${response.statusCode} на $path.');
    }
    return jsonDecode(response.body);
  }

  Future<String> _postRci(
    String host,
    String path, {
    required String login,
    required String password,
    Object? body,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.badCertificateCallback = (_, __, ___) => true;
    try {
      final base = _baseUri(host);
      final authHeaderCandidates = await _buildAuthHeaderCandidates(
        client,
        base,
        login: login,
        password: password,
      );

      _KeeneticHttpResponse? lastAuthFailure;
      for (final authHeaders in authHeaderCandidates) {
        final request = await client
            .postUrl(base.replace(path: path, query: ''))
            .timeout(timeout);
        request.followRedirects = false;
        for (final entry in authHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'Router1');
        request.write(jsonEncode(body ?? const <String, Object?>{}));
        final response = await request.close().timeout(timeout);
        final responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(timeout, onTimeout: () => '');
        final result = _KeeneticHttpResponse(response.statusCode, responseBody);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return responseBody;
        }
        if (response.statusCode != 401 && response.statusCode != 403) {
          throw KeeneticSetupException(
              'Keenetic ответил HTTP ${response.statusCode} на $path.');
        }
        lastAuthFailure = result;
      }
      throw KeeneticSetupException(
          'Keenetic не авторизовал команду $path: HTTP ${lastAuthFailure?.statusCode ?? 401}.');
    } on TimeoutException {
      throw const KeeneticSetupException(
          'Роутер не ответил за 15 секунд. Проверьте KeenDNS или локальный адрес.');
    } on SocketException {
      throw const KeeneticSetupException(
          'Адрес роутера недоступен: DNS или соединение не установлены.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _runCliCommands(
    KeeneticAccess access,
    List<String> commands, {
    bool ignoreErrors = false,
  }) async {
    if (commands.isEmpty) return;
    final response = await _retryKeenetic(() => _postRci(
          access.router.ip,
          '/rci/',
          login: access.login,
          password: access.password,
          body: [
            for (final command in commands) {'parse': command},
          ],
        ));
    if (ignoreErrors || response.trim().isEmpty) return;
    final data = jsonDecode(response);
    if (data is! List) return;
    for (final item in data) {
      final parse = item is Map ? item['parse'] : null;
      final statuses = parse is Map ? parse['status'] : null;
      if (statuses is! List) continue;
      for (final status in statuses) {
        if (status is Map && status['status'] == 'error') {
          final message = status['message']?.toString() ??
              status['ident']?.toString() ??
              'команда Keenetic не выполнена';
          throw KeeneticSetupException(message);
        }
      }
    }
  }

  Future<String> _importWireGuardConfig(
    KeeneticAccess access,
    String configText,
    _ParsedAwgConfig config,
  ) async {
    final payload = {
      'import': base64Encode(utf8.encode(configText)),
      'name': '',
      'filename':
          'router1_${_firstIpv4(config.details.interfaceAddress) ?? 'vpn'}.conf',
    };
    final client = HttpClient()..connectionTimeout = timeout;
    client.badCertificateCallback = (_, __, ___) => true;
    try {
      final base = _baseUri(access.router.ip);
      final authHeaderCandidates = await _buildAuthHeaderCandidates(
        client,
        base,
        login: access.login,
        password: access.password,
      );
      for (final authHeaders in authHeaderCandidates) {
        final request = await client
            .postUrl(base.replace(path: '/rci/interface/wireguard/import'))
            .timeout(timeout);
        request.followRedirects = false;
        for (final entry in authHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'Router1');
        request.write(jsonEncode(payload));
        final response = await request.close().timeout(timeout);
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(timeout, onTimeout: () => '');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          final created = data['created']?.toString() ?? '';
          if (created.isNotEmpty) return created;
          final intersects = data['intersects']?.toString() ?? '';
          if (intersects.isNotEmpty) {
            throw KeeneticSetupException(
                'Keenetic сообщает, что конфиг пересекается с интерфейсами: $intersects.');
          }
          throw const KeeneticSetupException(
              'Keenetic импортировал конфиг, но не вернул имя интерфейса.');
        }
      }
      throw const KeeneticSetupException(
          'Keenetic не авторизовал импорт WireGuard-конфига.');
    } on TimeoutException {
      throw const KeeneticSetupException(
          'Роутер не ответил за 15 секунд при импорте WireGuard.');
    } on SocketException {
      throw const KeeneticSetupException(
          'Адрес роутера недоступен при импорте WireGuard.');
    } finally {
      client.close(force: true);
    }
  }

  Future<TunnelStatus> _waitForHandshake(
    KeeneticAccess access,
    String name,
  ) async {
    TunnelStatus status = const TunnelStatus(
      active: false,
      handshakeOk: false,
      message: 'Handshake пока не получен.',
    );
    for (var attempt = 0; attempt < 6; attempt++) {
      status = await _readTunnelStatus(access, name);
      if (status.handshakeOk) return status;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return status;
  }

  Future<TunnelStatus> _readTunnelStatus(
    KeeneticAccess access,
    String name,
  ) async {
    final value = await _getJson(
      access.router.ip,
      '/rci/show/interface/$name',
      login: access.login,
      password: access.password,
    );
    if (value is! Map<String, dynamic>) {
      throw const KeeneticSetupException('Keenetic не вернул статус туннеля.');
    }
    final wireguard = value['wireguard'];
    final peers = wireguard is Map ? wireguard['peer'] : null;
    final peer = peers is List && peers.isNotEmpty && peers.first is Map
        ? peers.first as Map
        : const {};
    final active = value['state'] == 'up' &&
        value['connected'] == 'yes' &&
        wireguard is Map &&
        wireguard['status'] == 'up';
    final online = peer['online'] == true;
    final handshakeRaw = peer['last-handshake'];
    final handshake = handshakeRaw is num ? handshakeRaw.toInt() : null;
    final handshakeOk = active &&
        online &&
        handshake != null &&
        handshake >= 0 &&
        handshake < 1800;
    return TunnelStatus(
      active: active,
      handshakeOk: handshakeOk,
      message: handshakeOk
          ? 'Handshake получен через $name ${handshake}s назад.'
          : 'Туннель $name поднят, но свежий handshake пока не подтверждён.',
    );
  }

  Future<void> _rollbackSetup(
    KeeneticAccess access,
    _KeeneticRollbackPlan plan,
  ) async {
    for (final name in plan.competingInterfaces) {
      await _retryKeenetic(() => _postRci(
            access.router.ip,
            '/rci/interface/$name/up',
            login: access.login,
            password: access.password,
          ));
    }
    if (plan.createdByImport) {
      await _deleteRci(
        access.router.ip,
        '/rci/interface/${plan.selectedInterface}',
        login: access.login,
        password: access.password,
      );
    } else if (!plan.selectedWasUp) {
      await _retryKeenetic(() => _postRci(
            access.router.ip,
            '/rci/interface/${plan.selectedInterface}/down',
            login: access.login,
            password: access.password,
          ));
    }
    await _saveConfiguration(access, ignoreTransient: true);
  }

  Future<void> _saveConfiguration(
    KeeneticAccess access, {
    bool ignoreTransient = false,
  }) async {
    try {
      await _retryKeenetic(() => _postRci(
            access.router.ip,
            '/rci/system/configuration/save',
            login: access.login,
            password: access.password,
          ));
    } catch (e) {
      if (ignoreTransient && _isTransientKeeneticError(e)) return;
      rethrow;
    }
  }

  Future<T> _retryKeenetic<T>(Future<T> Function() operation) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await operation();
      } catch (e) {
        lastError = e;
        if (!_isTransientKeeneticError(e) || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 350 + attempt * 650));
      }
    }
    throw lastError ?? const KeeneticSetupException('Keenetic API недоступен.');
  }

  bool _isTransientKeeneticError(Object error) {
    if (error is TimeoutException || error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is KeeneticSetupException) {
      final message = error.message.toLowerCase();
      return message.contains('не ответил') ||
          message.contains('недоступен') ||
          message.contains('connection closed') ||
          message.contains('connection reset') ||
          message.contains('broken pipe');
    }
    return false;
  }

  Future<void> _deleteRci(
    String host,
    String path, {
    required String login,
    required String password,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.badCertificateCallback = (_, __, ___) => true;
    try {
      final base = _baseUri(host);
      final authHeaderCandidates = await _buildAuthHeaderCandidates(
        client,
        base,
        login: login,
        password: password,
      );
      for (final authHeaders in authHeaderCandidates) {
        final request = await client
            .deleteUrl(base.replace(path: path, query: ''))
            .timeout(timeout);
        request.followRedirects = false;
        for (final entry in authHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'Router1');
        final response = await request.close().timeout(timeout);
        await response.drain<void>().timeout(timeout, onTimeout: () {});
        if (response.statusCode >= 200 && response.statusCode < 300) return;
      }
      throw KeeneticSetupException('Keenetic не выполнил DELETE $path.');
    } finally {
      client.close(force: true);
    }
  }

  String? _findMatchingWireGuardInterface(
    Map<String, dynamic> interfaces,
    _ParsedAwgConfig config,
  ) {
    final configAddress = _firstIpv4(config.details.interfaceAddress);
    for (final entry in interfaces.entries) {
      if (!entry.key.startsWith('Wireguard') || entry.value is! Map) continue;
      final data = entry.value as Map;
      final addressMatches =
          configAddress != null && data['address'] == configAddress;
      if (addressMatches) return entry.key;
    }
    return null;
  }

  String? _firstIpv4(String value) {
    for (final item in value.split(',')) {
      final raw = item.trim().split('/').first;
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(raw)) {
        return raw;
      }
    }
    return null;
  }

  Uri _baseUri(String host) {
    final raw = host.trim().replaceFirst(RegExp(r'/$'), '');
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Uri.parse(raw);
    }
    final scheme = raw.contains('keenetic.pro') ? 'https' : 'http';
    return Uri.parse('$scheme://$raw');
  }

  Future<List<Map<String, String>>> _buildAuthHeaderCandidates(
    HttpClient client,
    Uri base, {
    required String login,
    required String password,
  }) async {
    final request = await client
        .getUrl(base.replace(path: '/auth', query: ''))
        .timeout(timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Router1');
    final response = await request.close().timeout(timeout);
    final headers = _headers(response);
    final cookie = _sessionCookie(response);
    await response.drain<void>().timeout(timeout, onTimeout: () {});

    final challenge = headers['x-ndm-challenge'];
    final realm = headers['x-ndm-realm'];
    final candidates = <Map<String, String>>[];
    if (challenge != null && realm != null) {
      final innerHash = _md5Hex('$login:$realm:$password');
      final responseHash = _sha256Hex('$challenge$innerHash');
      final authRequest = await client
          .postUrl(base.replace(path: '/auth', query: ''))
          .timeout(timeout);
      authRequest.followRedirects = false;
      authRequest.headers.set(HttpHeaders.acceptHeader, 'application/json');
      authRequest.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json');
      authRequest.headers.set(HttpHeaders.userAgentHeader, 'Router1');
      if (cookie != null) {
        authRequest.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      authRequest.write(jsonEncode({
        'login': login,
        'password': responseHash,
      }));
      final authResponse = await authRequest.close().timeout(timeout);
      final authCookie = _sessionCookie(authResponse) ?? cookie;
      await authResponse.drain<void>().timeout(timeout, onTimeout: () {});
      if (authResponse.statusCode >= 200 && authResponse.statusCode < 300) {
        candidates.add({
          if (authCookie != null) HttpHeaders.cookieHeader: authCookie,
        });
      }
    }

    candidates.add({
      HttpHeaders.authorizationHeader:
          'Basic ${base64Encode(utf8.encode('$login:$password'))}',
      if (cookie != null) HttpHeaders.cookieHeader: cookie,
    });
    return candidates;
  }

  Map<String, String> _headers(HttpClientResponse response) {
    final result = <String, String>{};
    response.headers.forEach((name, values) {
      result[name.toLowerCase()] = values.join(' ');
    });
    return result;
  }

  String _sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String _md5Hex(String value) {
    return md5.convert(utf8.encode(value)).toString();
  }

  String? _sessionCookie(HttpClientResponse response) {
    final values = response.headers[HttpHeaders.setCookieHeader];
    if (values == null || values.isEmpty) return null;
    final cookie = values.first.split(';').first.trim();
    return cookie.isEmpty ? null : cookie;
  }
}

class _KeeneticHttpResponse {
  const _KeeneticHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _ParsedAwgConfig {
  const _ParsedAwgConfig({
    required this.details,
    required this.privateKey,
    required this.peerPublicKey,
    required this.presharedKey,
  });

  final AwgConfigDetails details;
  final String privateKey;
  final String peerPublicKey;
  final String presharedKey;

  bool get fullTunnel => details.fullTunnel;

  String? get endpointHost {
    final endpoint = details.endpoint.trim();
    if (endpoint.isEmpty) return null;
    final bracketMatch = RegExp(r'^\[([^\]]+)\]:(\d+)$').firstMatch(endpoint);
    if (bracketMatch != null) return bracketMatch.group(1);
    final index = endpoint.lastIndexOf(':');
    if (index <= 0) return endpoint;
    return endpoint.substring(0, index);
  }

  String? get endpointPort {
    final endpoint = details.endpoint.trim();
    final bracketMatch = RegExp(r'^\[[^\]]+\]:(\d+)$').firstMatch(endpoint);
    if (bracketMatch != null) return bracketMatch.group(1);
    final index = endpoint.lastIndexOf(':');
    if (index <= 0 || index == endpoint.length - 1) return null;
    return endpoint.substring(index + 1);
  }
}

class _KeeneticRollbackPlan {
  const _KeeneticRollbackPlan({
    required this.selectedInterface,
    required this.createdByImport,
    required this.selectedWasUp,
    required this.competingInterfaces,
  });

  final String selectedInterface;
  final bool createdByImport;
  final bool selectedWasUp;
  final Set<String> competingInterfaces;
}

class KeeneticSetupException implements Exception {
  const KeeneticSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}
