import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/models/provider_rating.dart';
import '../marketplace/provider_directory_repository.dart';

/// Endereço pra onde o QR Code do card aponta.
///
/// É a página publicada no Firebase Hosting (ver `site/index.html`), e não
/// um link de loja direto, de propósito: um link só serve pra um sistema, e
/// quem escaneia pode estar em qualquer um dos dois. A página decide.
const String kLinkDoApp = 'https://prestadoraki.web.app';

/// Os cinco modelos de card.
///
/// POR QUE CINCO OCASIÕES, E NÃO DEZ APARÊNCIAS (decisão com o Franck,
/// 29/09): ele pediu "umas 10 opções". Dez miniaturas fazem o prestador não
/// escolher nenhuma — ou escolher sempre a primeira. E a maior parte delas
/// viraria variação cosmética (outra cor, texto em outro canto), o que não
/// deixa o feed dele variado, porque o que muda de um post pro outro é a
/// FOTO, não a moldura.
///
/// O que dá variedade de verdade é ter ocasiões diferentes, cada uma
/// puxando um dado diferente do app e respondendo uma pergunta diferente de
/// quem vê: ele faz bem? melhora mesmo? os outros gostaram? dá pra chamar
/// agora? dá pra confiar?
enum _Modelo { servico, antesDepois, avaliacao, agenda, numeros }

extension _ModeloInfo on _Modelo {
  String get titulo => switch (this) {
        _Modelo.servico => 'Serviço feito',
        _Modelo.antesDepois => 'Antes e depois',
        _Modelo.avaliacao => 'Avaliação',
        _Modelo.agenda => 'Tenho vaga',
        _Modelo.numeros => 'Meus números',
      };

  IconData get icone => switch (this) {
        _Modelo.servico => Icons.photo_camera_outlined,
        _Modelo.antesDepois => Icons.compare_arrows_rounded,
        _Modelo.avaliacao => Icons.format_quote_rounded,
        _Modelo.agenda => Icons.event_available_outlined,
        _Modelo.numeros => Icons.emoji_events_outlined,
      };

  /// O que falta pra este modelo poder ser usado, ou `null` se dá pra usar.
  String? indisponivel(int fotos, int avaliacoes) => switch (this) {
        _Modelo.servico => fotos < 1 ? 'Precisa de pelo menos 1 foto no seu perfil.' : null,
        _Modelo.antesDepois =>
          fotos < 2 ? 'Precisa de 2 fotos no seu perfil — uma do antes, uma do depois.' : null,
        _Modelo.avaliacao =>
          avaliacoes < 1 ? 'Você ainda não recebeu avaliação com comentário.' : null,
        _Modelo.agenda => null,
        _Modelo.numeros => null,
      };
}

/// "Divulgar meu trabalho" — monta uma imagem pronta pro prestador postar
/// no Instagram, no status do WhatsApp ou onde ele quiser.
///
/// POR QUE ISSO EXISTE (ideia do Franck, 28/09): quem tem audiência na
/// cidade é o prestador, não o app. O Denilson tem o Instagram dele e o
/// grupo do bairro — gente de Criciúma, que é exatamente quem procura
/// eletricista. Fazer ele postar algo que carrega o PrestadorAki alcança
/// mais gente, e muito mais barato, do que qualquer anúncio.
///
/// A FOTO É DELE, NÃO GERADA. A ideia original era a IA criar uma "arte do
/// trabalho dele". Não faz: a IA não conhece o trabalho dele, então
/// inventaria um serviço que ele não fez — e ele postaria isso como "feito
/// essa semana" pra clientes da própria cidade, que reconhecem. Aqui tudo
/// sai do que já está no app: as fotos que ele subiu, as avaliações que
/// recebeu, a nota que tem. É mais barato, sai instantâneo e é verdade.
///
/// A IMAGEM É DESENHADA PELO PRÓPRIO FLUTTER. O card é uma tela normal
/// dentro de um `RepaintBoundary`, capturada como PNG — custo zero por uso,
/// funciona offline, sem chamada de API nenhuma.
class CardDivulgacaoScreen extends StatefulWidget {
  const CardDivulgacaoScreen({super.key});

  @override
  State<CardDivulgacaoScreen> createState() => _CardDivulgacaoScreenState();
}

class _CardDivulgacaoScreenState extends State<CardDivulgacaoScreen> {
  final _cardKey = GlobalKey();
  final _servicoCtrl = TextEditingController();
  final _agendaCtrl = TextEditingController(text: 'Tenho vaga essa semana');

  ProviderListing? _perfil;
  List<ProviderRating> _avaliacoes = const [];
  bool _carregando = true;
  String? _erro;

  _Modelo _modelo = _Modelo.servico;
  int _foto = 0;
  int _fotoAntes = 1;
  int _avaliacao = 0;
  int _variacaoDaLegenda = 0;
  bool _compartilhando = false;

  List<String> get _fotos => _perfil?.fotos ?? const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _servicoCtrl.dispose();
    _agendaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final uid = context.read<AuthController>().providerId;
    if (uid == null) {
      setState(() {
        _carregando = false;
        _erro = 'Sua conta ainda não tem perfil de prestador.';
      });
      return;
    }
    try {
      final repo = context.read<ProviderDirectoryRepository>();
      final perfil = await repo.get(uid);
      // Só avaliações COM comentário: o card de depoimento é o comentário.
      // Uma avaliação de 5 estrelas sem texto vira um card vazio.
      final avaliacoes = (await repo.watchRatings(uid, limit: 20).first)
          .where((a) => (a.comment ?? '').trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _avaliacoes = avaliacoes;
        _carregando = false;
        _servicoCtrl.text = perfil?.category.label ?? '';
        _modelo = _primeiroModeloDisponivel(perfil?.fotos.length ?? 0, avaliacoes.length);
        _fotoAntes = (perfil?.fotos.length ?? 0) > 1 ? 1 : 0;
      });
      await _precarregarFotos(perfil);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar seu perfil.';
      });
    }
  }

  /// Abre já num modelo que a conta consegue usar. Um prestador sem foto
  /// nenhuma caía numa tela que só dizia "precisa de foto" — e o modelo de
  /// agenda, que funciona pra todo mundo, ficava escondido atrás disso.
  _Modelo _primeiroModeloDisponivel(int fotos, int avaliacoes) {
    for (final m in _Modelo.values) {
      if (m.indisponivel(fotos, avaliacoes) == null) return m;
    }
    return _Modelo.agenda;
  }

  /// Baixa as fotos ANTES de qualquer captura.
  ///
  /// `RepaintBoundary.toImage` fotografa o que está pintado naquele
  /// instante. Uma `Image.network` que ainda não terminou de baixar é um
  /// espaço vazio — e o card sairia com um buraco no lugar da foto, sem
  /// erro nenhum pra avisar.
  Future<void> _precarregarFotos(ProviderListing? perfil) async {
    if (perfil == null || !mounted) return;
    for (final url in perfil.fotos) {
      if (!mounted) return;
      try {
        await precacheImage(NetworkImage(url), context);
      } catch (_) {
        // Foto quebrada não impede as outras de funcionarem.
      }
    }
  }

  // ------------------------------------------------------------- legenda

  /// Legenda por modelo, com variações trocadas no botão.
  ///
  /// SEM IA NESTA VERSÃO, e não por preguiça: o serviço de IA que já existe
  /// (`ProviderBioAiService`) gera CARTA DE APRESENTAÇÃO — usar ele aqui
  /// devolveria uma bio no lugar de uma legenda. Fazer direito pede uma
  /// Cloud Function nova. Enquanto ela não existe, um texto montado aqui
  /// sai instantâneo, de graça e offline — e o campo é editável.
  String get _legenda {
    final perfil = _perfil;
    final cidade = perfil?.city ?? '';
    final categoria = perfil?.category.label ?? 'Serviços';
    final ondeAtende = perfil?.todasAsCidades.join(', ') ?? cidade;
    final servico = _servicoCtrl.text.trim();

    final textos = switch (_modelo) {
      _Modelo.servico => [
          '$servico — serviço concluído em $cidade.\nOrçamento sem compromisso pelo app.',
          'Mais um $servico entregue essa semana em $cidade. Trabalho com garantia e '
              'orçamento por escrito.\nChame pelo app pra pedir o seu.',
          '$categoria em $ondeAtende.\nPeça seu orçamento pelo PrestadorAki.',
        ],
      _Modelo.antesDepois => [
          'Antes e depois de $servico em $cidade.\nA diferença que um serviço bem feito faz.',
          'Esse era o estado antes. Do lado, como ficou.\n$categoria em $ondeAtende — '
              'orçamento sem compromisso.',
        ],
      _Modelo.avaliacao => [
          'Comentário de quem contratou. É por isso que eu faço questão de entregar '
              'bem feito.\nObrigado pela confiança!',
          'Chegou avaliação nova. Fico feliz demais quando o cliente volta pra dizer '
              'que valeu a pena.\n$categoria em $ondeAtende.',
        ],
      _Modelo.agenda => [
          '${_agendaCtrl.text.trim()} — $categoria em $ondeAtende.\n'
              'Chame pelo app e peça seu orçamento, sem compromisso.',
          '${_agendaCtrl.text.trim()}\nAtendo $ondeAtende. Orçamento por escrito, '
              'com tudo detalhado.',
        ],
      _Modelo.numeros => [
          '$categoria em $ondeAtende, com avaliação de quem já contratou.\n'
              'Peça seu orçamento pelo app.',
          'Os números são de clientes de verdade, avaliando pelo app.\n'
              'Chame pra pedir o seu orçamento.',
        ],
    };

    final tags = <String>{
      _hashtag(categoria),
      if (cidade.isNotEmpty) _hashtag(cidade),
      if (_modelo == _Modelo.servico || _modelo == _Modelo.antesDepois) _hashtag(servico),
      if (_modelo == _Modelo.antesDepois) '#antesedepois',
      '#orcamentosemcompromisso',
    }.where((t) => t.length > 3).join(' ');

    return '${textos[_variacaoDaLegenda % textos.length]}\n\n$tags';
  }

  /// "Elétrica Residencial" -> "#eletricaresidencial". Sem acento e sem
  /// espaço: a rede social quebra a hashtag no primeiro caractere estranho
  /// e ela não indexa nada.
  static String _hashtag(String texto) {
    const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const semAcento = 'aaaaaeeeeiiiiooooouuuuc';
    var r = texto.toLowerCase();
    for (var i = 0; i < comAcento.length; i++) {
      r = r.split(comAcento[i]).join(semAcento[i]);
    }
    return '#${r.replaceAll(RegExp(r'[^a-z0-9]'), '')}';
  }

  // --------------------------------------------------------- compartilhar

  Future<void> _compartilhar() async {
    if (_compartilhando) return;
    setState(() => _compartilhando = true);
    try {
      final png = await _capturar();
      if (png == null) throw Exception('captura vazia');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(png, mimeType: 'image/png')],
          text: _legenda,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível gerar a imagem. Tente de novo.')),
      );
    } finally {
      if (mounted) setState(() => _compartilhando = false);
    }
  }

  /// Fotografa o card e devolve o PNG.
  ///
  /// `pixelRatio` calculado pra sair com ~1080px de largura, que é o que o
  /// Instagram usa. Capturar no tamanho da tela produziria uma imagem de
  /// ~300px, que a rede social ampliaria e borraria.
  Future<Uint8List?> _capturar() async {
    final objeto = _cardKey.currentContext?.findRenderObject();
    if (objeto is! RenderRepaintBoundary) return null;
    final escala = (1080 / objeto.size.width).clamp(1.0, 4.0);
    final imagem = await objeto.toImage(pixelRatio: escala);
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<void> _copiarLegenda() async {
    await Clipboard.setData(ClipboardData(text: _legenda));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Legenda copiada.')),
    );
  }

  // ------------------------------------------------------------------ ui

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Divulgar meu trabalho')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                )
              : _conteudo(),
    );
  }

  Widget _conteudo() {
    final bloqueio = _modelo.indisponivel(_fotos.length, _avaliacoes.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text('O que você quer postar?',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final m in _Modelo.values)
                _ChipDeModelo(
                  modelo: m,
                  selecionado: _modelo == m,
                  // Modelo sem material fica visível mas apagado: some a
                  // opção e o prestador nunca descobre que ela existe —
                  // nem que basta subir mais uma foto pra liberar.
                  disponivel: m.indisponivel(_fotos.length, _avaliacoes.length) == null,
                  onTap: () => setState(() {
                    _modelo = m;
                    _variacaoDaLegenda = 0;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (bloqueio != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(bloqueio,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.ink, height: 1.4)),
                ),
              ],
            ),
          )
        else ...[
          ..._camposDoModelo(),
          const SizedBox(height: 20),
          const Text('Como vai ficar',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: RepaintBoundary(
                key: _cardKey,
                child: _Card(
                  modelo: _modelo,
                  perfil: _perfil,
                  fotoUrl: _urlDaFoto(_foto),
                  fotoAntesUrl: _urlDaFoto(_fotoAntes),
                  servico: _servicoCtrl.text.trim(),
                  frase: _agendaCtrl.text.trim(),
                  avaliacao: _avaliacoes.isEmpty
                      ? null
                      : _avaliacoes[_avaliacao % _avaliacoes.length],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Legenda',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _variacaoDaLegenda++),
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('Trocar'),
              ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.muted.withValues(alpha: 0.14)),
            ),
            child: Text(_legenda, style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
          const SizedBox(height: 8),
          // O Instagram ignora o texto que vem junto do compartilhamento —
          // ele só aceita a imagem. Sem este aviso e sem o botão de copiar,
          // a legenda some e a pessoa acha que o app não funcionou.
          const Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: AppColors.muted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'No Instagram a legenda não vai junto — copie e cole ao postar.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _compartilhando ? null : _compartilhar,
            icon: _compartilhando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.ios_share),
            label: Text(_compartilhando ? 'Gerando…' : 'Compartilhar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _copiarLegenda,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copiar legenda'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ],
    );
  }

  String? _urlDaFoto(int i) => (i >= 0 && i < _fotos.length) ? _fotos[i] : null;

  /// Cada modelo pede uma coisa diferente. Mostrar só o que aquele modelo
  /// usa evita a tela virar um formulário com campos que não fazem nada.
  List<Widget> _camposDoModelo() {
    switch (_modelo) {
      case _Modelo.servico:
        return [
          _tituloCampo('Escolha uma foto sua', 'São as fotos que já estão no seu perfil.'),
          _tiraDeFotos(_foto, (i) => setState(() => _foto = i)),
          const SizedBox(height: 16),
          _campoServico(),
        ];
      case _Modelo.antesDepois:
        return [
          _tituloCampo('A foto do ANTES', 'Como estava antes do serviço.'),
          _tiraDeFotos(_fotoAntes, (i) => setState(() => _fotoAntes = i)),
          const SizedBox(height: 14),
          _tituloCampo('A foto do DEPOIS', 'Como ficou.'),
          _tiraDeFotos(_foto, (i) => setState(() => _foto = i)),
          const SizedBox(height: 16),
          _campoServico(),
        ];
      case _Modelo.avaliacao:
        return [
          _tituloCampo('Qual avaliação?', 'Só aparecem as que têm comentário escrito.'),
          const SizedBox(height: 8),
          for (var i = 0; i < _avaliacoes.length; i++)
            _OpcaoDeAvaliacao(
              avaliacao: _avaliacoes[i],
              selecionada: _avaliacao == i,
              onTap: () => setState(() => _avaliacao = i),
            ),
        ];
      case _Modelo.agenda:
        return [
          _tituloCampo('O que você quer anunciar?', 'Uma frase curta, que caiba grande no card.'),
          const SizedBox(height: 8),
          TextField(
            controller: _agendaCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Ex.: Tenho duas vagas essa semana',
              border: OutlineInputBorder(),
            ),
          ),
        ];
      case _Modelo.numeros:
        return [
          _tituloCampo('Seus números', 'Saem direto do seu perfil — nada é digitado aqui.'),
          const SizedBox(height: 4),
        ];
    }
  }

  Widget _tituloCampo(String titulo, String subtitulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitulo, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _campoServico() {
    return TextField(
      controller: _servicoCtrl,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: 'Que serviço foi esse?',
        hintText: 'Ex.: Quadro de distribuição novo',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _tiraDeFotos(int selecionada, ValueChanged<int> onTap) {
    return SizedBox(
      height: 70,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _fotos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onTap(i),
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selecionada == i
                          ? AppColors.primary
                          : AppColors.muted.withValues(alpha: 0.25),
                      width: selecionada == i ? 2.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.network(_fotos[i], fit: BoxFit.cover),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- widgets

class _ChipDeModelo extends StatelessWidget {
  const _ChipDeModelo({
    required this.modelo,
    required this.selecionado,
    required this.disponivel,
    required this.onTap,
  });

  final _Modelo modelo;
  final bool selecionado;
  final bool disponivel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cor = selecionado ? AppColors.primary : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Opacity(
        opacity: disponivel ? 1 : 0.45,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 84,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: selecionado ? AppColors.primary.withValues(alpha: 0.10) : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selecionado ? AppColors.primary : AppColors.muted.withValues(alpha: 0.22),
                width: selecionado ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(modelo.icone, size: 22, color: cor),
                const SizedBox(height: 5),
                Text(
                  modelo.titulo,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.15,
                    fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
                    color: selecionado ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpcaoDeAvaliacao extends StatelessWidget {
  const _OpcaoDeAvaliacao({
    required this.avaliacao,
    required this.selecionada,
    required this.onTap,
  });

  final ProviderRating avaliacao;
  final bool selecionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionada ? AppColors.primary : AppColors.muted.withValues(alpha: 0.18),
              width: selecionada ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 5; i++)
                    Icon(
                      i < avaliacao.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 15,
                      color: const Color(0xFFFFC93C),
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      avaliacao.clientName ?? 'Cliente',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                avaliacao.comment ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O card em si — é ESTE widget que vira a imagem postada.
///
/// 4:5 porque é o formato que ocupa mais altura no feed do Instagram sem
/// ser cortado. A marca fica numa faixa pequena no rodapé em todos os
/// modelos: se o card parecer anúncio do PrestadorAki, o prestador não
/// posta, e card não postado divulga zero. O que é dele — a foto, o nome,
/// o elogio que recebeu — é o elemento grande.
class _Card extends StatelessWidget {
  const _Card({
    required this.modelo,
    required this.perfil,
    required this.fotoUrl,
    required this.fotoAntesUrl,
    required this.servico,
    required this.frase,
    required this.avaliacao,
  });

  final _Modelo modelo;
  final ProviderListing? perfil;
  final String? fotoUrl;
  final String? fotoAntesUrl;
  final String servico;
  final String frase;
  final ProviderRating? avaliacao;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _fundo(),
            Padding(padding: const EdgeInsets.all(16), child: _conteudo()),
          ],
        ),
      ),
    );
  }

  /// Fundo diferente por modelo — é o que faz dois posts seguidos não
  /// parecerem o mesmo post. Com foto, ela é o fundo; sem foto, um
  /// gradiente, e os dois modelos sem foto usam gradientes distintos de
  /// propósito.
  Widget _fundo() {
    const escuro = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3A2B27), AppColors.ink],
    );
    const marca = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primary, AppColors.primaryDark],
    );

    switch (modelo) {
      case _Modelo.servico:
        return Stack(fit: StackFit.expand, children: [_foto(fotoUrl), _veu()]);
      case _Modelo.antesDepois:
        return Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                Expanded(child: _metade(fotoAntesUrl, 'ANTES')),
                const SizedBox(width: 2),
                Expanded(child: _metade(fotoUrl, 'DEPOIS')),
              ],
            ),
            _veu(),
          ],
        );
      case _Modelo.avaliacao:
        return const DecoratedBox(decoration: BoxDecoration(gradient: escuro));
      case _Modelo.agenda:
        return const DecoratedBox(decoration: BoxDecoration(gradient: marca));
      case _Modelo.numeros:
        return const DecoratedBox(decoration: BoxDecoration(gradient: escuro));
    }
  }

  Widget _foto(String? url) => url == null
      ? const ColoredBox(color: AppColors.ink)
      : Image.network(url, fit: BoxFit.cover);

  Widget _metade(String? url, String rotulo) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _foto(url),
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              rotulo,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Véu escuro no rodapé: sem ele, uma foto de parede branca engole o
  /// texto branco e o card sai ilegível justamente pra quem tem foto clara.
  Widget _veu() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            stops: [0.0, 0.55, 1.0],
            colors: [Color(0xEE140C0A), Color(0x99140C0A), Color(0x00140C0A)],
          ),
        ),
      );

  Widget _conteudo() {
    final nome = perfil?.name ?? '';
    final categoria = perfil?.category.label ?? '';
    final local = perfil?.locationLabel ?? '';
    final nota = perfil?.ratingAverage ?? 0;
    final avaliacoes = perfil?.ratingCount ?? 0;
    final rodape = [
      _identidade(nome, categoria, local, nota, avaliacoes),
      const SizedBox(height: 12),
      _marca(),
    ];

    switch (modelo) {
      // COM FOTO: tudo no rodapé, sobre o véu. A foto é a estrela; o texto
      // é legenda dela.
      case _Modelo.servico:
      case _Modelo.antesDepois:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (servico.isNotEmpty) _frase(servico, 21),
            const SizedBox(height: 6),
            ...rodape,
          ],
        );

      // DEPOIMENTO: o comentário do cliente é o card. As aspas gigantes
      // dizem "isto é fala de outra pessoa" antes de qualquer leitura.
      case _Modelo.avaliacao:
        final a = avaliacao;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('"',
                    style: TextStyle(
                      color: AppColors.primary.withValues(alpha: 0.9),
                      fontSize: 64,
                      height: 0.9,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 2),
                Text(
                  a?.comment ?? '',
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      Icon(
                        i < (a?.stars ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 16,
                        color: const Color(0xFFFFC93C),
                      ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        a?.clientName ?? 'Cliente',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: rodape,
            ),
          ],
        );

      // SEM FOTO: a frase sobe pro topo e o resto desce pro pé. Deixar
      // tudo embaixo deixava metade do card como bloco vazio — parecia
      // defeito, não desenho.
      case _Modelo.agenda:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _frase(frase.isEmpty ? categoria : frase, 27),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: rodape,
            ),
          ],
        );

      // NÚMEROS: nada é digitado — tudo sai do perfil. Só entram os que
      // existem, pra não anunciar "0 avaliações".
      case _Modelo.numeros:
        final cidades = perfil?.todasAsCidades.length ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (avaliacoes > 0)
                  _numero(nota.toStringAsFixed(1).replaceAll('.', ','), 'de nota média'),
                if (avaliacoes > 0)
                  _numero('$avaliacoes', avaliacoes == 1 ? 'cliente avaliou' : 'clientes avaliaram'),
                if (cidades > 0)
                  _numero('$cidades', cidades == 1 ? 'cidade atendida' : 'cidades atendidas'),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: rodape,
            ),
          ],
        );
    }
  }

  Widget _numero(String valor, String rotulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            valor,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rotulo,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  /// A frase grande do card. Tamanho vem por parâmetro porque os modelos
  /// sem foto precisam dela maior — ali ela é o card inteiro, não legenda.
  Widget _frase(String texto, double tamanho) {
    return Text(
      texto,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: tamanho,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -0.4,
      ),
    );
  }

  /// Quem é o prestador: nome, categoria, cidade e a nota quando existe.
  Widget _identidade(String nome, String categoria, String local, double nota, int avaliacoes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          [nome, categoria, local].where((t) => t.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        // No card de depoimento as estrelas já aparecem lá em cima, com o
        // nome de quem avaliou — repetir aqui seria dizer a mesma coisa
        // duas vezes no mesmo quadro.
        if (avaliacoes > 0 && modelo != _Modelo.avaliacao && modelo != _Modelo.numeros) ...[
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFC93C), size: 15),
              const SizedBox(width: 3),
              Text(
                '${nota.toStringAsFixed(1).replaceAll('.', ',')} · $avaliacoes avaliações',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// A faixa do rodapé com o QR — a única parte do card que fala do app.
  Widget _marca() {
    return Container(
      padding: const EdgeInsets.only(top: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: QrImageView(
              data: kLinkDoApp,
              version: QrVersions.auto,
              size: 42,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Peça seu orçamento no PrestadorAki',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Aponte a câmera para o código',
                  style: TextStyle(color: Colors.white60, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
