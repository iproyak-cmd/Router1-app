import 'dart:io';

import 'package:path_provider/path_provider.dart';

class WindowsAwgTunnelState {
  const WindowsAwgTunnelState({
    required this.connected,
    required this.installed,
    this.rxBytes = 0,
    this.txBytes = 0,
  });

  final bool connected;
  final bool installed;
  final int rxBytes;
  final int txBytes;
}

class WindowsAwgTunnelException implements Exception {
  const WindowsAwgTunnelException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WindowsAwgTunnelService {
  static const tunnelName = 'r1pc';
  static const serviceName = 'AmneziaWGTunnel\$$tunnelName';

  Future<String> _findExecutable() async {
    final appDirectory = File(Platform.resolvedExecutable).parent;
    final engineDirectory = Directory('${appDirectory.path}\\engine');
    if (await engineDirectory.exists()) {
      await for (final entity in engineDirectory.list(recursive: true)) {
        if (entity is File &&
            entity.path.toLowerCase().endsWith('\\amneziawg.exe')) {
          return entity.path;
        }
      }
    }
    throw const WindowsAwgTunnelException(
      'Компонент подключения Fabula повреждён. Переустановите Fabula.',
    );
  }

  Future<(File, bool)> _writeConfig(String config) async {
    if (!config.contains('[Interface]') || !config.contains('[Peer]')) {
      throw const WindowsAwgTunnelException('Получен некорректный конфиг.');
    }
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}\\tunnels');
    await directory.create(recursive: true);
    final file = File('${directory.path}\\$tunnelName.conf');
    // Не используем точные default-route /0 на Windows: они включают kill
    // switch движка и блокируют локальную сеть, включая админку роутера.
    final windowsConfig = config.replaceAllMapped(
      RegExp(
        r'^\s*AllowedIPs\s*=\s*(.+)$',
        multiLine: true,
        caseSensitive: false,
      ),
      (match) {
        var value = match.group(1) ?? '';
        value = value.replaceAll('0.0.0.0/0', '0.0.0.0/1, 128.0.0.0/1');
        value = value.replaceAll('::/0', '::/1, 8000::/1');
        return 'AllowedIPs = $value';
      },
    );
    final previous = await file.exists() ? await file.readAsString() : null;
    final changed = previous != windowsConfig;
    await file.writeAsString(windowsConfig, flush: true);
    return (file, changed);
  }

  Future<String?> _findToolExecutable() async {
    final appDirectory = File(Platform.resolvedExecutable).parent;
    final engineDirectory = Directory('${appDirectory.path}\\engine');
    if (!await engineDirectory.exists()) return null;
    await for (final entity in engineDirectory.list(recursive: true)) {
      if (entity is File &&
          entity.uri.pathSegments.last.toLowerCase() == 'awg.exe') {
        return entity.path;
      }
    }
    return null;
  }

  Future<(int, int)> _transferStats() async {
    final tool = await _findToolExecutable();
    if (tool == null) return (0, 0);
    try {
      final result = await Process.run(
        tool,
        const ['show', tunnelName, 'transfer'],
        runInShell: false,
      );
      if (result.exitCode != 0) return (0, 0);
      var rx = 0;
      var tx = 0;
      for (final line in result.stdout.toString().split(RegExp(r'[\r\n]+'))) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length < 3) continue;
        rx += int.tryParse(fields[fields.length - 2]) ?? 0;
        tx += int.tryParse(fields.last) ?? 0;
      }
      return (rx, tx);
    } catch (_) {
      return (0, 0);
    }
  }

  Future<WindowsAwgTunnelState> connect(String config) async {
    final executable = await _findExecutable();
    final prepared = await _writeConfig(config);
    final file = prepared.$1;
    final current = await status();
    if (current.connected && !prepared.$2) return current;
    await _uninstallIfPresent(executable);
    final result = await Process.run(
      executable,
      ['/installtunnelservice', file.path],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      final currentAfterInstall = await status();
      if (currentAfterInstall.connected) return currentAfterInstall;
      final message = result.stderr.toString().trim();
      throw WindowsAwgTunnelException(
        message.isEmpty
            ? 'Windows не разрешила включить подключение. Запустите Fabula от имени администратора.'
            : message,
      );
    }
    return status();
  }

  Future<WindowsAwgTunnelState> disconnect() async {
    final executable = await _findExecutable();
    await _uninstallIfPresent(executable);
    return const WindowsAwgTunnelState(connected: false, installed: false);
  }

  Future<void> _uninstallIfPresent(String executable) async {
    final current = await status();
    if (!current.installed) return;
    final result = await Process.run(
      executable,
      const ['/uninstalltunnelservice', tunnelName],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw const WindowsAwgTunnelException(
        'Не удалось выключить предыдущее подключение Fabula.',
      );
    }
    for (var attempt = 0; attempt < 20; attempt++) {
      final value = await status();
      if (!value.installed) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw const WindowsAwgTunnelException(
      'Windows ещё завершает предыдущее подключение. Подождите несколько секунд и повторите.',
    );
  }

  Future<WindowsAwgTunnelState> status() async {
    final result = await Process.run(
      'sc.exe',
      const ['query', serviceName],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      return const WindowsAwgTunnelState(
        connected: false,
        installed: false,
      );
    }
    final output = '${result.stdout}\n${result.stderr}'.toUpperCase();
    final connected = RegExp(r':\s*4\s+').hasMatch(output) ||
        RegExp(r'\bRUNNING\b').hasMatch(output);
    final stats = connected ? await _transferStats() : (0, 0);
    return WindowsAwgTunnelState(
      // Имя поля локализуется Windows, но числовое состояние 4 остаётся
      // одинаковым на русской и английской системах.
      connected: connected,
      installed: true,
      rxBytes: stats.$1,
      txBytes: stats.$2,
    );
  }
}
