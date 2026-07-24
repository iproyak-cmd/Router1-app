from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

old_lookup = """  Future<Router1ClientLookup> _lookupOrCreateTrial() async {
    final current = await _lookupVpnAccess(null, attempts: 3);
    if (current != null && _fabulaConfigs(current).isNotEmpty) return current;
    throw const FormatException('vpn_access_required');
  }
"""
new_lookup = """  Future<Router1ClientLookup> _lookupOrCreateTrial() async {
    final deviceType = Platform.isWindows ? 'laptop_test' : 'smartphone_test';
    final platformAccess = await _lookupVpnAccess(deviceType, attempts: 3);
    if (platformAccess != null && _fabulaConfigs(platformAccess).isNotEmpty) {
      return platformAccess;
    }
    final fallback = await _lookupVpnAccess(null, attempts: 2);
    if (fallback != null && _fabulaConfigs(fallback).isNotEmpty) return fallback;
    throw const FormatException('vpn_access_required');
  }
"""

old_toggle = """  Future<void> _toggleVpn() async {
    if (vpnBusy) return;
    if (phone.trim().isEmpty) {
      await _editProfile(requirePhone: true);
      return;
    }
    setState(() => vpnBusy = true);
    try {
      if (vpn.connected) {
        vpn = await tunnel.disconnect();
      } else {
        final lookup = await _ensureVpnAccess();
        final available = _fabulaConfigs(lookup);
        final candidates = available.where((c) {
          final text = '${c.productType} ${c.deviceName}'.toLowerCase();
          return Platform.isWindows
              ? text.contains('windows') ||
                    text.contains('pc') ||
                    text.contains('пк')
              : text.contains('android') ||
                    text.contains('smartphone') ||
                    text.contains('смартфон');
        }).toList();
        final config = candidates.isNotEmpty
            ? candidates.first
            : (available.isNotEmpty ? available.first : null);
        if (config == null) throw const FormatException('no_config');
        final text = await _fetchVpnConfigWithRetry(config.id);
        await tunnel.prepare();
        vpn = await tunnel.connect(text, serverCode: config.serverCode);
        unawaited(
          _trackEvent(
            'vpn_connected',
            details: {'server_code': config.serverCode},
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Не удалось подготовить подключение. Повторите через минуту.',
            ),
            action: SnackBarAction(label: 'Повторить', onPressed: _toggleVpn),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => vpnBusy = false);
    }
  }
"""

new_toggle = """  Future<void> _toggleVpn() async {
    if (vpnBusy) return;
    if (phone.trim().isEmpty) {
      await _editProfile(requirePhone: true);
      return;
    }
    setState(() => vpnBusy = true);
    var tunnelStarted = false;
    try {
      final current = await tunnel.status();
      if (current.state == 'up') {
        vpn = await tunnel.disconnect();
        if (mounted) setState(() {});
        return;
      }

      final lookup = await _ensureVpnAccess();
      final available = _fabulaConfigs(lookup);
      final candidates = available.where((c) {
        final text = '${c.productType} ${c.deviceName}'.toLowerCase();
        return Platform.isWindows
            ? text.contains('windows') || text.contains('pc') || text.contains('пк')
            : text.contains('android') || text.contains('smartphone') || text.contains('смартфон');
      }).toList();
      final config = candidates.isNotEmpty
          ? candidates.first
          : (available.isNotEmpty ? available.first : null);
      if (config == null) throw const FormatException('no_config');

      final configText = await _fetchVpnConfigWithRetry(config.id);
      final prepared = await tunnel.prepare();
      if (!prepared) throw const FormatException('vpn_permission_denied');

      vpn = await tunnel.connect(configText, serverCode: config.serverCode);
      tunnelStarted = true;

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.getUrl(
          Uri.parse('https://www.cloudflare.com/cdn-cgi/trace?fabula=${DateTime.now().millisecondsSinceEpoch}'),
        );
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close().timeout(const Duration(seconds: 8));
        await response.drain<void>().timeout(const Duration(seconds: 8));
      } finally {
        client.close(force: true);
      }

      AwgTunnelStatus verified = vpn;
      for (var attempt = 0; attempt < 8; attempt++) {
        verified = await tunnel.status();
        if (verified.connected) break;
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
      if (!verified.connected) {
        throw const FormatException('vpn_no_payload_traffic');
      }

      vpn = verified;
      unawaited(
        _trackEvent(
          'vpn_connected',
          details: {
            'server_code': config.serverCode,
            'rx': verified.rxBytes,
            'tx': verified.txBytes,
          },
        ),
      );
    } catch (error) {
      if (tunnelStarted) {
        try {
          vpn = await tunnel.disconnect();
        } catch (_) {
          vpn = const AwgTunnelStatus(state: 'down');
        }
      }
      unawaited(_trackEvent('vpn_connect_failed', details: {'error': error.toString()}));
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().contains('vpn_no_payload_traffic')
                  ? 'VPN не передаёт трафик и был автоматически отключён.'
                  : 'Не удалось подключить VPN. Соединение безопасно отключено.',
            ),
            action: SnackBarAction(label: 'Повторить', onPressed: _toggleVpn),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => vpnBusy = false);
    }
  }
"""

if old_lookup not in text:
    raise SystemExit('VPN lookup block not found; refusing an unsafe patch')
if old_toggle not in text:
    raise SystemExit('VPN toggle block not found; refusing an unsafe patch')

text = text.replace(old_lookup, new_lookup, 1)
text = text.replace(old_toggle, new_toggle, 1)
path.write_text(text, encoding='utf-8')
print('FABULA_VPN_TRAFFIC_VERIFICATION_HOTFIX_OK')
