import 'dart:async';
import 'dart:io';

/// Verifies that a VPN route carries real application traffic.
///
/// A WireGuard handshake alone only proves that the peer answered.  It does
/// not prove that DNS, forwarding and the return path work.  Fabula therefore
/// probes both Telegram's TCP edge and a small HTTPS connectivity endpoint.
class TunnelConnectivityProbe {
  const TunnelConnectivityProbe();

  Future<bool> isUsable({Duration timeout = const Duration(seconds: 3)}) async {
    final checks = <Future<bool>>[
      _telegram('149.154.167.51', timeout),
      _telegram('91.108.56.100', timeout),
      _https(Uri.parse('https://connectivitycheck.gstatic.com/generate_204'), timeout),
      _https(Uri.parse('https://cp.cloudflare.com/generate_204'), timeout),
    ];
    final completer = Completer<bool>();
    var remaining = checks.length;
    for (final check in checks) {
      check.then((ok) {
        if (ok && !completer.isCompleted) completer.complete(true);
      }).catchError((_) {}).whenComplete(() {
        remaining -= 1;
        if (remaining == 0 && !completer.isCompleted) completer.complete(false);
      });
    }
    return completer.future.timeout(
      timeout + const Duration(milliseconds: 300),
      onTimeout: () => false,
    );
  }

  Future<bool> _telegram(String address, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(address, 443, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<bool> _https(Uri uri, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
