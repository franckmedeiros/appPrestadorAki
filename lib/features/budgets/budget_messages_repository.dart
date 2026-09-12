import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/budget_message.dart';

/// Conversa de um orçamento — a subcoleção `mensagens` debaixo de
/// `providers/{providerId}/budgets/{budgetId}` (ver BudgetMessage pro
/// porquê de morar ali).
///
/// Diferente dos outros repositórios do módulo, este NÃO assume que o
/// usuário logado é o dono do caminho: os dois lados da conversa usam
/// exatamente os mesmos métodos, e o `providerId` vem sempre por
/// parâmetro. Pro prestador ele é o próprio uid; pro cliente é o
/// `Budget.providerUid` que já vem no orçamento. Quem garante que
/// ninguém leia conversa alheia é o firestore.rules, não este código.
class BudgetMessagesRepository {
  BudgetMessagesRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _orcamento(String providerId, String budgetId) =>
      _firestore.collection('providers').doc(providerId).collection('budgets').doc(budgetId);

  CollectionReference<Map<String, dynamic>> _mensagens(String providerId, String budgetId) =>
      _orcamento(providerId, budgetId).collection('mensagens');

  /// Mensagens em ordem cronológica (a mais antiga primeiro), ao vivo.
  ///
  /// Ordena por `createdAt` ascendente e a tela rola pro fim — é o que dá
  /// a sensação de conversa. Uma mensagem recém-enviada aparece aqui
  /// ANTES de ter `createdAt` (o `serverTimestamp()` ainda não voltou do
  /// servidor); o Firestore coloca ela no fim da lista nesse instante,
  /// que por acaso é exatamente onde ela deve ficar.
  Stream<List<BudgetMessage>> watch({
    required String providerId,
    required String budgetId,
  }) =>
      _mensagens(providerId, budgetId)
          .orderBy('createdAt')
          .snapshots()
          .map((snap) => snap.docs.map(BudgetMessage.fromFirestore).toList());

  /// Envia uma mensagem. Quem soma o contador de não lidas do OUTRO lado
  /// e dispara o push é a Cloud Function `onMensagemDoOrcamentoCriada`
  /// — de propósito: se fosse o app a somar, um cliente mal-intencionado
  /// poderia mexer no contador do prestador, e o firestore.rules teria
  /// que abrir o documento do orçamento pra isso.
  Future<void> enviar({
    required String providerId,
    required String budgetId,
    required String texto,
    required bool souPrestador,
    required String meuNome,
  }) async {
    final limpo = texto.trim();
    if (limpo.isEmpty) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw ApiException(0, 'Faça login pra enviar mensagens.');
    try {
      await _mensagens(providerId, budgetId).add(
        BudgetMessage(
          id: '',
          texto: limpo,
          autorUid: uid,
          autorTipo: souPrestador ? AutorMensagem.prestador : AutorMensagem.cliente,
          autorNome: meuNome,
        ).toMap(),
      );
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível enviar a mensagem.');
    }
  }

  /// Zera o MEU contador de não lidas — chamado quando a conversa abre.
  ///
  /// Cada lado só pode zerar o próprio contador (ver firestore.rules); é
  /// por isso que são dois campos separados em vez de um só. Falha em
  /// silêncio de propósito: não conseguir limpar a bolinha não pode
  /// impedir a pessoa de ler a conversa.
  Future<void> marcarComoLidas({
    required String providerId,
    required String budgetId,
    required bool souPrestador,
  }) async {
    // Campo numa variável em vez de um ternário direto na chave do mapa:
    // `{a ? b : c : 0}` é um pesadelo de leitura (e de parser) por causa
    // dos dois `:` na mesma linha.
    final campo = souPrestador ? 'naoLidasPrestador' : 'naoLidasCliente';
    try {
      await _orcamento(providerId, budgetId).update({campo: 0});
    } catch (_) {
      // Sem problema — a bolinha some na próxima vez.
    }
  }
}
