import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Fotos de trabalhos feitos, que aparecem no perfil público do prestador
/// (pedido do Franck: "ter as opções de inserir fotos dos serviços").
///
/// DIFERENTE DA LOGO em um ponto que importa: a logo mora num caminho
/// fixo (`providers/{uid}/logo.jpg`) e cada envio sobrescreve o anterior —
/// por isso ela precisa daquele truque de cache-busting na URL. Aqui cada
/// foto ganha um NOME PRÓPRIO, então a URL é nova por definição, some
/// quando a foto é apagada, e não há o que enganar no cache.
///
/// O nome sai do relógio + um contador, e não de um UUID: não precisa ser
/// imprevisível (o caminho já é protegido pelo uid nas regras), só precisa
/// não colidir quando alguém manda três fotos no mesmo segundo.
class ProviderPhotosService {
  ProviderPhotosService._();
  static final ProviderPhotosService instance = ProviderPhotosService._();

  /// Teto de fotos por prestador.
  ///
  /// Seis é o que cabe num carrossel sem virar rolagem infinita, e chega
  /// pra mostrar trabalho. Sem teto, um prestador entusiasmado sobe
  /// quarenta fotos, o perfil fica pesado no 4G do cliente e a conta do
  /// Storage cresce sem ninguém perceber.
  static const int maximoDeFotos = 6;

  int _sequencia = 0;

  Future<String> enviar({required String uid, required File arquivo}) async {
    _sequencia++;
    final nome = '${DateTime.now().millisecondsSinceEpoch}_$_sequencia.jpg';
    final ref = FirebaseStorage.instance.ref('providers/$uid/fotos/$nome');
    await ref.putFile(arquivo);
    return ref.getDownloadURL();
  }

  /// Apaga o arquivo no Storage.
  ///
  /// Falha de propósito SEM lançar: o que o cliente enxerga é a lista de
  /// URLs no diretório, então tirar a foto da lista já a remove do perfil.
  /// Se o arquivo em si resistir (já apagado, URL de outro formato), o
  /// resultado visível é o mesmo e não faz sentido travar o salvamento do
  /// perfil por causa disso.
  Future<void> apagar(String url) async {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (e) {
      debugPrint('ProviderPhotosService.apagar falhou (seguindo mesmo assim): $e');
    }
  }
}
