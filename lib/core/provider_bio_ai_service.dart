import 'package:cloud_functions/cloud_functions.dart';

/// Chama a Cloud Function `gerarDescricaoPrestador` (ver
/// functions/src/bio.ts) pra gerar ou melhorar, com IA (Gemini), a
/// "carta de apresentação" do prestador — usado em EditProfileScreen, nos
/// botões "Gerar com IA"/"Melhorar com IA" da seção Descrição.
///
/// Fica só nesse pacotinho fino (em vez de chamar `httpsCallable` direto
/// na tela) pelo mesmo motivo do ProviderLogoService: mais fácil de achar
/// e reaproveitar se algum dia outra tela também precisar disso.
class ProviderBioAiService {
  ProviderBioAiService._();
  static final ProviderBioAiService instance = ProviderBioAiService._();

  /// [rascunho] nulo/vazio pede pra IA gerar do zero, só com
  /// categoria/cidade; preenchido pede pra ela melhorar esse texto.
  Future<String> gerar({
    required String categoria,
    String? cidade,
    String? estado,
    String? rascunho,
  }) async {
    final callable = FirebaseFunctions.instance.httpsCallable('gerarDescricaoPrestador');
    final result = await callable.call<Map<String, dynamic>>({
      'categoria': categoria,
      if (cidade != null && cidade.isNotEmpty) 'cidade': cidade,
      if (estado != null && estado.isNotEmpty) 'estado': estado,
      if (rascunho != null && rascunho.trim().isNotEmpty) 'rascunho': rascunho.trim(),
    });
    return (result.data['descricao'] as String?)?.trim() ?? '';
  }
}
