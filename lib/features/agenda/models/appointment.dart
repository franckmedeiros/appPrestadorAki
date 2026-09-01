import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos e status espelham os mesmos valores usados antes (época da API
/// REST/Postgres) — só a origem dos dados mudou, o vocabulário do domínio
/// continua o mesmo (ver firebase/DATA_MODEL.md).
enum AppointmentType { visitaTecnica, servico, retorno, reuniao, pagamento, outro }

enum AppointmentStatus { agendado, confirmado, concluido, cancelado }

AppointmentType _typeFromWire(String value) => AppointmentType.values.firstWhere(
      (t) => t.wireValue == value,
      orElse: () => AppointmentType.outro,
    );

AppointmentStatus _statusFromWire(String value) => AppointmentStatus.values.firstWhere(
      (s) => s.wireValue == value,
      orElse: () => AppointmentStatus.agendado,
    );

extension AppointmentTypeWire on AppointmentType {
  String get wireValue => switch (this) {
        AppointmentType.visitaTecnica => 'visita_tecnica',
        AppointmentType.servico => 'servico',
        AppointmentType.retorno => 'retorno',
        AppointmentType.reuniao => 'reuniao',
        AppointmentType.pagamento => 'pagamento',
        AppointmentType.outro => 'outro',
      };

  String get label => switch (this) {
        AppointmentType.visitaTecnica => 'Visita técnica',
        AppointmentType.servico => 'Serviço',
        AppointmentType.retorno => 'Retorno',
        AppointmentType.reuniao => 'Reunião',
        AppointmentType.pagamento => 'Pagamento',
        AppointmentType.outro => 'Outro',
      };
}

extension AppointmentStatusWire on AppointmentStatus {
  String get wireValue => switch (this) {
        AppointmentStatus.agendado => 'agendado',
        AppointmentStatus.confirmado => 'confirmado',
        AppointmentStatus.concluido => 'concluido',
        AppointmentStatus.cancelado => 'cancelado',
      };

  String get label => switch (this) {
        AppointmentStatus.agendado => 'Agendado',
        AppointmentStatus.confirmado => 'Confirmado',
        AppointmentStatus.concluido => 'Concluído',
        AppointmentStatus.cancelado => 'Cancelado',
      };
}

class Appointment {
  Appointment({
    required this.id,
    required this.type,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    this.customerId,
    this.customerName,
    this.addressText,
    this.observations,
    this.budgetId,
  });

  factory Appointment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Appointment(
      id: doc.id,
      type: _typeFromWire(data['type'] as String? ?? 'outro'),
      scheduledAt: (data['scheduledAt'] as Timestamp).toDate(),
      durationMinutes: data['durationMinutes'] as int? ?? 60,
      status: _statusFromWire(data['status'] as String? ?? 'agendado'),
      customerId: data['customerId'] as String?,
      customerName: data['customerName'] as String?,
      addressText: data['addressText'] as String?,
      observations: data['observations'] as String?,
      budgetId: data['budgetId'] as String?,
    );
  }

  final String id;
  final AppointmentType type;
  final DateTime scheduledAt;
  final int durationMinutes;
  final AppointmentStatus status;
  // Adicionado pra dar pra pré-selecionar o cliente vinculado ao EDITAR
  // um compromisso (ver AppointmentFormScreen) — o campo já existia no
  // Firestore desde sempre (gravado por
  // AppointmentsRepository.create/update), só não vinha pro modelo porque
  // nada precisava dele de volta até a tela de edição existir.
  final String? customerId;
  final String? customerName;
  final String? addressText;
  final String? observations;

  /// Id do orçamento (ver `Budget`/`BudgetsRepository.acceptFinal`) que
  /// deu origem a este compromisso, quando ele foi lançado
  /// automaticamente no aceite final do prestador. Nulo pra compromissos
  /// criados manualmente na Agenda.
  final String? budgetId;
}
