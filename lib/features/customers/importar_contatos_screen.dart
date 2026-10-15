import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../widgets/botao_com_seta.dart';
import '../../widgets/cabecalho_de_tela.dart';
import 'customers_repository.dart';

/// Importa contatos da agenda do celular como clientes (nome + WhatsApp),
/// vários de uma vez.
///
/// O WhatsApp não deixa nenhum app ler a lista de contatos dele; o que dá
/// pra ler é a agenda do aparelho, que é a mesma que o WhatsApp usa.
///
/// - Só aparecem contatos com um número brasileiro válido (10 ou 11
///   dígitos depois de tirar +55, 0 e código de operadora). Com mais de um
///   número, fica o primeiro celular.
/// - Quem já está cadastrado (mesmo número em `phone` ou `whatsapp`)
///   aparece como "Já cadastrado" e não pode ser marcado de novo.
/// - O número é gravado em `phone`, no mesmo formato do campo WhatsApp do
///   cadastro manual: "(48) 99912-3456".
///
/// Devolve (via `Navigator.pop`) quantos clientes foram importados.
class ImportarContatosScreen extends StatefulWidget {
  const ImportarContatosScreen({super.key});

  @override
  State<ImportarContatosScreen> createState() => _ImportarContatosScreenState();
}

enum _Estado { carregando, semPermissao, pronto, erro }

class ContatoParaImportar {
  ContatoParaImportar({required this.nome, required this.telefone, required this.digitos});
  final String nome;

  /// Formatado: "(48) 99912-3456".
  final String telefone;

  /// Só os dígitos com DDD: "48999123456" (chave pra achar duplicados).
  final String digitos;
}

class _ImportarContatosScreenState extends State<ImportarContatosScreen> {
  _Estado _estado = _Estado.carregando;
  String? _erro;
  List<ContatoParaImportar> _contatos = const [];
  Set<String> _jaCadastrados = const {};
  final Set<String> _marcados = {};
  final _busca = TextEditingController();
  String _filtro = '';
  bool _importando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _estado = _Estado.carregando;
      _erro = null;
    });
    try {
      final permitido = await FlutterContacts.requestPermission(readonly: true);
      if (!permitido) {
        if (mounted) setState(() => _estado = _Estado.semPermissao);
        return;
      }
      final repo = context.read<CustomersRepository>();
      final results = await Future.wait([
        FlutterContacts.getContacts(withProperties: true),
        repo.digitosDosTelefonesCadastrados(),
      ]);
      final contatos = results[0] as List<Contact>;
      final jaCadastrados = results[1] as Set<String>;

      final porNumero = <String, ContatoParaImportar>{};
      for (final c in contatos) {
        final nome = c.displayName.trim();
        if (nome.isEmpty) continue;
        final digitos = _melhorNumero(c.phones);
        if (digitos == null) continue;
        // Mesmo número em dois contatos da agenda: fica o primeiro.
        porNumero.putIfAbsent(
          digitos,
          () => ContatoParaImportar(nome: nome, telefone: formatarTelefoneBR(digitos), digitos: digitos),
        );
      }
      final lista = porNumero.values.toList()
        ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _contatos = lista;
        _jaCadastrados = jaCadastrados;
        _estado = _Estado.pronto;
      });
    } catch (e) {
      debugPrint('[ImportarContatos] $e');
      if (mounted) {
        setState(() {
          _estado = _Estado.erro;
          _erro = 'Não foi possível ler os contatos do celular.';
        });
      }
    }
  }

  /// Primeiro celular válido; se não houver celular, o primeiro número válido.
  static String? _melhorNumero(List<Phone> phones) {
    String? fixo;
    for (final p in phones) {
      final d = digitosTelefoneBR(p.normalizedNumber.isNotEmpty ? p.normalizedNumber : p.number);
      if (d == null) continue;
      if (d.length == 11) return d;
      fixo ??= d;
    }
    return fixo;
  }

  List<ContatoParaImportar> get _visiveis {
    if (_filtro.isEmpty) return _contatos;
    final q = _filtro.toLowerCase();
    final qDigitos = q.replaceAll(RegExp(r'\D'), '');
    return _contatos
        .where((c) => c.nome.toLowerCase().contains(q) || (qDigitos.isNotEmpty && c.digitos.contains(qDigitos)))
        .toList();
  }

  bool _disponivel(ContatoParaImportar c) => !_jaCadastrados.contains(c.digitos);

  void _alternarTodos(List<ContatoParaImportar> visiveis, bool marcar) {
    setState(() {
      for (final c in visiveis.where(_disponivel)) {
        marcar ? _marcados.add(c.digitos) : _marcados.remove(c.digitos);
      }
    });
  }

  Future<void> _importar() async {
    final escolhidos = _contatos.where((c) => _marcados.contains(c.digitos)).toList();
    if (escolhidos.isEmpty) return;
    setState(() => _importando = true);
    try {
      final n = await context.read<CustomersRepository>().importarContatos(
            [for (final c in escolhidos) (nome: c.nome, telefone: c.telefone)],
          );
      if (!mounted) return;
      Navigator.of(context).pop(n);
    } catch (e) {
      if (!mounted) return;
      setState(() => _importando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível importar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: CabecalhoDeTela(
              titulo: 'Importar contatos',
              area: AreaDoApp.prestador,
              aoVoltar: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(child: _corpo()),
          if (_estado == _Estado.pronto)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppMetrics.margemLateral, 8, AppMetrics.margemLateral, 10),
                child: BotaoComSeta(
                  rotulo: _marcados.isEmpty
                      ? 'Escolha os contatos'
                      : 'Importar ${_marcados.length} ${_marcados.length == 1 ? 'contato' : 'contatos'}',
                  icone: Icons.download_outlined,
                  comCaixa: false,
                  carregando: _importando,
                  aoTocar: _marcados.isEmpty ? null : _importar,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _corpo() {
    switch (_estado) {
      case _Estado.carregando:
        return const Center(child: CircularProgressIndicator());
      case _Estado.semPermissao:
        return _Aviso(
          icone: Icons.contacts_outlined,
          texto: 'Para importar, o PrestadorAki precisa ver os contatos do celular. '
              'Só o nome e o número dos contatos que você marcar são salvos nos seus clientes.',
          botao: 'Permitir acesso',
          aoTocar: () async {
            final ok = await FlutterContacts.requestPermission(readonly: true);
            if (ok) return _carregar();
            // Negado "para sempre": o sistema não mostra mais o pedido.
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Libere em Ajustes do celular → Apps → PrestadorAki → Permissões → Contatos.'),
            ));
          },
        );
      case _Estado.erro:
        return _Aviso(icone: Icons.error_outline, texto: _erro ?? 'Algo deu errado.', botao: 'Tentar de novo', aoTocar: _carregar);
      case _Estado.pronto:
        break;
    }

    if (_contatos.isEmpty) {
      return const _Aviso(
        icone: Icons.contacts_outlined,
        texto: 'Nenhum contato com número de celular brasileiro foi encontrado na agenda.',
      );
    }

    final visiveis = _visiveis;
    final disponiveisVisiveis = visiveis.where(_disponivel).toList();
    final todosMarcados =
        disponiveisVisiveis.isNotEmpty && disponiveisVisiveis.every((c) => _marcados.contains(c.digitos));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppMetrics.margemLateral, 0, AppMetrics.margemLateral, 8),
          child: TextField(
            controller: _busca,
            decoration: const InputDecoration(
              hintText: 'Buscar por nome ou número',
              suffixIcon: Icon(Icons.search, color: AppColors.muted),
            ),
            onChanged: (v) => setState(() => _filtro = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppMetrics.margemLateral - 12),
          child: Row(
            children: [
              Checkbox(
                value: todosMarcados,
                onChanged: disponiveisVisiveis.isEmpty ? null : (v) => _alternarTodos(visiveis, v ?? false),
              ),
              Expanded(
                child: Text(
                  _filtro.isEmpty ? 'Selecionar todos' : 'Selecionar os encontrados',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${_marcados.length} de ${_contatos.where(_disponivel).length}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visiveis.isEmpty
              ? const _Aviso(icone: Icons.search_off, texto: 'Nenhum contato encontrado.')
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: visiveis.length,
                  itemBuilder: (context, i) {
                    final c = visiveis[i];
                    final disponivel = _disponivel(c);
                    final marcado = _marcados.contains(c.digitos);
                    return CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppMetrics.margemLateral - 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: disponivel ? marcado : true,
                      onChanged: disponivel
                          ? (v) => setState(() => v == true ? _marcados.add(c.digitos) : _marcados.remove(c.digitos))
                          : null,
                      title: Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        disponivel ? c.telefone : '${c.telefone} · Já cadastrado',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.texto, this.botao, this.aoTocar});

  final IconData icone;
  final String texto;
  final String? botao;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.margemLateral),
      children: [
        const SizedBox(height: 60),
        Icon(icone, size: 40, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        if (botao != null) ...[
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: aoTocar, child: Text(botao!))),
        ],
      ],
    );
  }
}

/// "+55 (48) 9 9912-3456", "048 99912 3456", "0xx48999123456"... ->
/// "48999123456". Devolve null se não for um número brasileiro com DDD.
String? digitosTelefoneBR(String bruto) {
  var d = bruto.replaceAll(RegExp(r'\D'), '');
  if (bruto.trim().startsWith('+') && !d.startsWith('55')) return null; // estrangeiro
  if (d.startsWith('55') && (d.length == 12 || d.length == 13)) d = d.substring(2);
  // 0 + operadora (2 dígitos) + DDD + número: "0 15 48 999123456"
  if (d.startsWith('0') && (d.length == 13 || d.length == 14)) d = d.substring(3);
  if (d.startsWith('0') && (d.length == 11 || d.length == 12)) d = d.substring(1);
  if (d.length != 10 && d.length != 11) return null;
  if (d[0] == '0' || d[1] == '0') return null; // DDD válido não tem 0
  if (d.length == 11 && d[2] != '9') return null; // celular começa com 9
  return d;
}

/// "48999123456" -> "(48) 99912-3456"; "4834331234" -> "(48) 3433-1234".
String formatarTelefoneBR(String digitos) {
  final ddd = digitos.substring(0, 2);
  final resto = digitos.substring(2);
  final corte = resto.length - 4;
  return '($ddd) ${resto.substring(0, corte)}-${resto.substring(corte)}';
}
