import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../daily_look.dart';

class DailyLookService {
  const DailyLookService();

  static const _catalogUrl =
      'https://router1.tech/fabula/content/daily-looks.json';
  static const _dateKey = 'fabula_daily_look_date';
  static const _lookIdKey = 'fabula_daily_look_id';
  static const _seenIdsKey = 'fabula_daily_look_seen_ids';
  static const _manifestCacheKey = 'fabula_daily_look_manifest_cache';

  Future<DailyLook?> resolve({
    required String installationId,
    required DateTime date,
    required SharedPreferences preferences,
  }) async {
    final day = _dateOnly(date);
    final dayKey = day.toIso8601String();
    final catalog = await _catalog(preferences, day);
    final storedId = preferences.getString(_lookIdKey);
    if (preferences.getString(_dateKey) == dayKey && storedId != null) {
      for (final look in catalog) {
        if (look.id == storedId) return look;
      }
    }

    final seen = (preferences.getStringList(_seenIdsKey) ?? const <String>[])
        .toSet();
    try {
      final look = dailyLookFor(
        installationId: installationId,
        date: day,
        catalog: catalog,
        seenIds: seen,
      );
      seen.add(look.id);
      await preferences.setString(_dateKey, dayKey);
      await preferences.setString(_lookIdKey, look.id);
      await preferences.setStringList(_seenIdsKey, seen.toList()..sort());
      return look;
    } on DailyLookCatalogExhausted {
      // Never reset history: a repeated visual is worse than an editorial pause.
      return null;
    }
  }

  Future<List<DailyLook>> _catalog(
    SharedPreferences preferences,
    DateTime day,
  ) async {
    String? manifest;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.parse(_catalogUrl).replace(
        queryParameters: {'day': day.toIso8601String()},
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode == HttpStatus.ok) {
        manifest = await response.transform(utf8.decoder).join();
        await preferences.setString(_manifestCacheKey, manifest);
      }
    } catch (_) {
      // Offline mode uses the last editorial manifest and bundled reserve.
    } finally {
      client.close(force: true);
    }
    manifest ??= preferences.getString(_manifestCacheKey);
    return _mergeWithBundledReserve(_parseManifest(manifest));
  }
}

List<DailyLook> _parseManifest(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final activeBatchId = decoded['active_batch_id']?.toString().trim() ?? '';
    final looks = decoded['looks'] as List? ?? const [];
    return looks.whereType<Map>().map((item) {
      final json = Map<String, dynamic>.from(item);
      final id = json['id']?.toString().trim() ?? '';
      final batchId = json['batch_id']?.toString().trim() ?? '';
      final imageUrl = json['image_url']?.toString().trim() ?? '';
      final uri = Uri.tryParse(imageUrl);
      if (id.isEmpty ||
          activeBatchId.isEmpty ||
          batchId != activeBatchId ||
          uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'router1.tech' ||
          !uri.path.startsWith('/fabula/content/daily_looks/')) {
        return null;
      }
      return DailyLook(
        id: id,
        imageUrl: imageUrl,
        title: json['title']?.toString().trim() ?? '',
        description: json['description']?.toString().trim() ?? '',
      );
    }).whereType<DailyLook>().where((look) {
      return look.title.isNotEmpty && look.description.isNotEmpty;
    }).toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<DailyLook> _mergeWithBundledReserve(List<DailyLook> remote) {
  final bundled = {for (final look in dailyLookCatalog) look.id: look};
  final merged = <DailyLook>[];
  final ids = <String>{};
  for (final look in remote) {
    if (!ids.add(look.id)) continue;
    merged.add(
      DailyLook(
        id: look.id,
        imageUrl: look.imageUrl,
        assetPath: bundled[look.id]?.assetPath,
        title: look.title,
        description: look.description,
      ),
    );
  }
  if (merged.length >= 8) return merged;
  for (final look in dailyLookCatalog) {
    if (ids.add(look.id)) merged.add(look);
  }
  return merged;
}

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
