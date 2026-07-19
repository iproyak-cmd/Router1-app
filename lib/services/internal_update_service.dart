import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

String get router1InternalVersionUrl => Platform.isWindows
    ? 'https://router1.tech/fabula/windows/version.json'
    : 'https://router1.tech/fabula/android/version.json';

class Router1InternalUpdate {
  const Router1InternalUpdate({
    required this.version,
    required this.build,
    required this.minSupportedBuild,
    required this.url,
    required this.notes,
  });

  final String version;
  final int build;
  final int minSupportedBuild;
  final String url;
  final String notes;

  bool isRequiredFor(int currentBuild) => currentBuild < minSupportedBuild;
}

class InternalUpdateService {
  static const _channel = MethodChannel('tech.router1.app/awg');

  Future<Router1InternalUpdate?> check(int currentBuild) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(router1InternalVersionUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final build = (json['build'] as num?)?.toInt() ?? 0;
      if (build <= currentBuild) return null;
      final url = json['url']?.toString() ?? '';
      final downloadUri = Uri.tryParse(url);
      if (downloadUri == null ||
          downloadUri.scheme != 'https' ||
          downloadUri.host != 'router1.tech' ||
          !downloadUri.path.startsWith('/fabula/')) {
        return null;
      }
      return Router1InternalUpdate(
        version: json['version']?.toString() ?? '',
        build: build,
        minSupportedBuild: (json['min_supported_build'] as num?)?.toInt() ?? 0,
        url: url,
        notes: json['notes']?.toString() ?? '',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> install(String url) async {
    if (Platform.isWindows) {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw PlatformException(
          code: 'update_download_failed',
          message: 'Не удалось открыть загрузку обновления.',
        );
      }
      return;
    }
    await _channel.invokeMethod<bool>('installUpdate', {'url': url});
  }
}
