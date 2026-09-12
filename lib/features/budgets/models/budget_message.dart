import 'package:cloud_firestore/cloud_firestore.dart';

/// De que lado da conversa veio a mensagem.
///
/// Guardado como CAMPO (`autorTipo`) e não deduzido comparando
/// `autorUid` com o dono do orçamento: a mesma conta pode ser cliente e
/// prestador ao mesmo tempo (conta unificada, ver AuthController), e um
/// prestador pode perfeitamente pedir orçamento a outro. Sem este campo,
/// a tela teria que adivinhar o papel de quem escreveu, e adivinharia
/// errado exatamente nesse caso.
enum AutorMensagem {
  cliente('cliente'),
  prestador('prestador');

  const AutorMensagem(this.wireValue);
  final String wireValue;

  static AutorMensagem fromWire(String? value) =>
      value == 'prestador' ? AutorMensagem.prestador : AutorMensagem.cliente;
}

/// Uma mensagem da conversa de um orçamento
/// (`providers/{providerId}/budgets/{budgetId}/mensagens/{id}`).
///
/// A conversa mora DEBAIXO do orçamento de propósito (pedido do Franck:
/// "ter um lugar no app pra ele perguntar pro cliente, tipo um responder
/// dentro do card"): nasce junto do pedido, morre junto com ele na
/// exclusão da conta (o `recursiveDelete` de
/// functions/src/account.ts já leva subcoleção junto) e nunca vira um
/// chat solto sem assunto. O preço é que não existe "conversa" fora de
/// um orçamento — se um dia precisar, aí sim vira coleção própria.
class BudgetMessage {
  BudgetMessage({
    required this.id,
    required this.texto,
    required this.autorUid,
    required this.autorTipo,
    required this.autorNome,
    this.createdAt,
  });

  factory BudgetMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return BudgetMessage(
      id: doc.id,
      texto: data['texto'] as String? ?? '',
      autorUid: data['autorUid'] as String? ?? '',
      autorTipo: AutorMensagem.fromWire(data['autorTipo'] as String?),
      autorNome: data['autorNome'] as String? ?? '',
      // Null enquanto o `serverTimestamp()` não volta do servidor — a
      // escrita aparece na hora no aparelho de quem enviou (cache local
      // do Firestore) e só depois ganha a data de verdade. A tela precisa
      // aguentar esse instante sem quebrar.
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String texto;
  final String autorUid;
  final AutorMensagem autorTipo;

  /// Nome de quem escreveu, copiado no momento do envio. Cópia em vez de
  /// leitura do perfil na hora de exibir: a conversa é um histórico, e
  /// quem trocou de nome depois não deve reescrever o passado — mesma
  /// lógica de `Budget.customerName`.
  final String autorNome;

  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'texto': texto,
        'autorUid': autorUid,
        'autorTipo': autorTipo.wireValue,
        'autorNome': autorNome,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
