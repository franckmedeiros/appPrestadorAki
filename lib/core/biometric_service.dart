import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Resultado da tentativa de autenticação biométrica — mesmo modelo usado
/// no app Resenha (`BiometricAuthService`), que já se mostrou confiável
/// tanto em emulador quanto em aparelho físico. Ter um enum com o motivo
/// exato (em vez de só true/false) é o que permite mostrar uma mensagem
/// de verdade pro usuário em vez de "não aconteceu nada".
enum BiometricResult {
  success,
  notAvailable,
  notEnrolled,
  lockedOut,
  permanentlyLockedOut,
  failed,
  error,
}

extension BiometricResultMessage on BiometricResult {
  String get message {
    switch (this) {
      case BiometricResult.success:
        return 'Autenticado com sucesso';
      case BiometricResult.notAvailable:
        return 'Biometria não disponível neste aparelho';
      case BiometricResult.notEnrolled:
        return 'Nenhuma digital ou rosto cadastrado no aparelho';
      case BiometricResult.lockedOut:
        return 'Muitas tentativas. Tente novamente em instantes';
      case BiometricResult.permanentlyLockedOut:
        return 'Biometria bloqueada. Desbloqueie pelo sistema do aparelho';
      case BiometricResult.failed:
        return 'Não foi possível reconhecer sua biometria';
      case BiometricResult.error:
        return 'Erro ao autenticar com biometria';
    }
  }
}

/// Fina camada sobre o `local_auth`. Biometria aqui é um *cadeado local* do
/// app — não substitui o login (JWT) na API, só evita ter que digitar a
/// senha de novo toda vez que o app é reaberto num aparelho já confiável.
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Verifica se o aparelho suporta e tem biometria configurada.
  Future<bool> get isAvailable async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } on PlatformException catch (e) {
      debugPrint('[Biometria] isAvailable lançou PlatformException: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[Biometria] isAvailable lançou exceção: $e');
      return false;
    }
  }

  /// Dispara o prompt nativo de biometria e retorna um resultado detalhado
  /// (não só sucesso/falha) — assim dá pra mostrar o motivo real ao
  /// usuário quando não funcionar, em vez de falhar em silêncio.
  Future<BiometricResult> authenticate({
    String reason = 'Autentique-se para entrar no PrestadorAki',
  }) async {
    try {
      final available = await isAvailable;
      if (!available) return BiometricResult.notAvailable;

      final didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return didAuthenticate ? BiometricResult.success : BiometricResult.failed;
    } on PlatformException catch (e) {
      switch (e.code) {
        case auth_error.notAvailable:
          return BiometricResult.notAvailable;
        case auth_error.notEnrolled:
          return BiometricResult.notEnrolled;
        case auth_error.lockedOut:
          return BiometricResult.lockedOut;
        case auth_error.permanentlyLockedOut:
          return BiometricResult.permanentlyLockedOut;
        default:
          debugPrint('[Biometria] authenticate PlatformException: ${e.code} ${e.message}');
          return BiometricResult.error;
      }
    } catch (e) {
      debugPrint('[Biometria] authenticate lançou exceção: $e');
      return BiometricResult.error;
    }
  }
}
