import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Router1ApiException implements Exception {
  const Router1ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

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

class Router1DailyHoroscope {
  const Router1DailyHoroscope({
    required this.date,
    required this.sign,
    required this.signTitle,
    required this.symbol,
    required this.lunarPhase,
    required this.overview,
    required this.work,
    required this.money,
    required this.love,
    required this.advice,
    required this.color,
    required this.number,
    required this.tarotTitle,
    required this.tarotMeaning,
    required this.disclaimer,
  });

  final String date;
  final String sign;
  final String signTitle;
  final String symbol;
  final String lunarPhase;
  final String overview;
  final String work;
  final String money;
  final String love;
  final String advice;
  final String color;
  final int number;
  final String tarotTitle;
  final String tarotMeaning;
  final String disclaimer;

  factory Router1DailyHoroscope.fromJson(Map<String, dynamic> json) {
    final tarot = json['tarot'] is Map
        ? Map<String, dynamic>.from(json['tarot'] as Map)
        : const <String, dynamic>{};
    return Router1DailyHoroscope(
      date: json['date']?.toString() ?? '',
      sign: json['sign']?.toString() ?? '',
      signTitle: json['sign_title']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '✦',
      lunarPhase: json['lunar_phase']?.toString() ?? '',
      overview: json['overview']?.toString() ?? '',
      work: json['work']?.toString() ?? '',
      money: json['money']?.toString() ?? '',
      love: json['love']?.toString() ?? '',
      advice: json['advice']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      number: (json['number'] as num?)?.toInt() ?? 1,
      tarotTitle: tarot['title']?.toString() ?? '',
      tarotMeaning: tarot['meaning']?.toString() ?? '',
      disclaimer: json['disclaimer']?.toString() ?? 'Развлекательный прогноз',
    );
  }
}

class Router1ClientConfig {
  const Router1ClientConfig({
    required this.id,
    required this.deviceName,
    required this.productType,
    required this.protocol,
    required this.serverCode,
    required this.status,
    required this.paymentStatus,
    required this.hasConfig,
    required this.filename,
    required this.recommended,
    required this.routerCandidate,
    required this.isTest,
    required this.paidUntil,
  });

  final int id;
  final String deviceName;
  final String productType;
  final String protocol;
  final String serverCode;
  final String status;
  final String paymentStatus;
  final bool hasConfig;
  final String filename;
  final bool recommended;
  final bool routerCandidate;
  final bool isTest;
  final DateTime? paidUntil;

  bool get gadgetCandidate {
    final product = productType.toLowerCase();
    return !routerCandidate &&
        !isTest &&
        hasConfig &&
        (product == 'vpn_config' ||
            product == 'smartphone' ||
            product == 'iphone' ||
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
      serverCode: json['server_code']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      paymentStatus: json['payment_status']?.toString() ?? '',
      hasConfig: json['has_config'] == true,
      filename: json['filename']?.toString() ?? '',
      recommended: json['recommended'] == true,
      routerCandidate: json['router_candidate'] == true,
      isTest: json['is_test'] == true,
      paidUntil: DateTime.tryParse(json['paid_until']?.toString() ?? ''),
    );
  }
}

class Router1FailoverNode {
  const Router1FailoverNode({
    required this.role,
    required this.serverCode,
    required this.configText,
  });

  final String role;
  final String serverCode;
  final String configText;

  factory Router1FailoverNode.fromJson(Map<String, dynamic> json) =>
      Router1FailoverNode(
        role: json['role']?.toString() ?? 'standby',
        serverCode: json['server_code']?.toString() ?? '',
        configText: json['config_text']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'server_code': serverCode,
        'config_text': configText,
      };
}

class Router1FailoverPolicy {
  const Router1FailoverPolicy({
    required this.failureSamples,
    required this.handshakeStaleSeconds,
    required this.switchCooldownSeconds,
    required this.failbackHealthySamples,
  });

  final int failureSamples;
  final int handshakeStaleSeconds;
  final int switchCooldownSeconds;
  final int failbackHealthySamples;

  factory Router1FailoverPolicy.fromJson(Map<String, dynamic> json) =>
      Router1FailoverPolicy(
        failureSamples: (json['failure_samples'] as num?)?.toInt() ?? 3,
        handshakeStaleSeconds:
            (json['handshake_stale_seconds'] as num?)?.toInt() ?? 180,
        switchCooldownSeconds:
            (json['switch_cooldown_seconds'] as num?)?.toInt() ?? 300,
        failbackHealthySamples:
            (json['failback_healthy_samples'] as num?)?.toInt() ?? 5,
      );

  Map<String, dynamic> toJson() => {
        'failure_samples': failureSamples,
        'handshake_stale_seconds': handshakeStaleSeconds,
        'switch_cooldown_seconds': switchCooldownSeconds,
        'failback_healthy_samples': failbackHealthySamples,
      };
}

class Router1FailoverBundle {
  const Router1FailoverBundle({
    required this.deviceId,
    required this.primaryServer,
    required this.recommendedServer,
    required this.health,
    required this.nodes,
    required this.policy,
  });

  final int deviceId;
  final String primaryServer;
  final String recommendedServer;
  final Map<String, String> health;
  final List<Router1FailoverNode> nodes;
  final Router1FailoverPolicy policy;

  Router1FailoverNode? node(String serverCode) {
    for (final value in nodes) {
      if (value.serverCode == serverCode) return value;
    }
    return null;
  }

  factory Router1FailoverBundle.fromJson(Map<String, dynamic> json) {
    final healthJson = json['health'] as Map<String, dynamic>? ?? const {};
    final nodesJson = json['nodes'] as List? ?? const [];
    return Router1FailoverBundle(
      deviceId: (json['device_id'] as num?)?.toInt() ?? 0,
      primaryServer: json['primary_server']?.toString() ?? '',
      recommendedServer: json['recommended_server']?.toString() ?? '',
      health: {
        for (final entry in healthJson.entries)
          entry.key: entry.value is Map
              ? (entry.value as Map)['state']?.toString() ?? 'unknown'
              : 'unknown',
      },
      nodes: nodesJson
          .whereType<Map<String, dynamic>>()
          .map(Router1FailoverNode.fromJson)
          .where((node) =>
              node.serverCode.isNotEmpty && node.configText.isNotEmpty)
          .toList(),
      policy: Router1FailoverPolicy.fromJson(
        json['policy'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'primary_server': primaryServer,
        'recommended_server': recommendedServer,
        'health': {
          for (final entry in health.entries) entry.key: {'state': entry.value},
        },
        'nodes': nodes.map((node) => node.toJson()).toList(),
        'policy': policy.toJson(),
      };
}

class Router1Trial {
  const Router1Trial({
    required this.status,
    required this.mode,
    required this.deviceType,
    required this.orderId,
    required this.orderStatus,
  });
  final String status;
  final Router1RouteProfileKind mode;
  final String deviceType;
  final String orderId;
  final String orderStatus;
  bool get active => const {
        'claimed',
        'activating',
        'active',
        'generation_error'
      }.contains(status);

  factory Router1Trial.fromJson(Map<String, dynamic> json) => Router1Trial(
        status: json['status']?.toString() ?? '',
        mode: Router1RouteProfileKind.fromId(json['mode']?.toString()),
        deviceType: json['device_type']?.toString() ?? '',
        orderId: json['order_id']?.toString() ?? '',
        orderStatus: json['order_status']?.toString() ?? '',
      );
}

class Router1ClientLookup {
  const Router1ClientLookup({
    required this.clientName,
    required this.clientId,
    required this.recommendedConfigId,
    required this.configs,
    required this.trial,
  });

  final String clientName;
  final int? clientId;
  final int? recommendedConfigId;
  final List<Router1ClientConfig> configs;
  final Router1Trial? trial;

  Router1ClientConfig? activeTrialConfig({required bool router}) {
    for (final config in configs) {
      if (!config.isTest || !config.hasConfig) continue;
      if (router != config.routerCandidate) continue;
      if (const {'active', 'paid'}.contains(config.status)) return config;
    }
    return null;
  }

  /// Персональный реферальный код клиента — та же формула, что и на сервере
  /// (router1.db.referral_code_for): "R1" + id, дополненный нулями до 6 цифр.
  String? get referralCode =>
      clientId == null ? null : 'R1${clientId.toString().padLeft(6, '0')}';

  // Бесплатные тестовые конфиги намеренно исключены из "уже оплаченного" распознавания:
  // иначе клиент с ещё живым тестом при попытке купить полную версию получил бы её бесплатно,
  // т.к. эта функция используется для решения "пропустить оплату, конфиг уже есть".
  Router1ClientConfig? get recommendedConfig {
    for (final config in configs) {
      if ((config.id == recommendedConfigId || config.recommended) &&
          config.routerCandidate &&
          !config.isTest &&
          config.hasConfig) {
        return config;
      }
    }
    for (final config in configs) {
      if (config.routerCandidate && !config.isTest && config.hasConfig) {
        return config;
      }
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
      trial: json['trial'] is Map<String, dynamic>
          ? Router1Trial.fromJson(json['trial'] as Map<String, dynamic>)
          : null,
    );
  }
}

class Router1Order {
  const Router1Order({
    required this.orderId,
    required this.paymentUrl,
    required this.freeTrial,
    required this.trialMode,
    required this.modeLocked,
  });

  final String orderId;
  final String paymentUrl;
  final bool freeTrial;
  final Router1RouteProfileKind trialMode;
  final bool modeLocked;

  factory Router1Order.fromJson(Map<String, dynamic> json) {
    return Router1Order(
      orderId: json['order_id']?.toString() ?? '',
      paymentUrl: json['payment_url']?.toString() ?? '',
      freeTrial: json['free_trial'] == true,
      trialMode: Router1RouteProfileKind.fromId(json['trial_mode']?.toString()),
      modeLocked: json['mode_locked'] == true,
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
      final health = await _get('/health');
      final serviceOk = health['ok'] == true;
      if (!serviceOk) {
        throw const FormatException('Router1 API unhealthy');
      }
      return const Router1Snapshot(
        connected: true,
        serverName: 'Router1',
        mode: RouterMode.normal,
        downloadMbps: 0,
        uploadMbps: 0,
        pingMs: 0,
        trafficGb: 0,
        devices: [],
        events: ['API Router1 доступен'],
        demoMode: false,
      );
    } catch (_) {
      if (demoFallback) return Router1Snapshot.demo();
      rethrow;
    }
  }

  Future<Router1DailyHoroscope> dailyHoroscope(String sign) async {
    final data = await _get('/fabula/horoscope/${Uri.encodeComponent(sign)}');
    return Router1DailyHoroscope.fromJson(data);
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

  Future<Router1FailoverBundle> fetchFailoverBundle({
    required String phone,
    required int deviceId,
  }) async {
    final query = Uri(queryParameters: {'phone': phone}).query;
    final data = await _get('/app/failover/$deviceId?$query');
    final bundle = Router1FailoverBundle.fromJson(data);
    if (bundle.deviceId != deviceId || bundle.nodes.isEmpty) {
      throw const FormatException(
          'Router1 returned incomplete failover bundle');
    }
    return bundle;
  }

  Future<Router1Order> createRouterOrder({
    required String name,
    required String phone,
    required bool testMode,
    Router1RouteProfileKind trialMode = Router1RouteProfileKind.goldStandard,
    String? refCode,
  }) async {
    final data = await _post('/order', {
      'product': testMode ? 'router_test' : 'router',
      'name': name,
      'phone': phone,
      if (testMode) 'trial_mode': trialMode.id,
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
    String? email,
    Router1RouteProfileKind trialMode = Router1RouteProfileKind.goldStandard,
    String? refCode,
  }) async {
    final data = await _post('/order', {
      'product': product,
      'name': name,
      'phone': phone,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (product.endsWith('_test')) 'trial_mode': trialMode.id,
      if (refCode != null && refCode.trim().isNotEmpty)
        'ref_code': refCode.trim(),
    });
    final order = Router1Order.fromJson(data);
    if (order.orderId.isEmpty || order.paymentUrl.isEmpty) {
      throw const FormatException('Router1 returned incomplete order');
    }
    return order;
  }

  Future<List<Router1RenewalOffer>> renewalOffers(String phone) async {
    final query = Uri(queryParameters: {'phone': phone}).query;
    final data = await _get('/app/renewal-offers?$query');
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
    final response = await request
        .close()
        .timeout(Duration(seconds: path == '/order' ? 45 : 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _decode(HttpClientResponse response) async {
    final text = await response.transform(utf8.decoder).join();
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      data = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data?['detail']?.toString() ??
          data?['error']?.toString() ??
          (text.trim().isNotEmpty
              ? (text.trim().length > 240
                  ? text.trim().substring(0, 240)
                  : text.trim())
              : 'Router1 service error (${response.statusCode})');
      throw Router1ApiException(response.statusCode, message);
    }
    if (data == null) {
      throw const FormatException('Router1 returned invalid JSON');
    }
    return data;
  }
}
