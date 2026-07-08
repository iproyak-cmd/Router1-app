class KeeneticRouter {
  const KeeneticRouter({
    required this.model,
    required this.ip,
    required this.compatible,
    this.firmware,
    this.wifiName,
    this.hostname,
    this.apiAvailable = false,
    this.apiAuthRequired = false,
    this.apiAuthenticated = false,
    this.webPanelDetected = false,
    this.connectionType = 'local',
    this.lastError,
    this.source = 'auto',
  });

  final String model;
  final String ip;
  final String? firmware;
  final String? wifiName;
  final String? hostname;
  final bool apiAvailable;
  final bool apiAuthRequired;
  final bool apiAuthenticated;
  final bool webPanelDetected;
  final String connectionType;
  final String? lastError;
  final bool compatible;
  final String source;

  bool get hasRealModel {
    final value = model.trim().toLowerCase();
    return value.isNotEmpty &&
        value != 'keenetic' &&
        !value.contains('web panel');
  }

  bool get hasFirmware => firmware != null && firmware!.trim().isNotEmpty;

  bool get needsAuth => apiAuthRequired && !apiAuthenticated;

  bool get readyForAutoSetup =>
      compatible && apiAuthenticated && hasRealModel && hasFirmware;

  String get compatibilityStatus {
    if (readyForAutoSetup) return 'ready';
    if (needsAuth) return 'auth_required';
    if (webPanelDetected) return 'web_panel_only';
    if (!hasFirmware) return 'os_unknown';
    if (!hasRealModel) return 'model_unknown';
    return 'not_ready';
  }

  String get compatibilityMessage {
    switch (compatibilityStatus) {
      case 'ready':
        return 'Роутер готов к автонастройке.';
      case 'auth_required':
        return 'Роутер найден, нужна авторизация администратора.';
      case 'web_panel_only':
        return 'Найдена web panel Keenetic, но API еще не авторизован.';
      case 'os_unknown':
        return 'Версия KeeneticOS не получена.';
      case 'model_unknown':
        return 'Модель роутера не определена.';
      default:
        return 'Роутер найден, но автонастройка еще не подтверждена.';
    }
  }

  factory KeeneticRouter.manual({String ip = '192.168.1.1'}) {
    return KeeneticRouter(
      model: 'Keenetic',
      ip: ip,
      firmware: null,
      wifiName: null,
      compatible: false,
      apiAuthRequired: true,
      source: 'manual',
      connectionType: _connectionTypeFor(ip),
    );
  }

  factory KeeneticRouter.demo() {
    return const KeeneticRouter(
      model: 'KN-xxxx',
      ip: '192.168.1.1',
      hostname: 'Router1 Keenetic Test',
      wifiName: 'Router1 Test Wi-Fi',
      firmware: 'KeeneticOS Demo',
      compatible: true,
      apiAvailable: true,
      apiAuthenticated: true,
      connectionType: 'local',
      source: 'demo',
    );
  }

  static String _connectionTypeFor(String value) {
    final host = value.toLowerCase();
    if (host.contains('keenetic.pro') || host.contains('keenetic.link')) {
      return 'remote KeenDNS';
    }
    return 'local';
  }
}

class KeeneticDiscoveryResult {
  const KeeneticDiscoveryResult({
    required this.router,
    required this.routers,
    required this.checked,
    required this.logs,
  });

  final KeeneticRouter? router;
  final List<KeeneticRouter> routers;
  final List<String> checked;
  final List<String> logs;

  bool get found => router != null;
}
