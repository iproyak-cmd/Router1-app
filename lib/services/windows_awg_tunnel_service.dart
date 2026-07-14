import 'dart:io';

import 'package:path_provider/path_provider.dart';

class WindowsAwgTunnelState {
  const WindowsAwgTunnelState({
    required this.connected,
    required this.installed,
  });

  final bool connected;
  final bool installed;
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
      'Компонент подключения Router1 повреждён. Переустановите Router1.',
    );
  }

  Future<File> _writeConfig(String config) async {
    if (!config.contains('[Interface]') || !config.contains('[Peer]')) {
      throw const WindowsAwgTunnelException('Получен некорректный конфиг.');
    }
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}\\tunnels');
    await directory.create(recursive: true);
    final file = File('${directory.path}\\$tunnelName.conf');
    await file.writeAsString(config, flush: true);
    return file;
  }

  Future<WindowsAwgTunnelState> connect(String config) async {
    final executable = await _findExecutable();
    final file = await _writeConfig(config);
    final current = await status();
    if (current.connected) return current;
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
            ? 'Windows не разрешила включить подключение. Запустите Router1 от имени администратора.'
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
        'Не удалось выключить предыдущее подключение Router1.',
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
    return WindowsAwgTunnelState(
      // Имя поля локализуется Windows, но числовое состояние 4 остаётся
      // одинаковым на русской и английской системах.
      connected: RegExp(r':\s*4\s+').hasMatch(output) ||
          RegExp(r'\bRUNNING\b').hasMatch(output),
      installed: true,
    );
  }
}
