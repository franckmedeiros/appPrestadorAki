import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Avisa o usuário quando sai uma versão nova do app nas lojas.
///
/// Duas frentes (a função `verificarNovaVersao` no servidor confere as
/// lojas de hora em hora e grava `meta/versaoPublicada`):
///
/// 1. PUSH: quem permitiu notificações recebe "Nova versão do PrestadorAki"
///    pelo tópico `atualizacao_android` / `atualizacao_ios`. A inscrição no
///    tópico acontece em [inscreverNoTopico], chamada pelo
///    NotificationService depois que a permissão de notificação foi dada.
///
/// 2. AVISO DENTRO DO APP: ao abrir (e ao voltar pro app), compara a versão
///    instalada com `meta/versaoPublicada` e, se houver uma mais nova,
///    mostra uma faixa no topo com o botão "Atualizar". Isso cobre quem não
///    permitiu notificações e quem nunca fez login.
class AtualizacaoService with WidgetsBindingObserver {
  AtualizacaoService._();
  static final AtualizacaoService instance = AtualizacaoService._();

  /// Passar em `MaterialApp.router(scaffoldMessengerKey: ...)`.
  static final mensageiro = GlobalKey<ScaffoldMessengerState>();

  String? _versaoJaAvisada;
  bool _iniciado = false;

  /// Chamar uma vez no main(), depois do Firebase.initializeApp.
  void iniciar() {
    if (_iniciado || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    _iniciado = true;
    WidgetsBinding.instance.addObserver(this);
    // Dá um tempo pra splash/primeira tela montar antes do aviso.
    Future.delayed(const Duration(seconds: 4), verificar);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(verificar());
  }

  /// Inscreve o aparelho no tópico de avisos de atualização da plataforma.
  /// Chamar depois que a permissão de notificação foi concedida (no iOS o
  /// FCM só aceita inscrição em tópico depois de ter o token APNs).
  Future<void> inscreverNoTopico() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic(Platform.isIOS ? 'atualizacao_ios' : 'atualizacao_android');
    } catch (e) {
      debugPrint('[AtualizacaoService] não inscreveu no tópico: $e');
    }
  }

  Future<void> verificar() async {
    try {
      final snap = await FirebaseFirestore.instance.doc('meta/versaoPublicada').get();
      final dados = snap.data();
      if (dados == null) return;
      final info = await PackageInfo.fromPlatform();

      String? versaoNova;
      String? url;
      if (Platform.isAndroid) {
        final android = dados['android'] as Map<String, dynamic>?;
        final publicada = (android?['versionCode'] as num?)?.toInt();
        final instalada = int.tryParse(info.buildNumber) ?? 0;
        if (publicada != null && publicada > instalada) {
          versaoNova = (android?['nome'] as String?) ?? '$publicada';
          url = android?['url'] as String?;
        }
      } else {
        final ios = dados['ios'] as Map<String, dynamic>?;
        final publicada = ios?['versao'] as String?;
        if (publicada != null && compararVersoes(publicada, info.version) > 0) {
          versaoNova = publicada;
          url = ios?['url'] as String?;
        }
      }

      if (versaoNova == null || url == null || url.isEmpty) return;
      if (_versaoJaAvisada == versaoNova) return; // já mostrou nesta sessão
      _versaoJaAvisada = versaoNova;
      _mostrarAviso(url);
    } catch (e) {
      debugPrint('[AtualizacaoService] não verificou a versão: $e');
    }
  }

  void _mostrarAviso(String url) {
    final m = mensageiro.currentState;
    if (m == null) return;
    m.hideCurrentMaterialBanner();
    m.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update),
        content: const Text('Há uma nova versão do PrestadorAki disponível.'),
        actions: [
          TextButton(
            onPressed: () => m.hideCurrentMaterialBanner(),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () {
              m.hideCurrentMaterialBanner();
              unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
            },
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }

  /// "1.2.10" vs "1.2.9" → 1 (mesma regra do servidor).
  @visibleForTesting
  static int compararVersoes(String a, String b) {
    List<int> partes(String v) => v.split(RegExp(r'[.+]')).map((p) => int.tryParse(p) ?? 0).toList();
    final pa = partes(a), pb = partes(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }
}
