import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Ponte com o Google Play Billing pra assinatura mensal do prestador —
/// único gate do app: sem assinatura ativa, a conta nunca vira prestador
/// (nunca aparece na busca de "Encontre um profissional"). Quem só quer
/// contratar serviços (cliente) usa o app de graça pra sempre.
///
/// Mesmo desenho usado no app Resenha pra "criar uma resenha" (ver
/// lib/services/subscription_service.dart de lá), com uma diferença
/// importante: aqui a confirmação da compra (Cloud Function
/// `confirmarAssinaturaPrestador`) também é reforçada por notificações
/// automáticas da própria Play Store (RTDN — ver
/// functions/src/subscription.ts), então se a pessoa parar de pagar o
/// prestador sai da busca sozinho, sem precisar abrir o app.
///
/// A confirmação de verdade (bater o token de compra com a Google Play
/// Developer API) acontece só no servidor. Os erros que a Cloud Function
/// devolve, e os que a própria Play Store devolve durante a compra,
/// chegam aqui como exceções técnicas — [descreverErro] traduz isso pra
/// algo que faça sentido pra quem está usando o app.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  /// Precisa bater exatamente com o ID do produto cadastrado em
  /// Monetizar > Assinaturas no Play Console.
  static const String assinaturaMensalId = 'prestadoraki_assinatura_mensal';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<bool> get disponivel => _iap.isAvailable();

  Future<ProductDetailsResponse> buscarProduto() {
    return _iap.queryProductDetails({assinaturaMensalId});
  }

  /// Começa a escutar o resultado das compras. [onAtivada] dispara
  /// depois que a Cloud Function confirmar a assinatura de verdade e
  /// criar/reativar `providers/{uid}` — só nesse momento é seguro tratar
  /// a conta como prestador no app.
  ///
  /// [category]/[city]/[state] só são usados na PRIMEIRA assinatura
  /// (quando a conta ainda não tem `providers/{uid}`) — é o que a Cloud
  /// Function usa pra criar o cadastro de prestador pela primeira vez.
  /// Numa renovação ou restauração de compra de quem já é prestador,
  /// esses valores são ignorados pelo servidor.
  void iniciarEscuta({
    required void Function() onAtivada,
    required void Function(String mensagem) onErro,
    String? category,
    String? city,
    String? state,
  }) {
    _subscription?.cancel();
    _subscription = _iap.purchaseStream.listen(
      (compras) async {
        for (final compra in compras) {
          if (compra.status == PurchaseStatus.error) {
            onErro(descreverErro(compra.error?.message ?? ''));
          } else if (compra.status == PurchaseStatus.purchased ||
              compra.status == PurchaseStatus.restored) {
            try {
              await FirebaseFunctions.instance
                  .httpsCallable('confirmarAssinaturaPrestador')
                  .call({
                'purchaseToken': compra.verificationData.serverVerificationData,
                'productId': compra.productID,
                if (category != null) 'category': category,
                if (city != null) 'city': city,
                if (state != null) 'state': state,
              });
              onAtivada();
            } catch (e) {
              onErro(descreverErro(e));
            } finally {
              if (compra.pendingCompletePurchase) {
                await _iap.completePurchase(compra);
              }
            }
          }
        }
      },
      onError: (e) => onErro(descreverErro(e)),
    );
  }

  Future<void> comprar(ProductDetails produto) {
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: produto),
    );
  }

  Future<void> restaurarCompras() => _iap.restorePurchases();

  void pararEscuta() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Traduz qualquer erro relacionado à assinatura — tanto os que a
  /// Cloud Function `confirmarAssinaturaPrestador` devolve (ver
  /// functions/src/subscription.ts) quanto os que a própria Play Store
  /// devolve durante a compra — pra uma frase que faça sentido na UI, em
  /// vez de mostrar a exceção técnica crua. Pública porque a tela de
  /// paywall também usa pros erros de [comprar]/[restaurarCompras].
  String descreverErro(Object erro) {
    if (erro is FirebaseFunctionsException) {
      switch (erro.code) {
        case 'permission-denied':
          return 'Essa compra já está associada a outra conta.';
        case 'failed-precondition':
          return 'Sua assinatura ainda não está ativa. Se você acabou de '
              'pagar, aguarde um instante e tente "Já assinei, restaurar '
              'compra".';
        case 'invalid-argument':
          return 'Faltam dados pra concluir seu cadastro de prestador. '
              'Preencha categoria e cidade e tente de novo.';
        case 'unauthenticated':
          return 'Sua sessão expirou. Feche essa tela, faça login de novo '
              'e tente outra vez.';
        default:
          return 'Não conseguimos confirmar sua assinatura agora. Tente '
              'novamente em alguns minutos.';
      }
    }
    final texto = erro.toString().toLowerCase();
    if (texto.contains('already own') || texto.contains('alreadyowned')) {
      return 'Você já tem essa assinatura. Toque em "Já assinei, '
          'restaurar compra" logo abaixo.';
    }
    if (texto.contains('cancel') || texto.contains('user_cancel')) {
      return 'Compra cancelada.';
    }
    if (texto.trim().isEmpty) {
      return 'Não foi possível concluir a compra. Tente novamente.';
    }
    return 'Não foi possível concluir a compra. Tente novamente em '
        'alguns minutos.';
  }
}
