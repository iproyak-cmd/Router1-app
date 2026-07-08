import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/keenetic_router.dart';

class KeeneticDiscoveryService {
  const KeeneticDiscoveryService({
    this.timeout = const Duration(milliseconds: 2200),
  });

  final Duration timeout;

  Future<KeeneticDiscoveryResult> discover({
    bool demoMode = false,
    String? manualAddress,
  }) async {
    final checked = <String>[];
    final logs = <String>[];

    if (demoMode) {
      final router = KeeneticRouter.demo();
      logs.add('[demo] mock router selected: ${router.hostname} ${router.ip}');
      return KeeneticDiscoveryResult(
        router: router,
        routers: [router],
        checked: [router.ip],
        logs: logs,
      );
    }

    final routers = <KeeneticRouter>[];
    final candidates = await _candidates(manualAddress: manualAddress);

    for (final candidate in candidates) {
      checked.add(candidate.address);
      logs.add('check ${candidate.address} type=${candidate.type}');
      final router = await _probe(candidate, logs);
      if (router == null) {
        logs.add(
            'skip ${candidate.address}: not a reachable Keenetic/API endpoint');
      } else {
        logs.add(
            'found ${router.ip}: model=${router.model}; os=${router.firmware ?? 'unknown'}; api=${router.apiAvailable}');
        routers.add(router);
      }
    }

    return KeeneticDiscoveryResult(
      router: routers.isEmpty ? null : routers.first,
      routers: routers,
      checked: checked,
      logs: logs,
    );
  }

  Future<KeeneticDiscoveryResult> probeManual(String address,
      {bool demoMode = false}) {
    return discover(demoMode: demoMode, manualAddress: address);
  }

  Future<List<_Candidate>> _candidates({String? manualAddress}) async {
    final ordered = <_Candidate>[];

    void add(String address, String type) {
      final clean = _cleanAddress(address);
      if (clean.isEmpty) return;
      if (ordered.any((item) => item.address == clean)) return;
      ordered.add(_Candidate(clean, type));
    }

    for (final ip in await _gatewayCandidates()) {
      add(ip, 'local');
    }
    add('192.168.1.1', 'local');
    add('192.168.0.1', 'local');
    add('my.keenetic.net', 'local');
    if (manualAddress != null) {
      add(manualAddress, _connectionTypeFor(manualAddress, manual: true));
    }

    return ordered;
  }

  Future<List<String>> _gatewayCandidates() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      ).timeout(timeout);

      for (final item in interfaces) {
        for (final address in item.addresses) {
          final parts = address.address.split('.');
          if (parts.length != 4) continue;
          if (parts.first == '127' || parts.first == '169') continue;
          parts[3] = '1';
          final gateway = parts.join('.');
          if (!result.contains(gateway)) result.add(gateway);
        }
      }
    } catch (_) {
      // Android may hide interface details on some builds. Static fallbacks still run.
    }
    return result;
  }

  Future<KeeneticRouter?> _probe(
      _Candidate candidate, List<String> logs) async {
    final checks = _probeUris(candidate.address);
    _ProbeResponse? best;

    for (final uri in checks) {
      final response = await _get(uri, logs);
      if (response == null) continue;
      best ??= response;
      if (_looksLikeKeenetic(candidate.address, response)) {
        best = response;
        break;
      }
      if (response.path.contains('/rci/') &&
          (response.statusCode == 401 || response.statusCode == 403)) {
        best = response;
        break;
      }
    }

    if (best == null) return null;
    final apiAvailable = best.path.contains('/rci/') ||
        best.statusCode == 401 ||
        best.statusCode == 403;
    if (!_looksLikeKeenetic(candidate.address, best) && !apiAvailable) {
      return null;
    }

    final firmware = await _firmware(candidate.address, logs);
    final systemText =
        await _getText(candidate.address, '/rci/show/system', logs);
    final interfaceText =
        await _getText(candidate.address, '/rci/show/interface', logs);
    final rciAuthRequired = _hasRciAuthRequired(candidate.address, logs);
    final model = _modelFrom(best.body) ??
        _jsonString(systemText, const ['model', 'description']) ??
        'Keenetic';
    final hostname = _jsonString(systemText, const ['hostname', 'name']) ??
        _modelFrom(best.body) ??
        'Keenetic';
    final webPanelDetected = model.toLowerCase().contains('web panel') ||
        hostname.toLowerCase().contains('web panel');
    final apiAuthenticated = systemText != null || firmware != null;
    final hasRealModel = model.trim().toLowerCase() != 'keenetic' &&
        !model.toLowerCase().contains('web panel');
    final compatible = apiAuthenticated && hasRealModel && firmware != null;

    return KeeneticRouter(
      model: model,
      ip: candidate.address,
      hostname: hostname,
      firmware: firmware,
      wifiName: _wifiName(interfaceText),
      compatible: compatible,
      apiAvailable: apiAuthenticated,
      apiAuthRequired: rciAuthRequired,
      apiAuthenticated: apiAuthenticated,
      webPanelDetected: webPanelDetected,
      connectionType: candidate.type,
      lastError: _lastDiscoveryError(
        apiAuthRequired: rciAuthRequired,
        apiAuthenticated: apiAuthenticated,
        webPanelDetected: webPanelDetected,
        hasRealModel: hasRealModel,
        firmware: firmware,
      ),
      source: candidate.type == 'manual' ? 'manual' : 'auto',
    );
  }

  Future<_ProbeResponse?> _get(Uri uri, List<String> logs) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      logs.add('request GET $uri');
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'Router1');
      final response = await request.close().timeout(timeout);
      final headers = _headers(response);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout, onTimeout: () => '');
      logs.add('response ${response.statusCode} $uri body="${_short(body)}"');
      return _ProbeResponse(
        uri: uri,
        statusCode: response.statusCode,
        headers: headers,
        body: body,
      );
    } on TimeoutException {
      logs.add('error timeout $uri');
      return null;
    } on SocketException catch (e) {
      logs.add('error socket $uri: ${e.message}');
      return null;
    } on HandshakeException catch (e) {
      logs.add('error tls $uri: ${e.message}');
      return null;
    } on FormatException catch (e) {
      logs.add('error uri $uri: ${e.message}');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  List<Uri> _probeUris(String address) {
    final raw = _cleanAddress(address);
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final base = Uri.parse(raw);
      return [
        base.replace(path: '/', query: ''),
        base.replace(path: '/rci/show/version', query: ''),
        base.replace(path: '/rci/show/system', query: ''),
      ];
    }

    final schemes = raw.contains('keenetic.pro')
        ? const ['https', 'http']
        : const ['http', 'https'];
    return [
      for (final scheme in schemes) Uri.parse('$scheme://$raw/'),
      for (final scheme in schemes)
        Uri.parse('$scheme://$raw/rci/show/version'),
      for (final scheme in schemes) Uri.parse('$scheme://$raw/rci/show/system'),
    ];
  }

  Map<String, String> _headers(HttpClientResponse response) {
    final result = <String, String>{};
    response.headers.forEach((name, values) {
      result[name.toLowerCase()] = values.join(' ');
    });
    return result;
  }

  bool _looksLikeKeenetic(String host, _ProbeResponse response) {
    final text =
        '${response.headers.values.join(' ')} ${response.body}'.toLowerCase();
    if (text.contains('keenetic')) return true;
    if (text.contains('ndm') && text.contains('router')) return true;
    if ((host == 'my.keenetic.net' || host.contains('keenetic.pro')) &&
        (response.statusCode == 401 || response.statusCode == 403)) {
      return true;
    }
    return false;
  }

  String? _modelFrom(String body) {
    final title =
        RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
            .firstMatch(body)
            ?.group(1);
    final cleaned = title?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    if (cleaned.toLowerCase().contains('keenetic')) return cleaned;
    return null;
  }

  Future<String?> _firmware(String host, List<String> logs) async {
    for (final path in const ['/rci/show/version', '/rci/show/system']) {
      final text = await _getText(host, path, logs);
      if (text == null || text.isEmpty) continue;
      final match = RegExp(r'(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)').firstMatch(text);
      if (match != null) return match.group(1);
    }
    return null;
  }

  Future<String?> _getText(String host, String path, List<String> logs) async {
    final raw = _cleanAddress(host);
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final base = Uri.parse(raw);
      final response = await _get(base.replace(path: path, query: ''), logs);
      if (response == null ||
          response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode >= 500) {
        return null;
      }
      return response.body;
    }

    final schemes = raw.contains('keenetic.pro')
        ? const ['https', 'http']
        : const ['http', 'https'];
    for (final scheme in schemes) {
      final response = await _get(Uri.parse('$scheme://$raw$path'), logs);
      if (response == null) {
        continue;
      }
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode >= 500) {
        continue;
      }
      return response.body;
    }
    return null;
  }

  String? _wifiName(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'"ssid"\s*:\s*"([^"]+)"').firstMatch(text);
    return match?.group(1);
  }

  String? _jsonString(String? text, List<String> keys) {
    if (text == null || text.isEmpty) return null;
    for (final key in keys) {
      final match = RegExp('"$key"\\s*:\\s*"([^"]+)"').firstMatch(text);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String _short(String text) {
    final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.length <= 120) return value;
    return '${value.substring(0, 120)}...';
  }

  String _cleanAddress(String value) {
    return value.trim().replaceFirst(RegExp(r'/$'), '');
  }

  String _connectionTypeFor(String value, {required bool manual}) {
    final host = value.toLowerCase();
    if (host.contains('keenetic.pro') || host.contains('keenetic.link')) {
      return manual ? 'manual remote KeenDNS' : 'remote KeenDNS';
    }
    return manual ? 'manual' : 'local';
  }

  bool _hasRciAuthRequired(String host, List<String> logs) {
    return logs.any((line) =>
        line.contains(host) &&
        line.contains('/rci/') &&
        (line.contains('response 401') || line.contains('response 403')));
  }

  String? _lastDiscoveryError({
    required bool apiAuthRequired,
    required bool apiAuthenticated,
    required bool webPanelDetected,
    required bool hasRealModel,
    required String? firmware,
  }) {
    if (apiAuthRequired && !apiAuthenticated) {
      return 'API требует логин и пароль администратора.';
    }
    if (webPanelDetected && !apiAuthenticated) {
      return 'Получена Web Panel вместо авторизованного API.';
    }
    if (!hasRealModel) {
      return 'Модель роутера не определена.';
    }
    if (firmware == null || firmware.trim().isEmpty) {
      return 'Версия KeeneticOS не получена.';
    }
    return null;
  }
}

class _Candidate {
  const _Candidate(this.address, this.type);

  final String address;
  final String type;
}

class _ProbeResponse {
  const _ProbeResponse({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  String get path => uri.path;
}
