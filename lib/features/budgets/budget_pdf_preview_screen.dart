import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/app_theme.dart';

/// Mostra o PDF do orçamento na tela, com zoom e rolagem, e um botão de
/// compartilhar.
///
/// Pedido do Franck: "precisa ter opção de visualizar o PDF a qualquer
/// momento". Até aqui o único caminho pro PDF era compartilhar — ou seja,
/// pra CONFERIR o próprio documento antes de mandar, o prestador tinha
/// que mandar pra alguém (ou pra si mesmo) e abrir de fora do app.
///
/// Imprimir ficou de fora de propósito. Existiu por um dia e saiu no
/// mesmo dia: a folha de impressão do Android, ao ser cancelada, devolve
/// o app numa tela da qual ele precisava sair na mão ("se cancelo tenho
/// que sair da tela"). Quem quiser papel imprime pelo compartilhar, que
/// entrega o arquivo pro app de impressão do aparelho sem sequestrar a
/// navegação.
class BudgetPdfPreviewScreen extends StatelessWidget {
  const BudgetPdfPreviewScreen({
    super.key,
    required this.bytes,
    required this.fileName,
    this.title = 'Orçamento',
  });

  final Uint8List bytes;
  final String fileName;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        // Os bytes já vêm prontos de quem abriu a tela: gerar de novo aqui
        // significaria ler o perfil e baixar a logo outra vez, e correr o
        // risco de mostrar um documento diferente do que foi
        // compartilhado.
        build: (_) async => bytes,
        pdfFileName: fileName,
        // Impressão desligada: ver o comentário da classe.
        allowPrinting: false,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        // A barra do próprio PdfPreview vira só o compartilhar; sem isso
        // ela abre com controles de formato de papel que não fazem
        // sentido num orçamento que é sempre A4.
        useActions: true,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white),
        previewPageMargin: const EdgeInsets.all(12),
        scrollViewDecoration: const BoxDecoration(color: AppColors.background),
      ),
    );
  }
}
