import 'package:flutter/services.dart';

import 'router1_api.dart';
import 'services/windows_awg_tunnel_service.dart';

String fabulaAccessLabel(DateTime? paidUntil) {
  if (paidUntil == null) return 'Срок доступа определит сервер';
  const months = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  final local = paidUntil.toLocal();
  return 'Доступ активен до ${local.day} ${months[local.month - 1]}';
}

String fabulaConnectionErrorMessage(Object error) {
  if (error is WindowsAwgTunnelException) return error.message;
  if (error is PlatformException) {
    return switch (error.code) {
      'VPN_DENIED' =>
        'Разрешите Fabula создать защищённое подключение и повторите.',
      'EMPTY_CONFIG' =>
        'Сервис вернул пустые настройки подключения. Повторите чуть позже.',
      _ => 'Не удалось включить подключение. Проверьте интернет и повторите.',
    };
  }
  if (error is Router1ApiException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'Не удалось подтвердить доступ. Обновите Fabula и повторите.';
    }
    return 'Сервис подключения временно недоступен. Повторите чуть позже.';
  }
  if (error is FormatException &&
      error.message == 'config_generation_timeout') {
    return 'Подключение ещё создаётся. Подождите минуту и повторите.';
  }
  return 'Не удалось включить подключение. Проверьте интернет и повторите.';
}
