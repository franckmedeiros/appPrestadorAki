import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import 'models/budget.dart';

/// Dados do prestador que entram no PDF — separado de `AuthController`/
/// `Budget` de propósito: esta função não deveria depender de `context`
/// nem do Firestore, só de valores já resolvidos (chamador busca o perfil
/// antes, ver BudgetFormScreen._generatePdf).
class BudgetPdfProvider {
  BudgetPdfProvider({
    required this.name,
    this.logoUrl,
    this.pixKey,
    this.subtitle,
  });

  final String name;
  final String? logoUrl;
  final String? pixKey;

  /// Linha fina embaixo do nome no cabeçalho — "Eletricista · Criciúma/SC".
  /// Opcional: sem ela o cabeçalho só encolhe, não quebra. Quem tiver os
  /// dados à mão (categoria/cidade do `providerDirectory`) passa; quem não
  /// tiver, omite.
  final String? subtitle;
}

// ---------------------------------------------------------------------------
// Paleta
//
// Uma cor de destaque só, usada quatro vezes (palavra ORÇAMENTO, régua do
// cabeçalho, selo de aditivo, faixa do total) e o resto em cinzas. Era o
// que faltava: a versão anterior não tinha destaque nenhum, então nada na
// página tinha mais peso que o resto — e página sem hierarquia é o que a
// gente lê como "simples".
// ---------------------------------------------------------------------------
const _laranja = PdfColor.fromInt(0xFFE7502E);
const _ink = PdfColor.fromInt(0xFF111827); // títulos
const _corpo = PdfColor.fromInt(0xFF374151); // texto
const _muted = PdfColor.fromInt(0xFF6B7280); // rótulos, datas
const _fio = PdfColor.fromInt(0xFFE5E7EB); // filete
const _fioFraco = PdfColor.fromInt(0xFFF1F2F4); // separador entre itens
const _faixa = PdfColor.fromInt(0xFFF7F5F4); // fundo da faixa de pagamento
const _logoVazia = PdfColor.fromInt(0xFFDCD9D6);

/// Assinatura do app no rodapé de todas as páginas.
///
/// Este PDF é o documento que o PRESTADOR manda pro cliente dele — é dele
/// a autoria, não nossa. Por isso a marca entra em 7,5pt no rodapé e não
/// como banner: um orçamento que parece panfleto de outra empresa faz o
/// prestador parar de usar o PDF, e aí a divulgação vira zero. Discreto e
/// em todo orçamento vale mais que chamativo e evitado.
///
/// O ganho real aqui é que quem lê é um cliente que ainda não conhece o
/// app: é a única peça do produto que chega sozinha em quem não baixou.
/// Por isso o endereço do site entrou no lugar da frase de efeito que
/// estava aqui antes — quando não existia página nenhuma pra apontar, a
/// frase era o que dava; agora que existe, um endereço que a pessoa
/// consegue digitar vale mais que um slogan que ela não pode seguir.
const String kNomeDoApp = 'PrestadorAki';
const String kSiteDoApp = 'prestadoraki.web.app';

/// Quantos dias o orçamento vale, contados da data dele.
///
/// Não é campo do formulário (ainda): é o prazo padrão de mercado, posto
/// aqui num lugar só pra virar campo depois sem caçar número solto. Serve
/// ao prestador — sem validade escrita, o cliente reaparece em março
/// cobrando o preço de setembro.
const int kValidadePadraoEmDias = 15;

/// Gera o PDF do orçamento.
///
/// Layout revisado com o Franck (set/2026), partindo da crítica dele de
/// que o anterior era "bem simples". O que mudou, e por quê:
///
///  - Saíram as três caixas de borda cinza idênticas (dados do cliente,
///    totais, observações). Caixa igual pra tudo não organiza nada; agora
///    cada seção é um rótulo pequeno em caixa-alta espaçada e o espaço em
///    branco faz a separação, que é como proposta comercial séria se
///    parece.
///  - A tabela perdeu as bordas verticais. Grade fechada em toda célula é
///    o que faz um documento parecer planilha exportada.
///  - O total virou faixa laranja. Num orçamento é a informação que a
///    pessoa procura primeiro; antes era um número 16pt dentro de mais uma
///    caixa cinza, com o mesmo peso do subtotal.
///  - Entrou número do documento e validade da proposta — as duas coisas
///    que todo orçamento impresso tem e este não tinha.
///  - O cabeçalho da tabela agora repete em toda página (`repeat: true`).
///    Orçamento com aditivo passa de uma folha, e a segunda folha vinha
///    com colunas de números sem legenda.
Future<Uint8List> buildBudgetPdf(
  Budget budget,
  BudgetPdfProvider provider, {
  int validadeDias = kValidadePadraoEmDias,
}) async {
  pw.MemoryImage? logoImage;
  final logoUrl = provider.logoUrl;
  if (logoUrl != null && logoUrl.isNotEmpty) {
    try {
      final response = await http.get(Uri.parse(logoUrl));
      if (response.statusCode == 200) {
        logoImage = pw.MemoryImage(response.bodyBytes);
      }
    } catch (_) {
      // Link quebrado/lento/sem internet: o PDF sai sem a logo em vez de
      // travar a geração inteira por causa de uma imagem.
    }
  }

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 32),
      // `footer` do MultiPage, e não um widget no fim do `build`: assim ele
      // aparece no pé de TODAS as páginas, e o próprio pacote reserva o
      // espaço dele ao quebrar a página. Um orçamento com muitos itens
      // ocupa duas ou três folhas, e um rodapé que só sai na última é
      // justamente o que não seria visto.
      footer: _rodape,
      build: (context) => [
        _cabecalho(budget, provider, logoImage),
        pw.SizedBox(height: 12),
        pw.Container(height: 2, color: _laranja),
        pw.SizedBox(height: 16),
        _clienteECondicoes(budget, provider, validadeDias),
        pw.SizedBox(height: 18),
        _tabelaDeItens(budget),
        pw.SizedBox(height: 10),
        _totais(budget),
        if (budget.observations != null && budget.observations!.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          _rotulo('Observações'),
          pw.SizedBox(height: 4),
          pw.Text(budget.observations!,
              style: const pw.TextStyle(fontSize: 10, color: _corpo, lineSpacing: 2)),
        ],
        if (provider.pixKey != null && provider.pixKey!.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _faixaDePagamento(provider.pixKey!),
        ],
        pw.SizedBox(height: 36),
        _assinaturas(budget, provider),
      ],
    ),
  );

  return doc.save();
}

// ---------------------------------------------------------------------------
// Cabeçalho
// ---------------------------------------------------------------------------

pw.Widget _cabecalho(Budget budget, BudgetPdfProvider provider, pw.MemoryImage? logo) {
  final subtitle = provider.subtitle;
  final numero = _numeroDoDocumento(budget.id);
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _marcaDoPrestador(provider.name, logo),
            pw.SizedBox(width: 11),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    provider.name,
                    style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _ink),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    pw.SizedBox(height: 1),
                    pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: _muted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 16),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'ORÇAMENTO',
            style: pw.TextStyle(
              fontSize: 16.5,
              fontWeight: pw.FontWeight.bold,
              color: _laranja,
              letterSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 5),
          if (numero != null) ...[
            pw.RichText(
              textAlign: pw.TextAlign.right,
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 9, color: _muted),
                children: [
                  const pw.TextSpan(text: 'Nº '),
                  pw.TextSpan(
                    text: numero,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _corpo),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 1),
          ],
          pw.Text(
            formatDateLong(budget.date),
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
          // Pedido do Franck: "eu sempre preciso ver o orçamento original e
          // o aditivo". O selo desceu do título pra cá: antes ele trocava
          // a palavra "ORÇAMENTO" por "ORÇAMENTO — ADITIVO Nº 1", o que
          // encolhia o título e fazia o cabeçalho mudar de forma conforme
          // a revisão. Agora o título é sempre o mesmo e o aditivo é uma
          // informação a mais, do lado da data — que é onde ela pertence.
          if (budget.revisionNumber > 0) ...[
            pw.SizedBox(height: 4),
            _selo('Aditivo nº ${budget.revisionNumber}'),
          ],
        ],
      ),
    ],
  );
}

/// Logo do prestador, ou um círculo com as iniciais dele quando não tem.
///
/// O espaço reservado existe nos dois casos de propósito: sem ele, o
/// orçamento de quem não subiu logo sai com o nome colado na margem e
/// parece outro documento, não o mesmo com um pedaço faltando.
pw.Widget _marcaDoPrestador(String nome, pw.MemoryImage? logo) {
  if (logo != null) {
    return pw.Container(
      width: 40,
      height: 40,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        image: pw.DecorationImage(image: logo, fit: pw.BoxFit.cover),
      ),
    );
  }
  return pw.Container(
    width: 40,
    height: 40,
    alignment: pw.Alignment.center,
    decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle, color: _logoVazia),
    child: pw.Text(
      _iniciais(nome),
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromInt(0xFF8A8480),
      ),
    ),
  );
}

String _iniciais(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) {
    return partes.first.substring(0, 1).toUpperCase();
  }
  return (partes.first.substring(0, 1) + partes.last.substring(0, 1)).toUpperCase();
}

/// Número do documento: os 6 últimos caracteres do id do orçamento, em
/// maiúsculas.
///
/// Não é uma sequência (0001, 0002...) porque não existe contador em
/// lugar nenhum, e inventar um exigiria uma transação por orçamento só
/// pra ter um número bonito. O que importa é ser IMPRESSO e RASTREÁVEL:
/// o cliente liga citando "7F3A9C" e o prestador acha o orçamento. Um id
/// do Firestore inteiro (20 caracteres) ninguém lê no telefone.
/// `null` num orçamento que ainda não foi salvo (`_buildBudgetFromForm`
/// devolve id vazio nesse caso) — aí a linha inteira sai do cabeçalho, em
/// vez de imprimir um traço que parece campo com defeito.
String? _numeroDoDocumento(String id) {
  final limpo = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (limpo.isEmpty) return null;
  final trecho = limpo.length <= 6 ? limpo : limpo.substring(limpo.length - 6);
  return trecho.toUpperCase();
}

// ---------------------------------------------------------------------------
// Cliente + condições
// ---------------------------------------------------------------------------

pw.Widget _clienteECondicoes(Budget budget, BudgetPdfProvider provider, int validadeDias) {
  final validoAte = DateTime(
    budget.date.year,
    budget.date.month,
    budget.date.day + validadeDias,
  );
  final temPix = provider.pixKey != null && provider.pixKey!.isNotEmpty;

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _rotulo('Cliente'),
            pw.SizedBox(height: 4),
            pw.Text(
              budget.customerName,
              style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: _ink),
            ),
            if (budget.addressText != null && budget.addressText!.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(budget.addressText!,
                  style: const pw.TextStyle(fontSize: 10, color: _corpo, lineSpacing: 1.5)),
            ],
          ],
        ),
      ),
      pw.SizedBox(width: 24),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _rotulo('Condições'),
            pw.SizedBox(height: 4),
            _condicao('Validade da proposta:', _dataCurta(validoAte), destaque: true),
            if (temPix) ...[
              pw.SizedBox(height: 2),
              _condicao('Forma de pagamento:', 'Pix'),
            ],
          ],
        ),
      ),
    ],
  );
}

pw.Widget _condicao(String label, String valor, {bool destaque = false}) {
  return pw.RichText(
    text: pw.TextSpan(
      style: const pw.TextStyle(fontSize: 10, color: _muted),
      children: [
        pw.TextSpan(text: '$label '),
        pw.TextSpan(
          text: valor,
          style: pw.TextStyle(
            color: destaque ? _ink : _corpo,
            fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Tabela de itens
// ---------------------------------------------------------------------------

pw.Widget _tabelaDeItens(Budget budget) {
  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(3.2),
      1: pw.FixedColumnWidth(62),
      2: pw.FixedColumnWidth(78),
      3: pw.FixedColumnWidth(78),
    },
    children: [
      pw.TableRow(
        // Repete o cabeçalho em cada folha: um orçamento com aditivos
        // passa de uma página, e a segunda vinha só com colunas de
        // números, sem dizer qual era qual.
        repeat: true,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.2)),
        ),
        children: [
          _th('Descrição'),
          _th('Qtd', align: pw.TextAlign.center),
          _th('Valor unit.', align: pw.TextAlign.right),
          _th('Total', align: pw.TextAlign.right),
        ],
      ),
      for (final item in budget.items)
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _fioFraco, width: 0.8)),
          ),
          children: [
            _tdDescricao(item),
            _td(item.quantityLabel, align: pw.TextAlign.center),
            _td(formatCentsBRL(item.unitPriceCents), align: pw.TextAlign.right),
            _td(formatCentsBRL(item.totalCents), align: pw.TextAlign.right),
          ],
        ),
    ],
  );
}

pw.Widget _th(String texto, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(right: 8, bottom: 6),
    child: pw.Text(
      texto.toUpperCase(),
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 7.5,
        fontWeight: pw.FontWeight.bold,
        color: _muted,
        letterSpacing: 1.1,
      ),
    ),
  );
}

pw.Widget _td(String texto, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 7, bottom: 7, right: 8),
    child: pw.Text(texto,
        textAlign: align, style: const pw.TextStyle(fontSize: 10, color: _corpo)),
  );
}

/// Célula de "Descrição" — igual a `_td`, mas com o selo "Aditivo nº N"
/// logo abaixo quando o item foi acrescentado por um aditivo (ver
/// `BudgetItem.aditivoNumber`) — pedido do Franck: "eu sempre preciso ver
/// o orçamento original e o aditivo... seja como um item a mais no
/// orçamento, marcando como aditivo". Sem selo nenhum pro item original.
pw.Widget _tdDescricao(BudgetItem item) {
  final aditivoNumber = item.aditivoNumber;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 7, bottom: 7, right: 14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(item.description,
            style: const pw.TextStyle(fontSize: 10, color: _corpo, lineSpacing: 1.5)),
        if (aditivoNumber != null) ...[
          pw.SizedBox(height: 3),
          _selo('Aditivo nº $aditivoNumber'),
        ],
      ],
    ),
  );
}

pw.Widget _selo(String texto) {
  return pw.Text(
    texto.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 7,
      fontWeight: pw.FontWeight.bold,
      color: _laranja,
      letterSpacing: 1,
    ),
  );
}

// ---------------------------------------------------------------------------
// Totais
// ---------------------------------------------------------------------------

pw.Widget _totais(Budget budget) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Container(
        width: 200,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _linhaDeTotal('Subtotal', formatCentsBRL(budget.subtotalCents)),
            if (budget.discountCents > 0) ...[
              pw.SizedBox(height: 3),
              _linhaDeTotal('Desconto', '− ${formatCentsBRL(budget.discountCents)}'),
            ],
            pw.SizedBox(height: 7),
            pw.Container(
              color: _laranja,
              padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 1.6,
                    ),
                  ),
                  pw.Text(
                    formatCentsBRL(budget.totalCents),
                    style: pw.TextStyle(
                      fontSize: 14.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _linhaDeTotal(String label, String valor) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.Text(valor, style: const pw.TextStyle(fontSize: 10, color: _corpo)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Pagamento e assinaturas
// ---------------------------------------------------------------------------

pw.Widget _faixaDePagamento(String pixKey) {
  return pw.Container(
    width: double.infinity,
    color: _faixa,
    padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        _rotulo('Pagamento'),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Text(
            'Pix: $pixKey',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _assinaturas(Budget budget, BudgetPdfProvider provider) {
  return pw.Row(
    children: [
      pw.Expanded(child: _campoDeAssinatura(provider.name, 'Prestador')),
      pw.SizedBox(width: 36),
      pw.Expanded(child: _campoDeAssinatura(budget.customerName, 'Cliente')),
    ],
  );
}

pw.Widget _campoDeAssinatura(String nome, String papel) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(height: 0.9, color: PdfColor.fromInt(0xFF9CA3AF)),
      pw.SizedBox(height: 4),
      pw.Text(nome, style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
      pw.SizedBox(height: 1),
      pw.Text(
        papel.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: _muted,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Peças reaproveitadas
// ---------------------------------------------------------------------------

/// Rótulo de seção: 7,5pt, caixa-alta, espaçado, cinza.
///
/// Substitui os títulos 13pt em negrito dentro de caixas com borda. É o
/// recurso que nota fiscal e proposta de arquiteto usam pra separar
/// seções sem desenhar nada — e libera a página inteira do quadriculado
/// que ela tinha.
pw.Widget _rotulo(String texto) {
  return pw.Text(
    texto.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
      color: _muted,
      letterSpacing: 1.3,
    ),
  );
}

String _dataCurta(DateTime d) {
  final dia = d.day.toString().padLeft(2, '0');
  final mes = d.month.toString().padLeft(2, '0');
  return '$dia/$mes/${d.year}';
}

/// Rodapé de todas as páginas: assinatura do app à esquerda, número da
/// página à direita.
///
/// A numeração entra junto porque o rodapé é o lugar dela e o custo é uma
/// linha — num orçamento de duas ou três folhas soltas, saber que falta
/// página é o tipo de coisa que só se percebe quando falta.
pw.Widget _rodape(pw.Context context) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Divider(color: _fio, thickness: 0.8),
      pw.SizedBox(height: 2),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                children: [
                  const pw.TextSpan(text: 'Orçamento criado no '),
                  pw.TextSpan(
                    text: kNomeDoApp,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _laranja),
                  ),
                  const pw.TextSpan(text: ' — $kSiteDoApp'),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            '${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    ],
  );
}
