import 'package:flutter/services.dart';

class AwgTunnelStatus {
  const AwgTunnelStatus({required this.state, this.handshake = -3});
  final String state;
  final int handshake;
  bool get connected => state == 'up';
}

class AwgTunnelService {
  static const _channel = MethodChannel('tech.router1.app/awg');

  Future<bool> prepare() async =>
      await _channel.invokeMethod<bool>('prepare') ?? false;

  Future<AwgTunnelStatus> connect(String config) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
          'connect',
          {'config': config},
        ) ??
        const {};
    return AwgTunnelStatus(state: value['state']?.toString() ?? 'down');
  }

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
    );
  }
}
