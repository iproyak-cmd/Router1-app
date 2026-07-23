import 'dart:io';

import 'package:flutter/services.dart';

import 'windows_awg_tunnel_service.dart';

class AwgTunnelStatus {
  const AwgTunnelStatus({
    required this.state,
    this.handshake = -3,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.serverCode = '',
  });
  final String state;
  final int handshake;
  final int rxBytes;
  final int txBytes;
  final String serverCode;

  /// The OS-level tunnel may be UP while DNS, forwarding, or the return route
  /// is broken. Treat the VPN as connected only after payload traffic has
  /// crossed the tunnel in both directions.
  bool get connected => state == 'up' && rxBytes > 0 && txBytes > 0;
}

class AwgTunnelService {
  static const _channel = MethodChannel('tech.router1.app/awg');
  final _windows = WindowsAwgTunnelService();

  AwgTunnelStatus _androidStatus(Map<dynamic, dynamic> value) =>
      AwgTunnelStatus(
        state: value['state']?.toString() ?? 'down',
        handshake: (value['handshake'] as num?)?.toInt() ?? -3,
        rxBytes: (value['rx'] as num?)?.toInt() ?? 0,
        txBytes: (value['tx'] as num?)?.toInt() ?? 0,
        serverCode: value['serverCode']?.toString() ?? '',
      );

  Future<bool> prepare() async {
    if (Platform.isWindows) return true;
    return await _channel.invokeMethod<bool>('prepare') ?? false;
  }

  Future<AwgTunnelStatus> connect(String config,
      {String serverCode = ''}) async {
    if (Platform.isWindows) {
      final value = await _windows.connect(config);
      return AwgTunnelStatus(
        state: value.connected ? 'up' : 'down',
        rxBytes: value.rxBytes,
        txBytes: value.txBytes,
        serverCode: serverCode,
      );
    }
    final value = await _channel.invokeMapMethod<String, dynamic>(
          'connect',
          {'config': config, 'serverCode': serverCode},
        ) ??
        const {};
    return _androidStatus(value);
  }

  Future<bool> configureFailover({
    required String primaryServer,
    required String activeServer,
    required List<Map<String, String>> nodes,
    required int failureSamples,
    required int handshakeStaleSeconds,
    required int switchCooldownSeconds,
  }) async =>
      await _channel.invokeMethod<bool>('configureFailover', {
        'primaryServer': primaryServer,
        'activeServer': activeServer,
        'nodes': nodes,
        'failureSamples': failureSamples,
        'handshakeStaleSeconds': handshakeStaleSeconds,
        'switchCooldownSeconds': switchCooldownSeconds,
      }) ??
      false;

  Future<AwgTunnelStatus> disconnect() async {
    if (Platform.isWindows) {
      final value = await _windows.disconnect();
      return AwgTunnelStatus(
        state: value.connected ? 'up' : 'down',
        rxBytes: value.rxBytes,
        txBytes: value.txBytes,
      );
    }
    final value =
        await _channel.invokeMapMethod<String, dynamic>('disconnect') ??
            const {};
    return _androidStatus(value);
  }

  Future<AwgTunnelStatus> status() async {
    if (Platform.isWindows) {
      final value = await _windows.status();
      return AwgTunnelStatus(
        state: value.connected ? 'up' : 'down',
        rxBytes: value.rxBytes,
        txBytes: value.txBytes,
      );
    }
    final value =
        await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
    return _androidStatus(value);
  }
}
