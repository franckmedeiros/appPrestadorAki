import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Conta quem abre o app — inclusive quem nunca chega a criar conta — pra
/// o hub mostrar "abriu e não se cadastrou".
///
/// O que vai pro servidor é só um identificador ANÔNIMO do aparelho (um
/// hash), a plataforma e a versão do app. Nada de nome, e-mail ou
/// telefone. Depois do login o servidor liga esse registro ao uid.
///
/// O identificador sobrevive a desinstalar/instalar de novo, pra não
/// contar a mesma pessoa duas vezes:
/// - Android: ANDROID_ID (só muda num reset de fábrica);
/// - iOS: um código aleatório guardado no Keychain (o Keychain não é
///   apagado quando o app é desinstalado).
///
/// Tudo aqui é "fire-and-forget": se falhar (sem internet etc.), o app
/// segue normal e nada aparece pro usuário.
class InstalacaoService {
  InstalacaoService._();
  static final InstalacaoService instance = InstalacaoService._();

  static const _chaveIos = 'prestadoraki_install_id';
  static const _sal = 'prestadoraki-instalacao-v1';

  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String? _installId;
  String? _ultimoUidRegistrado;
  StreamSubscription<User?>? _authSub;
  Future<void> _abertura = Future.value();

  /// Chamar uma vez no main(), depois do Firebase.initializeApp.
  /// Registra a abertura e, a partir daí, cada login.
  void iniciar() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    // O login espera a abertura terminar, pra não haver duas gravações
    // simultâneas no mesmo registro.
    _abertura = _registrar('abertura');
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _ultimoUidRegistrado = null;
        return;
      }
      if (user.uid == _ultimoUidRegistrado) return;
      _ultimoUidRegistrado = user.uid;
      unawaited(_abertura.then((_) => _registrar('login')));
    });
  }

  Future<void> _registrar(String evento) async {
    try {
      final id = await _obterInstallId();
      final info = await PackageInfo.fromPlatform();
      await FirebaseFunctions.instance.httpsCallable('registrarAbertura').call(<String, dynamic>{
        'installId': id,
        'plataforma': Platform.isIOS ? 'ios' : 'android',
        'versao': '${info.version}+${info.buildNumber}',
        'evento': evento,
      });
    } catch (e) {
      debugPrint('[InstalacaoService] não registrou ($evento): $e');
    }
  }

  Future<String> _obterInstallId() async {
    final emCache = _installId;
    if (emCache != null) return emCache;

    String bruto;
    if (Platform.isAndroid) {
      final androidId = await const AndroidId().getId();
      bruto = (androidId == null || androidId.isEmpty) ? await _idAleatorioGuardado() : 'a:$androidId';
    } else {
      bruto = await _idAleatorioGuardado();
    }
    // Hash: o identificador real do aparelho nunca sai dele.
    final id = sha256.convert(utf8.encode('$_sal|$bruto')).toString().substring(0, 40);
    _installId = id;
    return id;
  }

  Future<String> _idAleatorioGuardado() async {
    final existente = await _storage.read(key: _chaveIos);
    if (existente != null && existente.isNotEmpty) return existente;
    final r = Random.secure();
    final novo = List<int>.generate(16, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _chaveIos, value: novo);
    return novo;
  }
}
