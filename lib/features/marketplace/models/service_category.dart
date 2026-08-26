import 'package:flutter/material.dart';

/// Categorias de serviço do marketplace — usadas tanto na busca do lado do
/// cliente quanto no perfil público do prestador. Lista fixa por enquanto;
/// se crescer muito ou precisar ser editável sem publicar uma nova versão
/// do app, isso vira uma coleção de verdade no Firestore em vez de um enum
/// no código.
enum ServiceCategory {
  eletricista,
  encanador,
  pedreiro,
  pintor,
  jardineiro,
  limpeza,
  marceneiro,
  serralheiro,
  climatizacao,
  vidraceiro,
  outro,
}

ServiceCategory serviceCategoryFromWire(String value) => ServiceCategory.values.firstWhere(
      (c) => c.wireValue == value,
      orElse: () => ServiceCategory.outro,
    );

extension ServiceCategoryWire on ServiceCategory {
  String get wireValue => name;

  String get label => switch (this) {
        ServiceCategory.eletricista => 'Eletricista',
        ServiceCategory.encanador => 'Encanador',
        ServiceCategory.pedreiro => 'Pedreiro',
        ServiceCategory.pintor => 'Pintor',
        ServiceCategory.jardineiro => 'Jardineiro',
        ServiceCategory.limpeza => 'Limpeza',
        ServiceCategory.marceneiro => 'Marceneiro',
        ServiceCategory.serralheiro => 'Serralheiro',
        ServiceCategory.climatizacao => 'Climatização',
        ServiceCategory.vidraceiro => 'Vidraceiro',
        ServiceCategory.outro => 'Outro',
      };

  /// Ícone usado no avatar do card de listagem (busca, favoritos,
  /// solicitações) — puramente visual, não afeta a busca nem é salvo em
  /// lugar nenhum.
  IconData get icon => switch (this) {
        ServiceCategory.eletricista => Icons.electrical_services,
        ServiceCategory.encanador => Icons.plumbing,
        ServiceCategory.pedreiro => Icons.construction,
        ServiceCategory.pintor => Icons.format_paint,
        ServiceCategory.jardineiro => Icons.yard,
        ServiceCategory.limpeza => Icons.cleaning_services,
        ServiceCategory.marceneiro => Icons.chair_outlined,
        ServiceCategory.serralheiro => Icons.hardware,
        ServiceCategory.climatizacao => Icons.ac_unit,
        ServiceCategory.vidraceiro => Icons.window,
        ServiceCategory.outro => Icons.handyman_rounded,
      };
}
