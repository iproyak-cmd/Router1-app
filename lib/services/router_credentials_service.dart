import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedRouterCredentials {
  const SavedRouterCredentials({
    required this.address,
    required this.login,
    required this.password,
  });

  final String address;
  final String login;
  final String password;
}

class RouterCredentialsService {
  // Keep the explicit Android encrypted storage mode while the dependency
  // transparently migrates existing installations to its replacement cipher.
  // ignore: deprecated_member_use
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _addressKey = 'router1_router_address';
  static const _loginKey = 'router1_router_login';
  static const _passwordKey = 'router1_router_password';

  Future<SavedRouterCredentials?> read() async {
    final values = await Future.wait([
      _storage.read(key: _addressKey),
      _storage.read(key: _loginKey),
      _storage.read(key: _passwordKey),
    ]);
    final address = values[0]?.trim() ?? '';
    final login = values[1]?.trim() ?? '';
    final password = values[2] ?? '';
    if (address.isEmpty || password.isEmpty) return null;
    return SavedRouterCredentials(
      address: address,
      login: login.isEmpty ? 'admin' : login,
      password: password,
    );
  }

  Future<void> save({
    required String address,
    required String login,
    required String password,
  }) async {
    await Future.wait([
      _storage.write(key: _addressKey, value: address.trim()),
      _storage.write(
          key: _loginKey, value: login.trim().isEmpty ? 'admin' : login.trim()),
      _storage.write(key: _passwordKey, value: password),
    ]);
  }

  Future<void> clear() => _storage.deleteAll();
}
