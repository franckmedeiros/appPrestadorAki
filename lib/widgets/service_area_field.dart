import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/brazil_locations.dart';

/// Separador entre cidade e UF no valor guardado ("Criciúma/SC").
const String _separador = '/';

String cidadeDe(String valor) => valor.split(_separador).first.trim();
String ufDe(String valor) {
  final partes = valor.split(_separador);
  return partes.length > 1 ? partes.last.trim() : '';
}

/// Seletor de "onde você atende" — várias cidades, não uma só.
///
/// POR QUE EXISTE (pedido do Franck): a cidade do cadastro era uma só, e
/// era ela que decidia em qual busca o prestador aparecia. Quem mora em
/// Criciúma e atende Florianópolis ficava invisível pra metade dos
/// clientes que poderia atender — e nem sabia disso, porque o app não dá
/// nenhum sinal de "você não apareceu numa busca".
///
/// A cidade do endereço continua sendo a principal (é dela que sai o
/// "Criciúma/SC" no card). Esta lista é o que ele atende ALÉM dela.
///
/// DECISÃO: a cidade principal entra na lista automaticamente e não pode
/// ser removida daqui. Sem isso, bastava alguém abrir a tela, escolher
/// "Florianópolis" e sumir da busca da própria cidade sem entender por quê.
class ServiceAreaField extends StatelessWidget {
  const ServiceAreaField({
    super.key,
    required this.cidadePrincipal,
    required this.ufPrincipal,
    required this.selecionadas,
    required this.onChanged,
  });

  /// Cidade do endereço da conta — sempre presente, sempre primeiro.
  final String? cidadePrincipal;
  final String? ufPrincipal;

  /// Cidades ADICIONAIS, no formato "Cidade/UF".
  final List<String> selecionadas;
  final ValueChanged<List<String>> onChanged;

  String? get _principal {
    final c = (cidadePrincipal ?? '').trim();
    if (c.isEmpty) return null;
    final uf = (ufPrincipal ?? '').trim().toUpperCase();
    return uf.isEmpty ? c : '$c$_separador$uf';
  }

  Future<void> _adicionar(BuildContext context) async {
    final escolhida = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FolhaDeCidade(),
    );
    if (escolhida == null) return;
    // Duplicata (inclusive contra a cidade principal) simplesmente não
    // entra — em vez de avisar de um erro que a pessoa não cometeu.
    if (escolhida == _principal || selecionadas.contains(escolhida)) return;
    onChanged([...selecionadas, escolhida]);
  }

  @override
  Widget build(BuildContext context) {
    final principal = _principal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Onde você atende',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (principal != null)
              Chip(
                avatar: const Icon(Icons.home_outlined, size: 15, color: AppColors.primary),
                label: Text(principal, style: const TextStyle(fontSize: 12.5)),
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
                visualDensity: VisualDensity.compact,
              ),
            for (final cidade in selecionadas)
              Chip(
                label: Text(cidade, style: const TextStyle(fontSize: 12.5)),
                onDeleted: () => onChanged(
                  selecionadas.where((c) => c != cidade).toList(),
                ),
                deleteIcon: const Icon(Icons.close, size: 15),
                visualDensity: VisualDensity.compact,
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Adicionar cidade', style: TextStyle(fontSize: 12.5)),
              onPressed: () => _adicionar(context),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          principal == null
              ? 'Escolha a cidade do seu endereço acima — ela entra aqui sozinha.'
              : 'Você aparece nas buscas de todas as cidades desta lista. '
                  'A do seu endereço não sai.',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

/// Escolhe UF e depois cidade, numa folha só.
///
/// Duas listas em sequência em vez de dois campos lado a lado: aqui a
/// pessoa está ADICIONANDO um item, não preenchendo um formulário — e
/// obrigar a escolher UF num campo pra só então poder tocar no de cidade
/// é o tipo de passo que faz sentido no código e não na mão.
class _FolhaDeCidade extends StatefulWidget {
  const _FolhaDeCidade();

  @override
  State<_FolhaDeCidade> createState() => _FolhaDeCidadeState();
}

class _FolhaDeCidadeState extends State<_FolhaDeCidade> {
  String? _uf;
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.muted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  if (_uf != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      onPressed: () => setState(() {
                        _uf = null;
                        _busca = '';
                      }),
                    ),
                  Expanded(
                    child: Text(
                      _uf == null ? 'Escolha o estado' : 'Cidades de $_uf',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  hintText: _uf == null ? 'Buscar estado' : 'Buscar cidade',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _uf == null ? _listaDeEstados() : _listaDeCidades(_uf!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaDeEstados() {
    return FutureBuilder<List<BrazilState>>(
      future: BrazilLocations.states(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final termo = _busca.trim().toLowerCase();
        final estados = snapshot.data!
            .where((e) =>
                termo.isEmpty ||
                e.name.toLowerCase().contains(termo) ||
                e.uf.toLowerCase().contains(termo))
            .toList();
        return ListView.builder(
          itemCount: estados.length,
          itemBuilder: (context, i) => ListTile(
            title: Text('${estados[i].name} (${estados[i].uf})'),
            onTap: () => setState(() {
              _uf = estados[i].uf;
              _busca = '';
            }),
          ),
        );
      },
    );
  }

  Widget _listaDeCidades(String uf) {
    return FutureBuilder<List<String>>(
      future: BrazilLocations.citiesOf(uf),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final termo = _busca.trim().toLowerCase();
        final cidades = snapshot.data!
            .where((c) => termo.isEmpty || c.toLowerCase().contains(termo))
            .toList();
        if (cidades.isEmpty) {
          return const Center(
            child: Text('Nenhuma cidade encontrada.',
                style: TextStyle(color: AppColors.muted)),
          );
        }
        return ListView.builder(
          itemCount: cidades.length,
          itemBuilder: (context, i) => ListTile(
            title: Text(cidades[i]),
            onTap: () => Navigator.of(context).pop('${cidades[i]}$_separador$uf'),
          ),
        );
      },
    );
  }
}
