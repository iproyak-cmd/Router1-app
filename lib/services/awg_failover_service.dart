import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../router1_api.dart';
import 'awg_tunnel_service.dart';

String? selectNextFailoverServer({
  required List<Router1FailoverNode> nodes,
  required String activeServer,
  required Set<String> attemptedServers,
  required Map<String, String> health,
}) {
  if (nodes.length < 2) return null;
  final activeIndex = nodes.indexWhere(
    (node) => node.serverCode == activeServer,
  );
  final start = activeIndex < 0 ? 0 : activeIndex;
  for (var offset = 1; offset <= nodes.length; offset++) {
    final node = nodes[(start + offset) % nodes.length];
    if (node.serverCode == activeServer ||
        attemptedServers.contains(node.serverCode) ||
        health[node.serverCode] == 'down') {
      continue;
    }
    return node.serverCode;
  }
  return null;
}

class AwgFailoverResult {
  const AwgFailoverResult({
    required this.switched,
    required this.serverCode,
    this.message,
  });

  final bool switched;
  final String serverCode;
  final String? message;
}

/// Foreground failover controller for the embedded Android tunnel.
///
/// Both configurations are cached before they are needed. This lets the app
/// switch nodes even when the active node can no longer reach Router1 API.
class AwgFailoverController {
  AwgFailoverController({
    required this.api,
    required this.tunnel,
    required this.phone,
    required this.deviceId,
  });

  final Router1Api api;
  final AwgTunnelService tunnel;
  final String phone;
  final int deviceId;

  Router1FailoverBundle? _bundle;
  String _activeServer = '';
  int _failureSamples = 0;
  int _primaryHealthySamples = 0;
  DateTime? _lastSwitch;
  DateTime? _lastBundleRefresh;
  bool _switching = false;
  final Set<String> _attemptedServers = <String>{};

  String get activeServer => _activeServer;
  bool get available => (_bundle?.nodes.length ?? 0) > 1;

  String get _cacheKey => 'router1_failover_bundle_$deviceId';
  String get _serverKey => 'router1_failover_server_$deviceId';
  String get _switchKey => 'router1_failover_switched_at_$deviceId';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        _bundle = Router1FailoverBundle.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
      } catch (_) {
        await prefs.remove(_cacheKey);
      }
    }
    _activeServer = prefs.getString(_serverKey) ?? _bundle?.primaryServer ?? '';
    final switchedAt = prefs.getInt(_switchKey);
    if (switchedAt != null) {
      _lastSwitch = DateTime.fromMillisecondsSinceEpoch(switchedAt);
    }
    await _configureNative();
    await refreshBundle(force: true);
  }

  Future<void> refreshBundle({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastBundleRefresh != null &&
        now.difference(_lastBundleRefresh!) < const Duration(seconds: 30)) {
      return;
    }
    _lastBundleRefresh = now;
    try {
      final value = await api.fetchFailoverBundle(
        phone: phone,
        deviceId: deviceId,
      );
      _bundle = value;
      if (_activeServer.isEmpty || value.node(_activeServer) == null) {
        _activeServer = value.primaryServer;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(value.toJson()));
      await prefs.setString(_serverKey, _activeServer);
      await _configureNative();
    } catch (_) {
      // A cached bundle is sufficient during a node outage.
    }
  }

  Future<AwgFailoverResult> evaluate(AwgTunnelStatus status) async {
    await refreshBundle();
    if (status.serverCode.isNotEmpty && status.serverCode != _activeServer) {
      _activeServer = status.serverCode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverKey, _activeServer);
    }
    final bundle = _bundle;
    if (bundle == null || bundle.nodes.length < 2 || !status.connected) {
      _failureSamples = 0;
      _primaryHealthySamples = 0;
      return AwgFailoverResult(
        switched: false,
        serverCode: _activeServer,
      );
    }

    final now = DateTime.now();
    final handshakeAge = status.handshake > 0
        ? now.millisecondsSinceEpoch ~/ 1000 - status.handshake
        : 1 << 30;
    final handshakeFresh = handshakeAge >= 0 &&
        handshakeAge <= bundle.policy.handshakeStaleSeconds;

    if (handshakeFresh) {
      _failureSamples = 0;
      _attemptedServers.clear();
      if (_activeServer != bundle.primaryServer &&
          bundle.health[bundle.primaryServer] == 'healthy') {
        _primaryHealthySamples += 1;
        if (_primaryHealthySamples >= bundle.policy.failbackHealthySamples &&
            _cooldownPassed(bundle.policy, now)) {
          return _switchTo(
              bundle.primaryServer, 'Основной маршрут восстановлен');
        }
      } else {
        _primaryHealthySamples = 0;
      }
      return AwgFailoverResult(
        switched: false,
        serverCode: _activeServer,
      );
    }

    _primaryHealthySamples = 0;
    _failureSamples += 1;
    if (_failureSamples < bundle.policy.failureSamples ||
        !_cooldownPassed(bundle.policy, now)) {
      return AwgFailoverResult(
        switched: false,
        serverCode: _activeServer,
      );
    }

    _attemptedServers.add(_activeServer);
    var candidate = selectNextFailoverServer(
      nodes: bundle.nodes,
      activeServer: _activeServer,
      attemptedServers: _attemptedServers,
      health: bundle.health,
    );
    if (candidate == null) {
      // Every configured route was tried. Start a new ordered cycle without
      // immediately selecting the route that just failed.
      _attemptedServers
        ..clear()
        ..add(_activeServer);
      candidate = selectNextFailoverServer(
        nodes: bundle.nodes,
        activeServer: _activeServer,
        attemptedServers: _attemptedServers,
        health: bundle.health,
      );
    }
    if (candidate == null) {
      return AwgFailoverResult(
        switched: false,
        serverCode: _activeServer,
        message: 'Резервный маршрут временно недоступен',
      );
    }
    return _switchTo(candidate, 'Переключено на резервный маршрут');
  }

  bool _cooldownPassed(Router1FailoverPolicy policy, DateTime now) =>
      _lastSwitch == null ||
      now.difference(_lastSwitch!).inSeconds >= policy.switchCooldownSeconds;

  Future<void> _configureNative() async {
    final bundle = _bundle;
    if (bundle == null || bundle.nodes.length < 2) return;
    try {
      await tunnel.configureFailover(
        primaryServer: bundle.primaryServer,
        activeServer:
            _activeServer.isEmpty ? bundle.primaryServer : _activeServer,
        nodes: [
          for (final node in bundle.nodes)
            {'serverCode': node.serverCode, 'config': node.configText},
        ],
        failureSamples: bundle.policy.failureSamples,
        handshakeStaleSeconds: bundle.policy.handshakeStaleSeconds,
        switchCooldownSeconds: bundle.policy.switchCooldownSeconds,
      );
    } catch (_) {
      // Старые APK не знают нативный метод; foreground-контроллер продолжит работу.
    }
  }

  Future<AwgFailoverResult> _switchTo(
    String serverCode,
    String message,
  ) async {
    if (_switching) {
      return AwgFailoverResult(
        switched: false,
        serverCode: _activeServer,
      );
    }
    final node = _bundle?.node(serverCode);
    if (node == null) {
      return AwgFailoverResult(
        switched: false,
        serverCode: _activeServer,
      );
    }
    _switching = true;
    try {
      final status = await tunnel.connect(
        node.configText,
        serverCode: node.serverCode,
      );
      if (!status.connected) {
        _attemptedServers.add(node.serverCode);
        return AwgFailoverResult(
          switched: false,
          serverCode: _activeServer,
          message: 'Не удалось включить резервный маршрут',
        );
      }
      _activeServer = node.serverCode;
      _lastSwitch = DateTime.now();
      _failureSamples = 0;
      _primaryHealthySamples = 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverKey, _activeServer);
      await prefs.setInt(_switchKey, _lastSwitch!.millisecondsSinceEpoch);
      return AwgFailoverResult(
        switched: true,
        serverCode: _activeServer,
        message: message,
      );
    } finally {
      _switching = false;
    }
  }
}
