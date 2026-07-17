import 'package:flutter_test/flutter_test.dart';
import 'package:fabula_app/router1_api.dart';
import 'package:fabula_app/services/awg_failover_service.dart';

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

    test('maps legacy router modes to product profiles', () {
      expect(
        Router1RouteProfileKind.fromRouterMode(RouterMode.normal),
        Router1RouteProfileKind.goldStandard,
      );
      expect(
        Router1RouteProfileKind.fromRouterMode(RouterMode.streaming),
        Router1RouteProfileKind.goldStandard,
      );
      expect(
        Router1RouteProfileKind.fromRouterMode(RouterMode.ai),
        Router1RouteProfileKind.ai,
      );
      expect(
        Router1RouteProfileKind.fromRouterMode(RouterMode.game),
        Router1RouteProfileKind.gamers,
      );
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

  group('Router1RenewalOffer', () {
    test('parses renewal tariff payload', () {
      final offer = Router1RenewalOffer.fromJson({
        'key': 'subscription_3m',
        'title': '3 месяца',
        'amount': 750,
        'period_days': 90,
      });

      expect(offer.key, 'subscription_3m');
      expect(offer.title, '3 месяца');
      expect(offer.amount, 750);
      expect(offer.periodDays, 90);
    });
  });

  group('Router1Order', () {
    test('parses locked free trial mode', () {
      final order = Router1Order.fromJson({
        'order_id': 'trial-order',
        'payment_url': 'https://router1.tech/success.html',
        'free_trial': true,
        'trial_mode': 'ai',
        'mode_locked': true,
      });

      expect(order.freeTrial, isTrue);
      expect(order.trialMode, Router1RouteProfileKind.ai);
      expect(order.modeLocked, isTrue);
    });
  });

  group('Router1FailoverBundle', () {
    test('parses primary, standby and policy', () {
      final bundle = Router1FailoverBundle.fromJson({
        'device_id': 126,
        'primary_server': 'fr',
        'recommended_server': 'nl2',
        'health': {
          'fr': {'state': 'down'},
          'nl2': {'state': 'healthy'},
        },
        'nodes': [
          {'role': 'primary', 'server_code': 'fr', 'config_text': 'primary'},
          {'role': 'standby', 'server_code': 'nl2', 'config_text': 'standby'},
        ],
        'policy': {
          'failure_samples': 3,
          'handshake_stale_seconds': 180,
          'switch_cooldown_seconds': 300,
          'failback_healthy_samples': 5,
        },
      });

      expect(bundle.deviceId, 126);
      expect(bundle.health['fr'], 'down');
      expect(bundle.node('nl2')?.configText, 'standby');
      expect(bundle.policy.switchCooldownSeconds, 300);
    });

    test('walks through every reserve before cycling back', () {
      const nodes = [
        Router1FailoverNode(
          role: 'primary',
          serverCode: 'fr',
          configText: 'fr-config',
        ),
        Router1FailoverNode(
          role: 'standby',
          serverCode: 'nl2',
          configText: 'nl2-config',
        ),
        Router1FailoverNode(
          role: 'emergency',
          serverCode: 'nl-wg',
          configText: 'wg-config',
        ),
      ];

      expect(
        selectNextFailoverServer(
          nodes: nodes,
          activeServer: 'fr',
          attemptedServers: {'fr'},
          health: const {},
        ),
        'nl2',
      );
      expect(
        selectNextFailoverServer(
          nodes: nodes,
          activeServer: 'nl2',
          attemptedServers: {'fr', 'nl2'},
          health: const {},
        ),
        'nl-wg',
      );
    });

    test('skips a route that the control plane marked down', () {
      const nodes = [
        Router1FailoverNode(
          role: 'primary',
          serverCode: 'fr',
          configText: 'fr-config',
        ),
        Router1FailoverNode(
          role: 'standby',
          serverCode: 'nl2',
          configText: 'nl2-config',
        ),
        Router1FailoverNode(
          role: 'emergency',
          serverCode: 'nl-wg',
          configText: 'wg-config',
        ),
      ];

      expect(
        selectNextFailoverServer(
          nodes: nodes,
          activeServer: 'fr',
          attemptedServers: {'fr'},
          health: const {'nl2': 'down'},
        ),
        'nl-wg',
      );
    });
  });
}
