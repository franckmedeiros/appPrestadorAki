import 'package:flutter/material.dart';

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
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('Todas as categorias'),
            selected: widget.selected == null,
            onTap: () => _pick(null),
          ),
        if (featured.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text('🔥 Mais procurados', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in featured)
                  ActionChip(
                    avatar: Icon(category.icon, size: 18),
                    label: Text(category.label),
                    onPressed: () => _pick(category),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
        for (final group in groups)
          ListTile(
            leading: Text(group.emoji, style: const TextStyle(fontSize: 20)),
            title: Text(group.label),
            subtitle: Text('${group.subcategories.length} opções'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _openGroup = group),
          ),
      ],
    );
  }
}
