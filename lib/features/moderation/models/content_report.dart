import 'package:cloud_firestore/cloud_firestore.dart';

/// Motivo de uma denúncia. O texto é o que o usuário escolhe na lista; o
/// `wireValue` é o que fica gravado, pra a lista poder mudar de redação
/// sem invalidar o que já foi denunciado.
enum MotivoDaDenuncia { ofensivo, spam, falso, dadosPessoais, outro }

extension MotivoDaDenunciaWire on MotivoDaDenuncia {
  String get wireValue => switch (this) {
        MotivoDaDenuncia.ofensivo => 'ofensivo',
        MotivoDaDenuncia.spam => 'spam',
        MotivoDaDenuncia.falso => 'falso',
        MotivoDaDenuncia.dadosPessoais => 'dados_pessoais',
        MotivoDaDenuncia.outro => 'outro',
      };

  String get label => switch (this) {
        MotivoDaDenuncia.ofensivo => 'Ofensivo ou discurso de ódio',
        MotivoDaDenuncia.spam => 'Spam ou propaganda',
        MotivoDaDenuncia.falso => 'Informação falsa sobre o serviço',
        MotivoDaDenuncia.dadosPessoais => 'Expõe dados pessoais',
        MotivoDaDenuncia.outro => 'Outro motivo',
      };
}

/// Uma denúncia de conteúdo publicado por um usuário (coleção `reports`).
///
/// Existe por exigência da Apple (App Store Review Guideline 1.2): um app
/// que mostra conteúdo escrito por usuários precisa oferecer um jeito de
/// denunciar esse conteúdo, bloquear quem publicou, e a operação precisa
/// conseguir remover o que foi denunciado — em até 24 horas.
///
/// O texto denunciado é copiado pra cá em `conteudo`. Isso é de propósito:
/// se a avaliação for apagada (pelo cliente que a escreveu, ou pela
/// própria moderação), a denúncia continua legível pra quem for analisar.
/// Uma denúncia que aponta pra um documento que não existe mais é inútil.
///
/// Ninguém no app lê essa coleção — nem quem denunciou. Só a operação, por
/// fora (ver scripts/moderar_denuncias.js). Ver o bloco `reports` no
/// firestore.rules.
class ContentReport {
  ContentReport({
    required this.id,
    required this.listingId,
    required this.autorUid,
    required this.denuncianteUid,
    required this.motivo,
    required this.status,
    this.conteudo,
    this.detalhe,
    this.createdAt,
  });

  factory ContentReport.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ContentReport(
      id: doc.id,
      listingId: data['listingId'] as String? ?? '',
      autorUid: data['autorUid'] as String? ?? '',
      denuncianteUid: data['denuncianteUid'] as String? ?? '',
      motivo: data['motivo'] as String? ?? 'outro',
      status: data['status'] as String? ?? 'aberta',
      conteudo: data['conteudo'] as String?,
      detalhe: data['detalhe'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;

  /// Prestador em cujo perfil a avaliação está — junto com [autorUid]
  /// localiza o documento exato, já que o id da avaliação é o uid de quem
  /// a escreveu (ver ProviderRating).
  final String listingId;

  /// Quem ESCREVEU o conteúdo denunciado.
  final String autorUid;

  /// Quem denunciou.
  final String denuncianteUid;

  final String motivo;
  final String? detalhe;

  /// Cópia do texto no momento da denúncia (ver comentário da classe).
  final String? conteudo;

  /// `aberta` enquanto ninguém analisou; a ferramenta de moderação grava
  /// `removida` ou `mantida` depois da decisão.
  final String status;

  final DateTime? createdAt;
}
