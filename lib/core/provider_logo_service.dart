import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Sobe a foto de logo do prestador pro Firebase Storage — mesmo padrão
/// do ComprovanteService do app Resenha (image_picker + Storage), usado
/// aqui porque o Franck pediu pra trocar o campo de "colar o link da
/// logo" por um upload de verdade, tocando no ícone do perfil.
///
/// Caminho fixo por prestador (`providers/{uid}/logo.jpg`) — um envio
/// novo SEMPRE sobrescreve o anterior, então trocar a logo não acumula
/// lixo no Storage. Ver storage.rules: só o próprio dono (uid) pode
/// escrever no caminho dele; a leitura é pública porque a logo aparece no
/// perfil público do diretório (ver ProviderDirectoryRepository).
class ProviderLogoService {
  ProviderLogoService._();
  static final ProviderLogoService instance = ProviderLogoService._();

  Future<String> enviar({required String uid, required File arquivo}) async {
    final ref = FirebaseStorage.instance.ref('providers/$uid/logo.jpg');
    await ref.putFile(arquivo);
    final url = await ref.getDownloadURL();
    // Cache-busting: o caminho é sempre o mesmo (fixo por uid) e o token de
    // download não muda numa sobrescrita, então a URL fica idêntica entre
    // envios — sem isso, o cache de imagem do Flutter (e caches HTTP no meio
    // do caminho) continua mostrando a foto antiga depois de trocar, dando
    // a impressão de que "não salvou". Um parâmetro extra que muda a cada
    // envio força buscar a imagem de novo; a Storage ignora parâmetros que
    // não conhece, então isso não quebra a URL.
    return '$url&cb=${DateTime.now().millisecondsSinceEpoch}';
  }
}
