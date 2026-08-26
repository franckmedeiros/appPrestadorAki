import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda só a preferência local de "entrar com biometria" — um cadeado do
/// próprio app, não uma credencial de autenticação. Antes da migração para
/// Firebase Auth, esta classe também guardava o par access/refresh token;
/// isso deixou de ser necessário porque o SDK do Firebase Auth já persiste
/// e renova a sessão sozinho (ver AuthController). Mantivemos o nome da
/// classe e o arquivo para não precisar mexer nos outros pontos que a
/// importam — só o conteúdo mudou.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _biometricKey = 'prestadoraki.biometricEnabled';

  Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _biometricKey, value: enabled ? 'true' : 'false');

  Future<bool> readBiometricEnabled() async =>
      (await _storage.read(key: _biometricKey)) == 'true';

  Future<void> clear() => _storage.delete(key: _biometricKey);
}
