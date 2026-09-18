import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/content_report.dart';

/// Denúncia de conteúdo e bloqueio de usuários.
///
/// POR QUE EXISTE: a Apple (App Store Review Guideline 1.2) exige que todo
/// app que exibe conteúdo escrito por usuários ofereça, no mínimo, um jeito
/// de denunciar o conteúdo, um jeito de bloquear quem publicou, e um
/// processo de remoção em até 24 horas. Aqui o conteúdo de usuário são as
/// avaliações com comentário (ver ProviderRating).
///
/// Duas coleções, com donos bem diferentes:
///
/// `reports/{id}` — a denúncia. O app só CRIA. Ninguém no app lê, nem
/// quem denunciou: uma denúncia é um pedido de análise, não uma
/// publicação. Quem lê é a operação, por fora (scripts/moderar_denuncias.js).
///
/// `blocks/{meuUid}` — a lista de quem EU bloqueei, um documento por
/// pessoa. Só o dono lê e escreve. O bloqueio é uma preferência particular
/// de quem bloqueia: quem foi bloqueado não é notificado e não perde nada
/// — só deixa de ser visto por aquela pessoa.
class ModerationRepository {
  ModerationRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _meusBloqueios(String uid) =>
      _firestore.collection('blocks').doc(uid);

  /// Registra uma denúncia de uma avaliação.
  ///
  /// [conteudo] é o texto como está NESTE momento. Guardar a cópia é o que
  /// permite analisar a denúncia mesmo depois de a avaliação sumir — e
  /// avaliação some com frequência, porque o próprio autor pode reescrever
  /// a dele a qualquer hora (ver ProviderDirectoryRepository.rate).
  Future<void> denunciarAvaliacao({
    required String listingId,
    required String autorUid,
    required MotivoDaDenuncia motivo,
    String? conteudo,
    String? detalhe,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw ApiException(0, 'Entre na sua conta para denunciar.');
    }
    try {
      await _firestore.collection('reports').add({
        'tipo': 'avaliacao',
        'listingId': listingId,
        'autorUid': autorUid,
        'denuncianteUid': uid,
        'motivo': motivo.wireValue,
        if (detalhe != null && detalhe.trim().isNotEmpty) 'detalhe': detalhe.trim(),
        if (conteudo != null && conteudo.trim().isNotEmpty) 'conteudo': conteudo.trim(),
        'status': 'aberta',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível enviar a denúncia.');
    }
  }

  /// Uids que a conta logada bloqueou, com o nome de cada um pra a tela de
  /// bloqueados não precisar de uma leitura extra por pessoa.
  Future<Map<String, String>> listarBloqueados() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const {};
    try {
      final doc = await _meusBloqueios(uid).get();
      final dados = doc.data()?['bloqueados'];
      if (dados is! Map) return const {};
      return {
        for (final entrada in dados.entries)
          entrada.key.toString(): (entrada.value is Map
                  ? (entrada.value as Map)['nome']?.toString()
                  : null) ??
              'Usuário',
      };
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível carregar sua lista de bloqueados.');
    }
  }

  Future<void> bloquear(String uidBloqueado, {String? nome}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw ApiException(0, 'Entre na sua conta para bloquear alguém.');
    }
    if (uid == uidBloqueado) {
      throw ApiException(0, 'Você não pode bloquear a si mesmo.');
    }
    try {
      // `set` com merge, e não `update`: o documento não existe até o
      // primeiro bloqueio, e `update` num documento inexistente falha.
      await _meusBloqueios(uid).set({
        'bloqueados': {
          uidBloqueado: {
            'nome': (nome == null || nome.trim().isEmpty) ? 'Usuário' : nome.trim(),
            'em': FieldValue.serverTimestamp(),
          },
        },
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível bloquear.');
    }
  }

  Future<void> desbloquear(String uidBloqueado) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _meusBloqueios(uid).update({
        'bloqueados.$uidBloqueado': FieldValue.delete(),
      });
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível desbloquear.');
    }
  }
}
