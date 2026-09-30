import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../core/valor_por_extenso.dart';
import '../budgets/budget_pdf.dart' show BudgetPdfProvider, kNomeDoApp, kSiteDoApp;
import '../marketplace/models/service_category.dart';
import 'models/job.dart';

/// Recibo de pagamento de um serviço concluído.
///
/// Por que existe: o ciclo terminava no ar. O serviço concluía, o Pix era
/// pago, e não sobrava documento nenhum pra nenhum dos dois lados — o
/// cliente sem comprovante do que pagou, o prestador sem o papel que todo
/// cliente de obra acaba pedindo.
///
/// Reaproveita de propósito a mesma linguagem visual do orçamento (ver
/// budget_pdf.dart): mesma paleta, mesmo cabeçalho, mesmo rodapé. Os dois
/// documentos chegam no mesmo cliente com dias de diferença; se parecerem
/// de empresas diferentes, o segundo perde a autoridade do primeiro.
///
/// A diferença de forma é proposital: o orçamento é uma tabela (o que vai
/// ser feito, item a item), o recibo é uma DECLARAÇÃO — um parágrafo em
/// primeira pessoa, com o valor por extenso e a quitação. É assim que
/// recibo é escrito no Brasil, e fugir disso faria o documento parecer
/// uma segunda via da nota.
const _laranja = PdfColor.fromInt(0xFFE7502E);
const _ink = PdfColor.fromInt(0xFF111827);
const _corpo = PdfColor.fromInt(0xFF374151);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _fio = PdfColor.fromInt(0xFFE5E7EB);
const _faixa = PdfColor.fromInt(0xFFF7F5F4);
const _logoVazia = PdfColor.fromInt(0xFFDCD9D6);

/// Gera o recibo a partir do serviço concluído.
///
/// [numeroDoRecibo] tem sequência PRÓPRIA, separada da do orçamento (ver
/// `JobsRepository.garantirNumeroDeRecibo`): são dois blocos de documento
/// diferentes, e um prestador que emite 40 orçamentos e 12 recibos no ano
/// não espera que o recibo dele comece no 41.
///
/// [numeroDoOrcamento] é opcional e amarra os dois documentos ("conforme
/// orçamento nº 0042"). Omitido, o recibo se vira sozinho descrevendo o
/// serviço.
Future<Uint8List> buildReciboPdf(
  Job job,
  BudgetPdfProvider provider, {
  required int numeroDoRecibo,
  int? numeroDoOrcamento,
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
      // Mesma escolha do orçamento: sai sem a logo em vez de não sair.
    }
  }

  // A data do recibo é a do PAGAMENTO, nunca a de hoje. Reimprimir um
  // recibo em janeiro não pode transformá-lo num recibo de janeiro.
  final data = job.paidAt ?? job.completedAt ?? DateTime.now();
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 32),
      footer: _rodape,
      build: (context) => [
        _cabecalho(provider, logoImage, numeroDoRecibo),
        pw.SizedBox(height: 12),
        pw.Container(height: 2, color: _laranja),
        pw.SizedBox(height: 22),
        _faixaDoValor(job.totalCents),
        pw.SizedBox(height: 22),
        _declaracao(job, provider, numeroDoOrcamento),
        pw.SizedBox(height: 18),
        _quitacao(),
        pw.SizedBox(height: 26),
        pw.Text(_localEData(provider.cidade, data),
            style: const pw.TextStyle(fontSize: 10, color: _corpo)),
        pw.SizedBox(height: 44),
        _assinatura(provider.name),
      ],
    ),
  );

  return doc.save();
}

// ---------------------------------------------------------------------------

pw.Widget _cabecalho(BudgetPdfProvider provider, pw.MemoryImage? logo, int numero) {
  final subtitle = provider.subtitle;
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
            'RECIBO',
            style: pw.TextStyle(
              fontSize: 16.5,
              fontWeight: pw.FontWeight.bold,
              color: _laranja,
              letterSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.RichText(
            textAlign: pw.TextAlign.right,
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 9, color: _muted),
              children: [
                const pw.TextSpan(text: 'Nº '),
                pw.TextSpan(
                  text: numero.toString().padLeft(4, '0'),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _corpo),
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

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
  if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
  return (partes.first.substring(0, 1) + partes.last.substring(0, 1)).toUpperCase();
}

/// O valor, em faixa laranja, sozinho e grande.
///
/// Num recibo o valor é O conteúdo — quem recebe o papel está conferindo
/// um número, não lendo um texto. Mesmo recurso da faixa de total do
/// orçamento, de novo pra os dois documentos se reconhecerem.
pw.Widget _faixaDoValor(int cents) {
  return pw.Container(
    width: double.infinity,
    color: _laranja,
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'VALOR RECEBIDO',
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            letterSpacing: 1.6,
          ),
        ),
        pw.Text(
          formatCentsBRL(cents),
          style: pw.TextStyle(
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
      ],
    ),
  );
}

/// O parágrafo do recibo, em primeira pessoa.
///
/// O valor aparece duas vezes de propósito — em algarismo e por extenso.
/// Não é redundância: é o que impede que o algarismo seja alterado depois
/// que o papel sai da mão de quem assinou.
pw.Widget _declaracao(Job job, BudgetPdfProvider provider, int? numeroDoOrcamento) {
  final referencias = <String>[];
  // `job.category` é o id do catálogo ('ar_condicionado'), não o rótulo.
  // Num parágrafo corrido isso sairia "serviços de ar_condicionado
  // prestados" — passa pelo catálogo e desce pra minúscula, porque o
  // rótulo vem capitalizado pra card e aqui ele está no meio da frase.
  final categoriaId = (job.category ?? '').trim();
  final categoria =
      categoriaId.isEmpty ? '' : serviceCategoryFromWire(categoriaId).label.toLowerCase();
  referencias.add(categoria.isEmpty
      ? 'referente aos serviços prestados'
      : 'referente aos serviços de $categoria prestados');
  final endereco = (job.addressText ?? '').trim();
  if (endereco.isNotEmpty) referencias.add('em $endereco');
  if (numeroDoOrcamento != null) {
    referencias.add('conforme orçamento nº ${numeroDoOrcamento.toString().padLeft(4, '0')}');
  }

  return pw.RichText(
    text: pw.TextSpan(
      style: const pw.TextStyle(fontSize: 11, color: _corpo, lineSpacing: 4),
      children: [
        const pw.TextSpan(text: 'Recebi de '),
        pw.TextSpan(
          text: job.customerName,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink),
        ),
        const pw.TextSpan(text: ' a importância de '),
        pw.TextSpan(
          text: '${formatCentsBRL(job.totalCents)} (${valorPorExtenso(job.totalCents)})',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink),
        ),
        pw.TextSpan(text: ', ${referencias.join(', ')}.'),
      ],
    ),
  );
}

pw.Widget _quitacao() {
  return pw.Container(
    width: double.infinity,
    color: _faixa,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: pw.Text(
      'Para maior clareza, firmo o presente recibo, dando plena e geral '
      'quitação do valor acima, nada mais tendo a reclamar.',
      style: const pw.TextStyle(fontSize: 9.5, color: _corpo, lineSpacing: 2),
    ),
  );
}

/// "Criciúma/SC, 30 de setembro de 2026." — e só a data quando a cidade
/// do prestador não está cadastrada. O par local+data é o fecho padrão de
/// um recibo; sem cidade, a data sozinha ainda fecha.
String _localEData(String? cidade, DateTime data) {
  final local = (cidade ?? '').trim();
  final quando = formatDateLong(data);
  return local.isEmpty ? '$quando.' : '$local, $quando.';
}

pw.Widget _assinatura(String nome) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(width: 240, height: 0.9, color: PdfColor.fromInt(0xFF9CA3AF)),
      pw.SizedBox(height: 4),
      pw.Text(nome, style: const pw.TextStyle(fontSize: 10, color: _ink)),
      pw.SizedBox(height: 1),
      pw.Text(
        'QUEM RECEBEU',
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
                  const pw.TextSpan(text: 'Recibo emitido no '),
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
