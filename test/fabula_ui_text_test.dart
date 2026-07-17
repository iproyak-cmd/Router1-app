import 'package:fabula_app/fabula_ui_text.dart';
import 'package:fabula_app/router1_api.dart';
import 'package:fabula_app/services/windows_awg_tunnel_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fabulaAccessLabel', () {
    test('does not promise a hard-coded trial date', () {
      expect(fabulaAccessLabel(null), 'Срок доступа определит сервер');
    });

    test('uses the expiry returned by the server', () {
      expect(
        fabulaAccessLabel(DateTime(2026, 7, 23, 12)),
        'Доступ активен до 23 июля',
      );
    });
  });

  group('fabulaConnectionErrorMessage', () {
    test('explains denied VPN permission', () {
      expect(
        fabulaConnectionErrorMessage(PlatformException(code: 'VPN_DENIED')),
        contains('Разрешите Fabula'),
      );
    });

    test('explains delayed config generation', () {
      expect(
        fabulaConnectionErrorMessage(
          const FormatException('config_generation_timeout'),
        ),
        contains('ещё создаётся'),
      );
    });

    test('does not claim success when the server never handshakes', () {
      expect(
        fabulaConnectionErrorMessage(
          const FormatException('tunnel_handshake_timeout'),
        ),
        contains('Сервер не ответил'),
      );
    });

    test('does not expose an authorization error', () {
      expect(
        fabulaConnectionErrorMessage(
          const Router1ApiException(401, 'internal backend detail'),
        ),
        isNot(contains('internal backend detail')),
      );
    });

    test('keeps safe Windows guidance', () {
      expect(
        fabulaConnectionErrorMessage(
          const WindowsAwgTunnelException('Запустите Fabula снова.'),
        ),
        'Запустите Fabula снова.',
      );
    });
  });
}
