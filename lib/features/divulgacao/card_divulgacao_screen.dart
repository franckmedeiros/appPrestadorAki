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
import '../marketplace/provider_directory_repository.dart';

/// Endereço pra onde o QR Code do card aponta.
///
/// É a página publicada no Firebase Hosting (ver `site/index.html`), e não
/// um link de loja direto, de propósito: um link só serve pra um sistema, e
/// quem escaneia pode estar em qualquer um dos dois. A página decide.
const String kLinkDoApp = 'https://prestadoraki.web.app';

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
/// essa semana" pra clientes da própria cidade, que reconhecem. Aqui o card
/// usa as fotos que ele já subiu no perfil. É mais barato, sai instantâneo
/// e, principalmente, é verdade.
///
/// A IMAGEM É DESENHADA PELO PRÓPRIO FLUTTER. O card é uma tela normal
/// dentro de um `RepaintBoundary`, capturada como PNG — custo zero por uso,
/// funciona offline, sem chamada de API nenhuma. Geração de imagem por IA
/// cobraria por card e demoraria segundos.
class CardDivulgacaoScreen extends StatefulWidget {
  const CardDivulgacaoScreen({super.key});

  @override
  State<CardDivulgacaoScreen> createState() => _CardDivulgacaoScreenState();
}

class _CardDivulgacaoScreenState extends State<CardDivulgacaoScreen> {
  final _cardKey = GlobalKey();
  final _servicoCtrl = TextEditingController();

  ProviderListing? _perfil;
  bool _carregando = true;
  String? _erro;

  /// Índice da foto escolhida, ou -1 pro card sem foto (só texto) — que é
  /// o que salva quem ainda não subiu foto nenhuma, e também serve pra
  /// anunciar disponibilidade em vez de um serviço específico.
  int _foto = -1;

  int _variacaoDaLegenda = 0;
  bool _compartilhando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _servicoCtrl.dispose();
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
      final perfil = await context.read<ProviderDirectoryRepository>().get(uid);
      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _carregando = false;
        _foto = (perfil?.fotos.isNotEmpty ?? false) ? 0 : -1;
        _servicoCtrl.text = perfil?.category.label ?? '';
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

  /// Três variações fixas, trocadas no botão.
  ///
  /// SEM IA NESTA PRIMEIRA VERSÃO, e não por preguiça: o serviço de IA que
  /// já existe (`ProviderBioAiService`) gera CARTA DE APRESENTAÇÃO, que é
  /// outro texto — usar ele aqui devolveria uma bio no lugar de uma
  /// legenda. Fazer direito pede uma Cloud Function nova. Enquanto ela não
  /// existe, um texto montado aqui sai instantâneo, de graça e offline — e
  /// o campo é editável de qualquer jeito.
  String get _legenda {
    final perfil = _perfil;
    final servico = _servicoCtrl.text.trim();
    final cidade = perfil?.city ?? '';
    final categoria = perfil?.category.label ?? 'Serviços';
    final ondeAtende = perfil?.todasAsCidades.join(', ') ?? cidade;

    final textos = <String>[
      '$servico — serviço concluído em $cidade.\n'
          'Orçamento sem compromisso pelo app.',
      'Mais um $servico entregue essa semana em $cidade. '
          'Trabalho com garantia e orçamento por escrito.\n'
          'Chame pelo app pra pedir o seu.',
      '$categoria em $ondeAtende.\n'
          'Peça seu orçamento pelo PrestadorAki — é rápido e sem compromisso.',
    ];

    final tags = <String>{
      _hashtag(categoria),
      if (cidade.isNotEmpty) _hashtag(cidade),
      _hashtag(servico),
      '#orcamentosemcompromisso',
    }.where((t) => t.length > 3).join(' ');

    return '${textos[_variacaoDaLegenda % textos.length]}\n\n$tags';
  }

  /// "Elétrica Residencial" -> "#eletricaresidencial". Sem acento, sem
  /// espaço — do contrário a rede social quebra a hashtag no primeiro
  /// caractere estranho e ela não indexa nada.
  static String _hashtag(String texto) {
    const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const semAcento = 'aaaaaeeeeiiiiooooouuuuc';
    var r = texto.toLowerCase();
    for (var i = 0; i < comAcento.length; i++) {
      r = r.split(comAcento[i]).join(semAcento[i]);
    }
    r = r.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '#$r';
  }

  // --------------------------------------------------------- compartilhar

  Future<void> _compartilhar() async {
    if (_compartilhando) return;
    setState(() => _compartilhando = true);
    try {
      final png = await _capturar();
      if (png == null) throw Exception('captura vazia');
      // Sem `fileNameOverrides`: o nome do arquivo compartilhado é
      // cosmético (nenhuma rede social mostra ele), e o parâmetro mudou de
      // nome entre versões do share_plus. Deixar o pacote nomear sozinho
      // tira uma incompatibilidade possível sem perder nada visível.
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
    final perfil = _perfil;
    final fotos = perfil?.fotos ?? const <String>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text(
          'Escolha uma foto sua',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          fotos.isEmpty
              ? 'Você ainda não tem fotos no perfil. Dá pra postar assim mesmo, '
                  'com o card de texto.'
              : 'São as fotos que já estão no seu perfil.',
          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _MiniFoto(
                selecionada: _foto == -1,
                onTap: () => setState(() => _foto = -1),
                child: const Center(
                  child: Icon(Icons.text_fields_rounded, color: AppColors.muted, size: 22),
                ),
              ),
              for (var i = 0; i < fotos.length; i++)
                _MiniFoto(
                  selecionada: _foto == i,
                  onTap: () => setState(() => _foto = i),
                  child: Image.network(fotos[i], fit: BoxFit.cover),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _servicoCtrl,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Que serviço foi esse?',
            hintText: 'Ex.: Quadro de distribuição novo',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Como vai ficar',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: RepaintBoundary(
              key: _cardKey,
              child: _Card(
                perfil: perfil,
                fotoUrl: (_foto >= 0 && _foto < fotos.length) ? fotos[_foto] : null,
                servico: _servicoCtrl.text.trim(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text('Legenda', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
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
        // ele só aceita a imagem. Por isso o botão de copiar existe e este
        // aviso também: sem os dois, a legenda simplesmente some e a pessoa
        // acha que o app não funcionou.
        Row(
          children: [
            const Icon(Icons.info_outline, size: 15, color: AppColors.muted),
            const SizedBox(width: 6),
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
    );
  }
}

class _MiniFoto extends StatelessWidget {
  const _MiniFoto({required this.selecionada, required this.onTap, required this.child});

  final bool selecionada;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionada ? AppColors.primary : AppColors.muted.withValues(alpha: 0.25),
              width: selecionada ? 2.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

/// O card em si — é ESTE widget que vira a imagem postada.
///
/// 4:5 porque é o formato que ocupa mais altura no feed do Instagram sem
/// ser cortado. A marca fica numa faixa pequena no rodapé de propósito: se
/// o card parecer anúncio do PrestadorAki, o prestador não posta, e card
/// não postado divulga zero. O nome dele é o elemento grande.
class _Card extends StatelessWidget {
  const _Card({required this.perfil, required this.fotoUrl, required this.servico});

  final ProviderListing? perfil;
  final String? fotoUrl;
  final String servico;

  @override
  Widget build(BuildContext context) {
    final nome = perfil?.name ?? '';
    final categoria = perfil?.category.label ?? '';
    final local = perfil?.locationLabel ?? '';
    final nota = perfil?.ratingAverage ?? 0;
    final avaliacoes = perfil?.ratingCount ?? 0;

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (fotoUrl != null)
              Image.network(fotoUrl!, fit: BoxFit.cover)
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                ),
              ),
            // O véu escuro embaixo existe pra o texto ficar legível em
            // QUALQUER foto — sem ele, uma foto de parede branca engole as
            // letras brancas e o card sai ilegível justamente pra quem tem
            // foto clara.
            if (fotoUrl != null)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: [0.0, 0.55, 1.0],
                    colors: [Color(0xEE140C0A), Color(0x99140C0A), Color(0x00140C0A)],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (servico.isNotEmpty)
                    Text(
                      servico,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.3,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    [nome, categoria, local].where((t) => t.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (avaliacoes > 0) ...[
                    const SizedBox(height: 5),
                    Row(
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
                  const SizedBox(height: 12),
                  Container(
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
