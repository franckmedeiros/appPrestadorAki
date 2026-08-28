import 'package:flutter/material.dart';
import '../core/brazil_locations.dart';
import '../core/text_normalize.dart';

/// Caixa de exibição compartilhada por `StateSelectorField` e
/// `CitySelectorField` — visual de `TextFormField` (mesmo `InputDecorator`
/// que qualquer outro campo do formulário usa), mas abre uma lista em vez
/// de deixar digitar.
class _SelectorBox extends StatelessWidget {
  const _SelectorBox({
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

/// Campo de Estado (UF) — abre uma lista com os 27 estados do Brasil em
/// vez de deixar digitar livre (par de `CitySelectorField`; ver a nota em
/// `BrazilLocations` sobre por que isso substituiu o campo de texto
/// livre).
class StateSelectorField extends FormField<String> {
  StateSelectorField({
    Key? key,
    String? initialValue,
    FormFieldValidator<String>? validator,
    bool enabled = true,
    required ValueChanged<String?> onChanged,
    String label = 'Estado (UF)',
  }) : super(
          key: key,
          initialValue: initialValue,
          validator: validator,
          enabled: enabled,
          builder: (field) => _SelectorBox(
            label: label,
            hint: 'Selecione',
            valueText: field.value,
            errorText: field.errorText,
            enabled: field.widget.enabled,
            onTap: !field.widget.enabled
                ? null
                : () async {
                    final uf = await showModalBottomSheet<String>(
                      context: field.context,
                      isScrollControlled: true,
                      builder: (_) => _StatePickerSheet(selected: field.value),
                    );
                    if (uf != null) {
                      field.didChange(uf);
                      onChanged(uf);
                    }
                  },
          ),
        );
}

class _StatePickerSheet extends StatefulWidget {
  const _StatePickerSheet({required this.selected});

  final String? selected;

  @override
  State<_StatePickerSheet> createState() => _StatePickerSheetState();
}

class _StatePickerSheetState extends State<_StatePickerSheet> {
  final _future = BrazilLocations.states();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: FutureBuilder<List<BrazilState>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final states = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Selecione o estado',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: states.length,
                    itemBuilder: (context, index) {
                      final s = states[index];
                      return ListTile(
                        title: Text(s.name),
                        trailing: Text(s.uf, style: const TextStyle(fontWeight: FontWeight.w700)),
                        selected: s.uf == widget.selected,
                        onTap: () => Navigator.of(context).pop(s.uf),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Campo de Cidade — abre uma lista pesquisável com as cidades do estado
/// escolhido em `uf` (fica desabilitado enquanto não houver estado
/// escolhido). Par de `StateSelectorField`.
class CitySelectorField extends FormField<String> {
  CitySelectorField({
    Key? key,
    required String? uf,
    String? initialValue,
    FormFieldValidator<String>? validator,
    required ValueChanged<String?> onChanged,
    String label = 'Cidade',
  }) : super(
          key: key,
          initialValue: initialValue,
          validator: validator,
          enabled: uf != null && uf.isNotEmpty,
          builder: (field) => _SelectorBox(
            label: label,
            hint: field.widget.enabled ? 'Selecione' : 'Escolha o estado primeiro',
            valueText: field.value,
            errorText: field.errorText,
            enabled: field.widget.enabled,
            onTap: !field.widget.enabled
                ? null
                : () async {
                    final city = await showModalBottomSheet<String>(
                      context: field.context,
                      isScrollControlled: true,
                      builder: (_) => _CityPickerSheet(uf: uf!, selected: field.value),
                    );
                    if (city != null) {
                      field.didChange(city);
                      onChanged(city);
                    }
                  },
          ),
        );
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({required this.uf, required this.selected});

  final String uf;
  final String? selected;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  late final Future<List<String>> _future = BrazilLocations.citiesOf(widget.uf);
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: FutureBuilder<List<String>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final query = normalizeForSearch(_query);
            final cities = query.isEmpty
                ? snapshot.data!
                : snapshot.data!.where((c) => normalizeForSearch(c).contains(query)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Buscar cidade',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: cities.isEmpty
                      ? const Center(child: Text('Nenhuma cidade encontrada'))
                      : ListView.builder(
                          itemCount: cities.length,
                          itemBuilder: (context, index) {
                            final c = cities[index];
                            return ListTile(
                              title: Text(c),
                              selected: c == widget.selected,
                              onTap: () => Navigator.of(context).pop(c),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
