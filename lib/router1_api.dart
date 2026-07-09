import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum RouterMode {
  normal('normal', 'Обычный'),
  game('game', 'Игровой'),
  ai('ai', 'Нейросети'),
  streaming('streaming', 'Стриминг'),
  privacy('privacy', 'Приватность'),
  domains('domains', 'Свои домены');

  const RouterMode(this.id, this.title);

  final String id;
  final String title;
}

enum Router1RouteProfileKind {
  goldStandard(
    'gold_standard',
    'Standard',
    'Telegram, WhatsApp и YouTube через Router1, остальное напрямую.',
  ),
  ai(
    'ai',
    '+AI',
    'Standard плюс нейронки. Может быть медленнее.',
  ),
  gamers(
    'gamers',
    'For Gamers',
    'Standard плюс игровые сервисы, без нейронок.',
  );

  const Router1RouteProfileKind(this.id, this.title, this.description);

  final String id;
  final String title;
  final String description;

  bool get includesAi => this == Router1RouteProfileKind.ai;
  bool get includesGames => this == Router1RouteProfileKind.gamers;

  static Router1RouteProfileKind fromId(String? id) {
    final normalized = (id ?? '').trim().toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'ai' || '+ai' || 'plus_ai' => Router1RouteProfileKind.ai,
      'gamers' ||
      'gamer' ||
      'game' ||
      'for_gamers' =>
        Router1RouteProfileKind.gamers,
      _ => Router1RouteProfileKind.goldStandard,
    };
  }

  static Router1RouteProfileKind fromRouterMode(RouterMode mode) {
    return switch (mode) {
      RouterMode.ai => Router1RouteProfileKind.ai,
      RouterMode.game => Router1RouteProfileKind.gamers,
      _ => Router1RouteProfileKind.goldStandard,
    };
  }
}

class Router1Snapshot {
  const Router1Snapshot({
    required this.connected,
    required this.serverName,
    required this.mode,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.pingMs,
    required this.trafficGb,
    required this.devices,
    required this.events,
    required this.demoMode,
  });

  final bool connected;
  final String serverName;
  final RouterMode mode;
  final double downloadMbps;
  final double uploadMbps;
  final int pingMs;
  final double trafficGb;
  final List<KeeneticDevice> devices;
  final List<String> events;
  final bool demoMode;

  static Router1Snapshot demo({RouterMode mode = RouterMode.ai}) {
    return Router1Snapshot(
      connected: true,
      serverName: 'Оптимальный маршрут',
      mode: mode,
      downloadMbps: 184.6,
      uploadMbps: 42.8,
      pingMs: 37,
      trafficGb: 128.4,
      devices: const [
        KeeneticDevice(name: 'Keenetic Giga', type: 'router', online: true),
        KeeneticDevice(name: 'iPhone Павел', type: 'phone', online: true),
        KeeneticDevice(name: 'MacBook', type: 'laptop', online: true),
        KeeneticDevice(name: 'Samsung TV', type: 'tv', online: false),
      ],
      events: const [
        'Нейросети работают без ручных настроек',
        'Telegram, YouTube и ChatGPT под контролем',
        'Keenetic защищает все домашние устройства',
      ],
      demoMode: true,
    );
  }
}

class KeeneticDevice {
  const KeeneticDevice({
    required this.name,
    required this.type,
    required this.online,
  });

  final String name;
  final String type;
  final bool online;
}

class Router1ClientConfig {
  const Router1ClientConfig({
    required this.id,
    required this.deviceName,
    required this.productType,
    required this.protocol,
    required this.status,
    required this.paymentStatus,
    required this.hasConfig,
    required this.filename,
    required this.recommended,
    required this.routerCandidate,
  });

  final int id;
  final String deviceName;
  final String productType;
  final String protocol;
  final String status;
  final String paymentStatus;
  final bool hasConfig;
  final String filename;
  final bool recommended;
  final bool routerCandidate;

  bool get gadgetCandidate {
    final product = productType.toLowerCase();
    return !routerCandidate &&
        hasConfig &&
        (product == 'vpn_config' ||
            product == 'smartphone' ||
            product == 'pc' ||
            deviceName.toLowerCase().contains('смартфон') ||
            deviceName.toLowerCase().contains('ноутбук') ||
            deviceName.toLowerCase().contains('пк'));
  }

  factory Router1ClientConfig.fromJson(Map<String, dynamic> json) {
    return Router1ClientConfig(
      id: (json['id'] as num).toInt(),
      deviceName: json['device_name']?.toString() ?? 'Router1',
      productType: json['product_type']?.toString() ?? '',
      protocol: json['protocol']?.toString() ?? 'wireguard',
      status: json['status']?.toString() ?? '',
      paymentStatus: json['payment_status']?.toString() ?? '',
      hasConfig: json['has_config'] == true,
      filename: json['filename']?.toString() ?? '',
      recommended: json['recommended'] == true,
      routerCandidate: json['router_candidate'] == true,
    );
  }
}

class Router1ClientLookup {
  const Router1ClientLookup({
    required this.clientName,
    required this.clientId,
    required this.recommendedConfigId,
    required this.configs,
  });

  final String clientName;
  final int? clientId;
  final int? recommendedConfigId;
  final List<Router1ClientConfig> configs;

  /// Персональный реферальный код клиента — та же формула, что и на сервере
  /// (router1.db.referral_code_for): "R1" + id, дополненный нулями до 6 цифр.
  String? get referralCode =>
      clientId == null ? null : 'R1${clientId.toString().padLeft(6, '0')}';

  Router1ClientConfig? get recommendedConfig {
    for (final config in configs) {
      if ((config.id == recommendedConfigId || config.recommended) &&
          config.routerCandidate &&
          config.hasConfig) {
        return config;
      }
    }
    for (final config in configs) {
      if (config.routerCandidate && config.hasConfig) return config;
    }
    return null;
  }

  List<Router1ClientConfig> get gadgetConfigs =>
      configs.where((config) => config.gadgetCandidate).toList();

  factory Router1ClientLookup.fromJson(Map<String, dynamic> json) {
    final client = json['client'] as Map<String, dynamic>? ?? const {};
    final configsJson = json['configs'] as List? ?? const [];
    return Router1ClientLookup(
      clientName: client['name']?.toString() ??
          client['full_name']?.toString() ??
          'Клиент Router1',
      clientId: (client['id'] as num?)?.toInt(),
      recommendedConfigId: (json['recommended_config_id'] as num?)?.toInt(),
      configs: configsJson
          .whereType<Map<String, dynamic>>()
          .map(Router1ClientConfig.fromJson)
          .toList(),
    );
  }
}

class Router1Order {
  const Router1Order({
    required this.orderId,
    required this.paymentUrl,
  });

  final String orderId;
  final String paymentUrl;

  factory Router1Order.fromJson(Map<String, dynamic> json) {
    return Router1Order(
      orderId: json['order_id']?.toString() ?? '',
      paymentUrl: json['payment_url']?.toString() ?? '',
    );
  }
}

class Router1RenewalOffer {
  const Router1RenewalOffer({
    required this.key,
    required this.title,
    required this.amount,
    required this.periodDays,
  });

  final String key;
  final String title;
  final int amount;
  final int periodDays;

  factory Router1RenewalOffer.fromJson(Map<String, dynamic> json) {
    return Router1RenewalOffer(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      periodDays: (json['period_days'] as num?)?.toInt() ?? 0,
    );
  }
}

class Router1RenewalOrder {
  const Router1RenewalOrder({
    required this.paymentId,
    required this.amount,
    required this.paymentUrl,
    required this.text,
  });

  final String paymentId;
  final int amount;
  final String paymentUrl;
  final String text;

  factory Router1RenewalOrder.fromJson(Map<String, dynamic> json) {
    return Router1RenewalOrder(
      paymentId: json['payment_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      paymentUrl: json['payment_url']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
    );
  }
}

class Router1OrderStatus {
  const Router1OrderStatus({
    required this.paid,
    required this.configReady,
    required this.orderId,
    required this.confUrl,
    required this.filename,
  });

  final bool paid;
  final bool configReady;
  final String orderId;
  final String confUrl;
  final String filename;

  factory Router1OrderStatus.fromJson(Map<String, dynamic> json) {
    final confUrl = json['conf_url']?.toString() ?? '';
    return Router1OrderStatus(
      paid: json['status'] == 'paid',
      configReady: confUrl.isNotEmpty,
      orderId: json['order_id']?.toString() ?? '',
      confUrl: confUrl,
      filename: json['filename']?.toString() ?? '',
    );
  }
}

class Router1Ipv4Route {
  const Router1Ipv4Route({
    required this.network,
    required this.mask,
  });

  final String network;
  final String mask;
}

class Router1RouteProfile {
  const Router1RouteProfile({
    required this.profileId,
    required this.version,
    required this.mediaDomains,
    required this.aiDomains,
    required this.mediaProbeDomains,
    required this.aiProbeDomains,
    required this.mediaResolvedHosts,
    required this.aiResolvedHosts,
    required this.mediaIpv4Routes,
    required this.aiIpv4Routes,
    required this.telegramIpv4Routes,
    required this.telegramIpv6Routes,
  });

  final String profileId;
  final String version;
  final List<String> mediaDomains;
  final List<String> aiDomains;
  final List<String> mediaProbeDomains;
  final List<String> aiProbeDomains;
  final Map<String, List<String>> mediaResolvedHosts;
  final Map<String, List<String>> aiResolvedHosts;
  final List<Router1Ipv4Route> mediaIpv4Routes;
  final List<Router1Ipv4Route> aiIpv4Routes;
  final List<Router1Ipv4Route> telegramIpv4Routes;
  final List<String> telegramIpv6Routes;

  Router1RouteProfileKind get kind => Router1RouteProfileKind.fromId(profileId);
  bool get includesAi => kind.includesAi || aiDomains.isNotEmpty;
  bool get includesGames => kind.includesGames;

  factory Router1RouteProfile.fromJson(Map<String, dynamic> json) {
    return Router1RouteProfile(
      profileId: json['profile_id']?.toString() ?? 'router-default',
      version: json['version']?.toString() ?? '',
      mediaDomains: _stringList(json['media_domains']),
      aiDomains: _stringList(json['ai_domains']),
      mediaProbeDomains: _stringList(json['media_probe_domains']),
      aiProbeDomains: _stringList(json['ai_probe_domains']),
      mediaResolvedHosts: _hostMap(json['media_resolved_hosts']),
      aiResolvedHosts: _hostMap(json['ai_resolved_hosts']),
      mediaIpv4Routes: _ipv4Routes(json['media_ipv4_routes']),
      aiIpv4Routes: _ipv4Routes(json['ai_ipv4_routes']),
      telegramIpv4Routes: _ipv4Routes(json['telegram_ipv4_routes']),
      telegramIpv6Routes: _stringList(json['telegram_ipv6_routes']),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, List<String>> _hostMap(Object? value) {
    if (value is! Map) return const {};
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final values = _stringList(entry.value);
      if (key.isNotEmpty && values.isNotEmpty) result[key] = values;
    }
    return result;
  }

  static List<Router1Ipv4Route> _ipv4Routes(Object? value) {
    if (value is! List) return const [];
    final result = <Router1Ipv4Route>[];
    for (final item in value) {
      if (item is List && item.length >= 2) {
        final network = item[0].toString().trim();
        final mask = item[1].toString().trim();
        if (network.isNotEmpty && mask.isNotEmpty) {
          result.add(Router1Ipv4Route(network: network, mask: mask));
        }
      } else if (item is Map) {
        final network = item['network']?.toString().trim() ?? '';
        final mask = item['mask']?.toString().trim() ?? '';
        if (network.isNotEmpty && mask.isNotEmpty) {
          result.add(Router1Ipv4Route(network: network, mask: mask));
        }
      }
    }
    return result.toList(growable: false);
  }
}

class Router1Api {
  Router1Api({
    required this.baseUrl,
    required this.token,
    this.demoFallback = true,
  });

  final String baseUrl;
  final String token;
  final bool demoFallback;

  Future<Router1Snapshot> snapshot() async {
    try {
      final status = await _get('/status');
      final traffic = await _get('/traffic');
      final modeId = status['mode'] is Map ? status['mode']['mode'] : null;
      return Router1Snapshot(
        connected: _serviceOk(status, 'wireguard'),
        serverName: status['node']?['NODE_NAME']?.toString() ?? 'Router1',
        mode: _modeFromId(modeId?.toString()),
        downloadMbps: 0,
        uploadMbps: 0,
        pingMs: 0,
        trafficGb: _trafficGb(traffic),
        devices: const [],
        events: const ['Центр управления подключён'],
        demoMode: false,
      );
    } catch (_) {
      if (demoFallback) return Router1Snapshot.demo();
      rethrow;
    }
  }

  Future<void> setMode(RouterMode mode) async {
    await _post('/mode', {'mode': mode.id});
  }

  Future<void> restart() async {
    await _post('/restart', <String, Object?>{});
  }

  Future<List<String>> logs() async {
    final data = await _get('/logs?lines=120');
    final logs = data['logs'];
    if (logs is! List) return const [];
    return logs
        .map((item) => item['stdout']?.toString() ?? '')
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<void> addDomainRoute(RouterMode mode, List<String> domains) async {
    await _post('/domain-route', {
      'mode': mode.id,
      'domains': domains,
    });
  }

  Future<Router1ClientLookup> findClientByPhone(String phone) async {
    final query = Uri(queryParameters: {'phone': phone}).query;
    final data = await _get('/app/client?$query');
    return Router1ClientLookup.fromJson(data);
  }

  Future<String> fetchClientConfigText({
    required String phone,
    required int deviceId,
  }) async {
    final query = Uri(queryParameters: {'phone': phone}).query;
    final data = await _get('/app/config/$deviceId?$query');
    final text = data['config_text']?.toString() ?? '';
    if (text.isEmpty) {
      throw const FormatException('Router1 returned empty config');
    }
    return text;
  }

  Future<Router1Order> createRouterOrder({
    required String name,
    required String phone,
    required bool testMode,
    String? refCode,
  }) async {
    final data = await _post('/order', {
      'product': testMode ? 'router_test' : 'router',
      'name': name,
      'phone': phone,
      if (refCode != null && refCode.trim().isNotEmpty)
        'ref_code': refCode.trim(),
    });
    final order = Router1Order.fromJson(data);
    if (order.orderId.isEmpty || order.paymentUrl.isEmpty) {
      throw const FormatException('Router1 returned incomplete order');
    }
    return order;
  }

  Future<Router1Order> createDeviceOrder({
    required String product,
    required String name,
    required String phone,
    String? refCode,
  }) async {
    final data = await _post('/order', {
      'product': product,
      'name': name,
      'phone': phone,
      if (refCode != null && refCode.trim().isNotEmpty)
        'ref_code': refCode.trim(),
    });
    final order = Router1Order.fromJson(data);
    if (order.orderId.isEmpty || order.paymentUrl.isEmpty) {
      throw const FormatException('Router1 returned incomplete order');
    }
    return order;
  }

  Future<List<Router1RenewalOffer>> renewalOffers() async {
    final data = await _get('/app/renewal-offers');
    final offers = data['offers'] as List? ?? const [];
    return offers
        .whereType<Map<String, dynamic>>()
        .map(Router1RenewalOffer.fromJson)
        .where((offer) => offer.key.isNotEmpty && offer.amount > 0)
        .toList(growable: false);
  }

  Future<Router1RenewalOrder> createRenewalOrder({
    required String phone,
    required String offerKey,
  }) async {
    final data = await _post('/app/renewal-order', {
      'phone': phone,
      'offer_key': offerKey,
    });
    final order = Router1RenewalOrder.fromJson(data);
    if (order.paymentId.isEmpty || order.paymentUrl.isEmpty) {
      throw const FormatException('Router1 returned incomplete renewal order');
    }
    return order;
  }

  Future<Router1OrderStatus> orderStatus(String orderId) async {
    final data = await _get('/order/$orderId');
    return Router1OrderStatus.fromJson(data);
  }

  Future<String> fetchOrderConfigText(String orderId) async {
    final data = await _get('/app/order/$orderId/config');
    final text = data['config_text']?.toString() ?? '';
    if (text.isEmpty) {
      throw const FormatException('Router1 returned empty order config');
    }
    return text;
  }

  Future<Router1RouteProfile> routerRouteProfile({
    Router1RouteProfileKind profile = Router1RouteProfileKind.goldStandard,
  }) async {
    final profileId = Uri.encodeComponent(profile.id);
    final data = await _get('/app/route-profile/$profileId');
    return Router1RouteProfile.fromJson(data);
  }

  Future<String> submitRouterDiagnostics(Map<String, Object?> payload) async {
    final data = await _post('/app/router-diagnostics', payload);
    return data['diagnostic_id']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final request =
        await HttpClient().getUrl(uri).timeout(const Duration(seconds: 12));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, Object?> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final request =
        await HttpClient().postUrl(uri).timeout(const Duration(seconds: 12));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _decode(HttpClientResponse response) async {
    final text = await response.transform(utf8.decoder).join();
    final data = jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(data['error']?.toString() ?? 'Router1 service error');
    }
    return data;
  }

  bool _serviceOk(Map<String, dynamic> status, String key) {
    final services = status['services'];
    return services is Map && services[key] == 'active';
  }

  double _trafficGb(Map<String, dynamic> traffic) {
    final peers = traffic['peers'];
    if (peers is! List) return 0;
    var total = 0;
    for (final peer in peers) {
      if (peer is Map) {
        total += (peer['rx_bytes'] as num? ?? 0).toInt();
        total += (peer['tx_bytes'] as num? ?? 0).toInt();
      }
    }
    return total / 1024 / 1024 / 1024;
  }

  RouterMode _modeFromId(String? id) {
    return switch (id) {
      'game' => RouterMode.game,
      'ai' => RouterMode.ai,
      'streaming' => RouterMode.streaming,
      'privacy' => RouterMode.privacy,
      'domains' => RouterMode.domains,
      'normal' => RouterMode.normal,
      _ => RouterMode.normal,
    };
  }
}
