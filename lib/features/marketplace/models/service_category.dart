import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Uma subcategoria de serviço (folha da árvore de categorias) — ex.:
/// "Eletricista" dentro do grupo "Manutenção e Reparos". O catálogo
/// completo (grupos + subcategorias) é carregado de um asset JSON
/// (`assets/data/service_categories.json`) em vez de viver como um enum
/// fixo no código, porque a lista é grande (mais de cem itens) e tende a
/// crescer ou mudar sem precisar publicar uma nova versão do app.
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.label,
    required this.groupId,
    required this.groupLabel,
    required this.groupEmoji,
  });

  final String id;
  final String label;
  final String groupId;
  final String groupLabel;
  final String groupEmoji;

  /// Valor salvo no Firestore (campo `category` de providers, listings e
  /// solicitações de serviço). É igual ao `id` da subcategoria.
  String get wireValue => id;

  /// Ícone usado no avatar do card de listagem (busca, favoritos,
  /// solicitações) — atribuído por grupo, já que teria pouco sentido
  /// manter um ícone único para cada uma das +100 subcategorias.
  IconData get icon => _iconForGroup(groupId);

  @override
  bool operator ==(Object other) => other is ServiceCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServiceCategory($id)';
}

/// Um grupo de categorias (ex.: "🏠 Casa e Construção") reunindo várias
/// subcategorias ([ServiceCategory]). Usado para organizar o seletor em
/// duas etapas (grupo → subcategoria) em vez de uma lista enorme e plana.
class ServiceCategoryGroup {
  const ServiceCategoryGroup({
    required this.id,
    required this.label,
    required this.emoji,
    required this.subcategories,
  });

  final String id;
  final String label;
  final String emoji;
  final List<ServiceCategory> subcategories;

  /// Ícone usado no avatar do grupo na listagem "Outras categorias" do
  /// seletor (ver `service_category_field.dart`) — mesmo ícone atribuído
  /// às subcategorias do grupo, já que ambos vêm do mesmo `groupId`.
  IconData get icon => _iconForGroup(id);
}

IconData _iconForGroup(String groupId) => switch (groupId) {
      'casa_construcao' => Icons.construction,
      'manutencao_reparos' => Icons.build,
      'climatizacao_eletro' => Icons.ac_unit,
      'jardim_externo' => Icons.yard,
      'automoveis' => Icons.directions_car,
      'limpeza_domestica' => Icons.cleaning_services,
      'tecnologia' => Icons.computer,
      'mudancas_transporte' => Icons.local_shipping,
      'moveis_decoracao' => Icons.chair_outlined,
      'servicos_profissionais' => Icons.badge_outlined,
      'eventos' => Icons.celebration,
      'beleza_bem_estar' => Icons.spa,
      'animais' => Icons.pets,
      _ => Icons.handyman_rounded,
    };

/// Resolve o valor salvo no Firestore para a subcategoria correspondente,
/// caindo em [ServiceCategoryCatalog.outro] quando não encontra (dado
/// legado, categoria removida etc.). Mantém a mesma assinatura que existia
/// quando `ServiceCategory` era um enum, então nenhum call site que só usa
/// esta função precisa mudar.
ServiceCategory serviceCategoryFromWire(String value) => ServiceCategoryCatalog.byWire(value);

/// Carrega e mantém em cache, em memória, o catálogo de categorias e
/// subcategorias a partir de `assets/data/service_categories.json`.
///
/// [load] deve ser chamado uma única vez em `main()`, com `await`, antes de
/// `runApp` — exatamente como já é feito com `Firebase.initializeApp`. Isso
/// garante que o catálogo já esteja pronto de forma síncrona quando
/// `fromFirestore` (em `ProviderListing`/`ServiceRequest`) chamar
/// [serviceCategoryFromWire] ao converter documentos do Firestore.
class ServiceCategoryCatalog {
  ServiceCategoryCatalog._();

  /// Item sintético usado quando uma categoria salva não é reconhecida.
  /// Não faz parte do JSON — sempre disponível, mesmo antes de [load].
  static const ServiceCategory outro = ServiceCategory(
    id: 'outro',
    label: 'Outro',
    groupId: 'outro',
    groupLabel: 'Outro',
    groupEmoji: '🔧',
  );

  static List<ServiceCategoryGroup> _groups = const [];
  static List<ServiceCategory> _all = const [];
  static List<ServiceCategory> _featured = const [];
  static bool _loaded = false;

  static bool get isLoaded => _loaded;

  /// Todos os grupos, na ordem definida no JSON.
  static List<ServiceCategoryGroup> get groups => _groups;

  /// Todas as subcategorias de todos os grupos, em uma lista só (sem
  /// incluir [outro]).
  static List<ServiceCategory> get all => _all;

  /// As subcategorias de destaque ("mais procurados"), na ordem definida
  /// no JSON, para exibir como atalhos rápidos no topo do seletor.
  static List<ServiceCategory> get featured => _featured;

  static Future<void> load() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('assets/data/service_categories.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final groups = <ServiceCategoryGroup>[];
    final all = <ServiceCategory>[];
    for (final groupJson in (json['groups'] as List).cast<Map<String, dynamic>>()) {
      final groupId = groupJson['id'] as String;
      final groupLabel = groupJson['label'] as String;
      final groupEmoji = groupJson['emoji'] as String;

      final subcategories = <ServiceCategory>[];
      for (final subJson in (groupJson['subcategories'] as List).cast<Map<String, dynamic>>()) {
        final category = ServiceCategory(
          id: subJson['id'] as String,
          label: subJson['label'] as String,
          groupId: groupId,
          groupLabel: groupLabel,
          groupEmoji: groupEmoji,
        );
        subcategories.add(category);
        all.add(category);
      }

      groups.add(ServiceCategoryGroup(
        id: groupId,
        label: groupLabel,
        emoji: groupEmoji,
        subcategories: subcategories,
      ));
    }

    final byId = {for (final category in all) category.id: category};
    final featuredIds = (json['featured'] as List).cast<String>();
    final featured = featuredIds.map((id) => byId[id]).whereType<ServiceCategory>().toList();

    _groups = groups;
    _all = all;
    _featured = featured;
    _loaded = true;
  }

  /// Busca uma subcategoria pelo `id`/`wireValue` salvo no Firestore. Cai em
  /// [outro] se não encontrar (ou se [load] ainda não rodou — não deveria
  /// acontecer, já que `main()` sempre espera [load] antes de `runApp`).
  static ServiceCategory byWire(String value) {
    for (final category in _all) {
      if (category.id == value) return category;
    }
    return outro;
  }
}
