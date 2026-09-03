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
  BudgetPdfProvider({required this.name, this.logoUrl, this.pixKey});

  final String name;
  final String? logoUrl;
  final String? pixKey;
}

const _borderColor = PdfColor.fromInt(0xFFE0E0E0);
const _mutedColor = PdfColor.fromInt(0xFF6B7280);
const _headerBgColor = PdfColor.fromInt(0xFFF5F5F5);

/// Gera o PDF do orçamento no layout combinado com o Franck (ver
/// orcamento_Franck_Medeiros_..._.pdf, exemplo mandado por ele): logo +
/// nome da empresa à esquerda, "ORÇAMENTO" + data à direita, caixa de
/// dados do cliente, tabela de itens, caixa de subtotal/desconto/total,
/// observações e assinaturas.
Future<Uint8List> buildBudgetPdf(Budget budget, BudgetPdfProvider provider) async {
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
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null) ...[
                  pw.Container(
                    width: 56,
                    height: 56,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      image: pw.DecorationImage(image: logoImage, fit: pw.BoxFit.cover),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Text(
                  provider.name,
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  // Pedido do Franck: "quando o orçamento sofrer revisão,
                  // realizar a opção de aditivo" — o PDF de um orçamento
                  // já revisado (ver BudgetsRepository.registerAditivo)
                  // se identifica como tal, com a data abaixo já sendo a
                  // do aditivo (budget.date é sempre a mais recente).
                  budget.revisionNumber > 0 ? 'ORÇAMENTO — ADITIVO Nº ${budget.revisionNumber}' : 'ORÇAMENTO',
                  style: pw.TextStyle(fontSize: budget.revisionNumber > 0 ? 15 : 20, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(formatDateLong(budget.date), style: const pw.TextStyle(color: _mutedColor)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Divider(color: _borderColor, thickness: 1),
        pw.SizedBox(height: 18),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _borderColor),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Dados do Cliente', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Row(children: [
                pw.SizedBox(
                  width: 72,
                  child: pw.Text('Nome:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
                pw.Expanded(child: pw.Text(budget.customerName)),
              ]),
              if (budget.addressText != null && budget.addressText!.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Row(children: [
                  pw.SizedBox(
                    width: 72,
                    child: pw.Text('Endereço:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Expanded(child: pw.Text(budget.addressText!)),
                ]),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _headerBgColor),
              children: [
                _cell('Descrição', bold: true),
                _cell('Qtd', bold: true, align: pw.TextAlign.center),
                _cell('Preço unitário', bold: true, align: pw.TextAlign.right),
                _cell('Preço total', bold: true, align: pw.TextAlign.right),
              ],
            ),
            for (final item in budget.items)
              pw.TableRow(children: [
                _cell(item.description),
                _cell(item.quantityLabel, align: pw.TextAlign.center),
                _cell(formatCentsBRL(item.unitPriceCents), align: pw.TextAlign.right),
                _cell(formatCentsBRL(item.totalCents), align: pw.TextAlign.right),
              ]),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 220,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _totalsRow('Subtotal:', formatCentsBRL(budget.subtotalCents)),
                if (budget.discountCents > 0) ...[
                  pw.SizedBox(height: 4),
                  _totalsRow('Desconto:', formatCentsBRL(budget.discountCents)),
                ],
                pw.SizedBox(height: 6),
                pw.Divider(color: _borderColor),
                pw.SizedBox(height: 2),
                _totalsRow('Total:', formatCentsBRL(budget.totalCents), bold: true, fontSize: 16),
              ],
            ),
          ),
        ),
        if (budget.observations != null && budget.observations!.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Observações', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text(budget.observations!),
              ],
            ),
          ),
        ],
        if (provider.pixKey != null && provider.pixKey!.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            'Pix para pagamento: ${provider.pixKey}',
            style: const pw.TextStyle(fontSize: 10.5, color: _mutedColor),
          ),
        ],
        pw.SizedBox(height: 48),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _signatureBlock(provider.name, 'Empresa'),
            _signatureBlock(budget.customerName, 'Cliente'),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(fontSize: 10.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
    ),
  );
}

pw.Widget _totalsRow(String label, String value, {bool bold = false, double fontSize = 12}) {
  final style = pw.TextStyle(fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: style),
      pw.Text(value, style: style),
    ],
  );
}

pw.Widget _signatureBlock(String name, String role) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: 180, child: pw.Divider(thickness: 1, color: PdfColors.black)),
      pw.SizedBox(height: 4),
      pw.Text(name, style: const pw.TextStyle(fontSize: 10.5)),
      pw.Text(role, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
    ],
  );
}
