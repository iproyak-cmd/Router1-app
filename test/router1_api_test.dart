import 'package:flutter_test/flutter_test.dart';
import 'package:router1_app_mvp/router1_api.dart';

void main() {
  group('Router1RouteProfileKind', () {
    test('normalizes profile ids and aliases', () {
      expect(
        Router1RouteProfileKind.fromId('gold_standard'),
        Router1RouteProfileKind.goldStandard,
      );
      expect(
        Router1RouteProfileKind.fromId('router-default'),
        Router1RouteProfileKind.goldStandard,
      );
      expect(Router1RouteProfileKind.fromId('+AI'), Router1RouteProfileKind.ai);
      expect(
        Router1RouteProfileKind.fromId('for-gamers'),
        Router1RouteProfileKind.gamers,
      );
    });

    test('exposes stable product metadata', () {
      expect(Router1RouteProfileKind.goldStandard.includesAi, isFalse);
      expect(Router1RouteProfileKind.ai.includesAi, isTrue);
      expect(Router1RouteProfileKind.gamers.includesGames, isTrue);
    });
  });

  group('Router1RouteProfile', () {
    test('parses gold standard as media-only mode', () {
      final profile = Router1RouteProfile.fromJson({
        'profile_id': 'gold_standard',
        'version': '2026-07-08.2',
        'media_domains': ['youtube.com', 'telegram.org', 'whatsapp.com'],
        'ai_domains': [],
        'media_probe_domains': ['www.youtube.com'],
        'ai_probe_domains': [],
        'media_resolved_hosts': {},
        'ai_resolved_hosts': {},
        'media_ipv4_routes': [
          ['91.108.0.0', '255.255.0.0'],
        ],
        'ai_ipv4_routes': [],
        'telegram_ipv4_routes': [],
        'telegram_ipv6_routes': [],
      });

      expect(profile.kind, Router1RouteProfileKind.goldStandard);
      expect(profile.includesAi, isFalse);
      expect(profile.includesGames, isFalse);
      expect(profile.mediaDomains, contains('youtube.com'));
    });

    test('detects ai mode from payload', () {
      final profile = Router1RouteProfile.fromJson({
        'profile_id': 'ai',
        'version': '2026-07-08.2',
        'media_domains': ['youtube.com'],
        'ai_domains': ['chatgpt.com', 'claude.ai'],
        'media_probe_domains': [],
        'ai_probe_domains': ['chatgpt.com'],
        'media_resolved_hosts': {},
        'ai_resolved_hosts': {},
        'media_ipv4_routes': [],
        'ai_ipv4_routes': [
          {'network': '104.16.0.0', 'mask': '255.248.0.0'},
        ],
        'telegram_ipv4_routes': [],
        'telegram_ipv6_routes': [],
      });

      expect(profile.kind, Router1RouteProfileKind.ai);
      expect(profile.includesAi, isTrue);
      expect(profile.aiIpv4Routes.single.network, '104.16.0.0');
    });
  });
}
