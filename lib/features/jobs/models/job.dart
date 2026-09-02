import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color;

import '../../../core/app_theme.dart';

/// Status do módulo "Serviços" (Kanban — ver JobsKanbanScreen), pedido do
/// Franck pra substituir o antigo atalho "Pedidos" do Dashboard: quando o
/// prestador dá o aceite final de um orçamento (ver
/// `BudgetsRepository.acceptFinal`), nasce um `Job` aqui com status
/// `novo`, e o prestador vai avançando ele pelas raias manualmente
/// (tocando no card + escolhendo a próxima etapa — sem arrastar e
/// soltar).
///
///   novo                 -> serviço acabou de ser confirmado/agendado.
///   emAndamento           -> prestador começou a executar.
///   interrompido          -> pausado (ex.: falta material, cliente
///                            remarcou) — pode voltar pra `emAndamento`.
///   aguardandoPagamento   -> execução terminou, falta o cliente pagar
///                            (é aqui que o QR Code Pix é gerado/mostrado
///                            — ver `PixPayload`).
///   concluido             -> pagamento confirmado e serviço encerrado —
///                            dispara notificação pro cliente pedindo
///                            avaliação (ver functions/src/jobs.ts).
enum JobStatus { novo, emAndamento, interrompido, aguardandoPagamento, concluido }

extension JobStatusWire on JobStatus {
  String get wireValue => switch (this) {
        JobStatus.novo => 'novo',
        JobStatus.emAndamento => 'em_andamento',
        JobStatus.interrompido => 'interrompido',
        JobStatus.aguardandoPagamento => 'aguardando_pagamento',
        JobStatus.concluido => 'concluido',
      };

  /// Mesma paleta de cor usada no Kanban (Serviços) pra cada etapa —
  /// agora compartilhada com o selo de status do Dashboard
  /// (`JobStatusChip`/"Compromissos de hoje"), em vez de duplicar este
  /// switch em cada tela que precisa colorir por status.
  Color get color => switch (this) {
        JobStatus.novo => AppColors.primary,
        JobStatus.emAndamento => AppColors.warning,
        JobStatus.interrompido => AppColors.danger,
        JobStatus.aguardandoPagamento => AppColors.warning,
        JobStatus.concluido => AppColors.success,
      };

  String get label => switch (this) {
        JobStatus.novo => 'Novo',
        JobStatus.emAndamento => 'Em andamento',
        JobStatus.interrompido => 'Interrompido',
        JobStatus.aguardandoPagamento => 'Aguardando pagamento',
        JobStatus.concluido => 'Concluído',
      };
}

JobStatus jobStatusFromWire(String? value) {
  for (final status in JobStatus.values) {
    if (status.wireValue == value) return status;
  }
  return JobStatus.novo;
}

/// Um serviço em execução, criado automaticamente no aceite final de um
/// orçamento vindo de um pedido de cliente pelo marketplace (ver
/// `Budget.isFromClientRequest`/`BudgetsRepository.acceptFinal`) — por
/// isso todo `Job` tem `budgetId`/`clientUid` (pra saber quem avisar a
/// cada mudança de etapa — ver functions/src/jobs.ts) e um "retrato" dos
/// dados do orçamento no momento do aceite (`customerName`,
/// `addressText`, `totalCents`...), mesma convenção de `Budget` (um job
/// antigo não deve mudar se o cadastro for editado depois).
class Job {
  Job({
    required this.id,
    required this.status,
    required this.customerName,
    required this.totalCents,
    this.providerUid,
    this.budgetId,
    this.appointmentId,
    this.clientUid,
    this.providerDirectoryId,
    this.providerName,
    this.category,
    this.addressText,
    this.createdAt,
    this.updatedAt,
    this.paidAt,
    this.completedAt,
  });

  factory Job.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Job(
      id: doc.id,
      status: jobStatusFromWire(data['status'] as String?),
      customerName: data['customerName'] as String? ?? '',
      totalCents: (data['totalCents'] as num?)?.toInt() ?? 0,
      providerUid: data['providerUid'] as String?,
      budgetId: data['budgetId'] as String?,
      appointmentId: data['appointmentId'] as String?,
      clientUid: data['clientUid'] as String?,
      providerDirectoryId: data['providerDirectoryId'] as String?,
      providerName: data['providerName'] as String?,
      category: data['category'] as String?,
      addressText: data['addressText'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final JobStatus status;
  final String customerName;
  final int totalCents;
  final String? providerUid;
  final String? budgetId;
  final String? appointmentId;

  /// Uid do cliente do app dono do pedido original — nulo pra um job que,
  /// por algum motivo, não tenha vindo de um pedido pelo marketplace
  /// (hoje isso não acontece: `Job` só nasce em `acceptFinal`, que exige
  /// um orçamento vindo de cliente). Usado por functions/src/jobs.ts pra
  /// saber quem avisar a cada mudança de etapa.
  final String? clientUid;
  final String? providerDirectoryId;
  final String? providerName;
  final String? category;
  final String? addressText;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? paidAt;
  final DateTime? completedAt;
}
