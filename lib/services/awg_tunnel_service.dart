import 'package:flutter/services.dart';

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
  bool get connected => state == 'up';
}

class AwgTunnelService {
  static const _channel = MethodChannel('tech.router1.app/awg');

  Future<bool> prepare() async =>
      await _channel.invokeMethod<bool>('prepare') ?? false;

  Future<AwgTunnelStatus> connect(String config,
      {String serverCode = ''}) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
          'connect',
          {'config': config, 'serverCode': serverCode},
        ) ??
        const {};
    return AwgTunnelStatus(state: value['state']?.toString() ?? 'down');
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
    final value =
        await _channel.invokeMapMethod<String, dynamic>('disconnect') ??
            const {};
    return AwgTunnelStatus(state: value['state']?.toString() ?? 'down');
  }

  Future<AwgTunnelStatus> status() async {
    final value =
        await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
    return AwgTunnelStatus(
      state: value['state']?.toString() ?? 'down',
      handshake: (value['handshake'] as num?)?.toInt() ?? -3,
      rxBytes: (value['rx'] as num?)?.toInt() ?? 0,
      txBytes: (value['tx'] as num?)?.toInt() ?? 0,
      serverCode: value['serverCode']?.toString() ?? '',
    );
  }
}
