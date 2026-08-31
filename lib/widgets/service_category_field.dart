import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/text_normalize.dart';
import '../features/marketplace/models/service_category.dart';

/// Caixa de exibição do campo de categoria — mesmo visual de
/// `TextFormField` usado pelos outros seletores (ver `_SelectorBox` em
/// `state_city_fields.dart`), duplicado aqui porque aquele é privado ao
/// outro arquivo e o widget é pequeno o bastante para não valer a pena
/// extrair um terceiro arquivo só para compartilhar isso.
class _CategorySelectorBox extends StatelessWidget {
  const _CategorySelectorBox({
    required this.label,
    required this.hint,
    required this.valueText,
    required this.errorText,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String hint;
  final String? valueText;
  final String? errorText;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = valueText != null && valueText!.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          suffixIcon: const Icon(Icons.arrow_drop_down),
          enabled: enabled,
        ),
        child: Text(
          hasValue ? valueText! : hint,
          overflow: TextOverflow.ellipsis,
          style: !hasValue ? TextStyle(color: Theme.of(context).hintColor) : null,
        ),
      ),
    );
  }
}

/// Resultado do bottom sheet: precisa distinguir "usuário fechou sem
/// escolher nada" (sheet retorna null, o campo não muda) de "usuário
/// escolheu 'Todas as categorias'" (sheet retorna um _CategoryPickResult
/// com category == null, o campo é limpo).
class _CategoryPickResult {
  const _CategoryPickResult(this.category);

  final ServiceCategory? category;
}

/// Campo de Categoria de serviço — abre um seletor em duas etapas (grupo
/// → subcategoria, com atalhos para as mais procuradas e busca) em vez de
/// uma lista plana com mais de cem itens. Usado tanto na busca do cliente
/// (com [allowClear] = true, já que "todas as categorias" é uma opção
/// válida) quanto no cadastro do prestador (categoria obrigatória, via
/// [validator]).
class ServiceCategorySelectorField extends FormField<ServiceCategory> {
  ServiceCategorySelectorField({
    Key? key,
    ServiceCategory? initialValue,
    FormFieldValidator<ServiceCategory>? validator,
    bool enabled = true,
    bool allowClear = false,
    required ValueChanged<ServiceCategory?> onChanged,
    String label = 'Categoria',
  }) : super(
          key: key,
          initialValue: initialValue,
          validator: validator,
          enabled: enabled,
          builder: (field) => _CategorySelectorBox(
            label: label,
            hint: 'Selecione',
            valueText: field.value == null ? null : '${field.value!.groupEmoji} ${field.value!.label}',
            errorText: field.errorText,
            enabled: field.widget.enabled,
            onTap: !field.widget.enabled
                ? null
                : () async {
                    final result = await showModalBottomSheet<_CategoryPickResult>(
                      context: field.context,
                      isScrollControlled: true,
                      builder: (_) => _CategoryPickerSheet(
                        selected: field.value,
                        allowClear: allowClear,
                      ),
                    );
                    if (result != null) {
                      field.didChange(result.category);
                      onChanged(result.category);
                    }
                  },
          ),
        );
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({required this.selected, required this.allowClear});

  final ServiceCategory? selected;
  final bool allowClear;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  ServiceCategoryGroup? _openGroup;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _pick(ServiceCategory? category) => Navigator.of(context).pop(_CategoryPickResult(category));

  @override
  Widget build(BuildContext context) {
    final query = normalizeForSearch(_query);
    final searching = query.isNotEmpty;
    final matches = searching
        ? ServiceCategoryCatalog.all.where((c) => normalizeForSearch(c.label).contains(query)).toList()
        : const <ServiceCategory>[];

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  if (!searching && _openGroup != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _openGroup = null),
                    ),
                  Expanded(
                    child: Text(
                      !searching && _openGroup != null
                          ? '${_openGroup!.emoji} ${_openGroup!.label}'
                          : 'Selecione a categoria',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar categoria',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(child: _buildBody(matches, searching)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<ServiceCategory> matches, bool searching) {
    if (searching) {
      if (matches.isEmpty) {
        return const Center(child: Text('Nenhuma categoria encontrada'));
      }
      return ListView.builder(
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final category = matches[index];
          return ListTile(
            title: Text(category.label),
            subtitle: Text('${category.groupEmoji} ${category.groupLabel}'),
            selected: category == widget.selected,
            onTap: () => _pick(category),
          );
        },
      );
    }

    if (_openGroup != null) {
      final subcategories = _openGroup!.subcategories;
      return ListView.builder(
        itemCount: subcategories.length,
        itemBuilder: (context, index) {
          final category = subcategories[index];
          return ListTile(
            title: Text(category.label),
            selected: category == widget.selected,
            onTap: () => _pick(category),
          );
        },
      );
    }

    final groups = ServiceCategoryCatalog.groups;
    final featured = ServiceCategoryCatalog.featured;
    return ListView(
      children: [
        if (widget.allowClear)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pick(null),
              child: Row(
                children: [
                  const Icon(Icons.grid_view_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Todas as categorias',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 15),
                  ),
                  if (widget.selected == null) ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary, size: 18),
                  ],
                ],
              ),
            ),
          ),
        if (featured.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 18),
                SizedBox(width: 6),
                Text('Mais procuradas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.6,
              children: [
                for (final category in featured)
                  _FeaturedCategoryCard(category: category, onTap: () => _pick(category)),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            'Outras categorias',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.muted),
          ),
        ),
        for (final entry in groups.asMap().entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: _CategoryGroupTile(
              group: entry.value,
              color: _groupTileColors[entry.key % _groupTileColors.length],
              onTap: () => setState(() => _openGroup = entry.value),
            ),
          ),
      ],
    );
  }
}

/// Paleta de cores usada nos selos redondos de "Outras categorias" —
/// gira por índice do grupo só pra dar variedade visual, sem significado
/// funcional (não é ligado à cor de nenhuma marca/categoria específica).
const _groupTileColors = <Color>[
  Color(0xFF2E9E5B), // verde
  Color(0xFF1E88E5), // azul
  Color(0xFF00ACC1), // ciano
  Color(0xFF6D4C41), // marrom
  Color(0xFF8E24AA), // roxo
  Color(0xFFE7502E), // laranja da marca
  Color(0xFF3949AB), // índigo
  Color(0xFF00897B), // teal
  Color(0xFFD81B60), // rosa
  Color(0xFF7CB342), // verde claro
  Color(0xFF546E7A), // azul acinzentado
  Color(0xFFF9A825), // âmbar
];

/// Card do grid de "Mais procuradas" — ícone + nome numa caixa com borda
/// arredondada, no lugar do ActionChip antigo (visual a partir de um
/// mockup que o Franck mandou).
class _FeaturedCategoryCard extends StatelessWidget {
  const _FeaturedCategoryCard({required this.category, required this.onTap});

  final ServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.muted.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(category.icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha de "Outras categorias" — selo redondo colorido com o ícone do
/// grupo, título + contagem de subcategorias e seta, dentro de um card
/// com borda leve (visual a partir do mesmo mockup do grid acima).
class _CategoryGroupTile extends StatelessWidget {
  const _CategoryGroupTile({required this.group, required this.color, required this.onTap});

  final ServiceCategoryGroup group;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.muted.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
              child: Icon(group.icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(
                    '${group.subcategories.length} opções',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
