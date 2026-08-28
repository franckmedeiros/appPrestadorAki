import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import 'appointments_repository.dart';
import 'models/appointment.dart';

/// Tela de agenda — lista os compromissos dos próximos 30 dias, com um
/// botão pra criar um novo e toque num card pra editar (ver
/// `_openAppointment`). Consulta diária (dia a dia) ficará mais rica
/// quando a UI de calendário de verdade for desenhada; por ora é uma
/// lista cronológica simples.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  // Stream ao vivo (ver AppointmentsRepository.watchRange) — mesma razão
  // de CustomersRepository.watchAll: resolve "salvei e não apareceu,
  // precisei sair e entrar de novo".
  late Stream<List<Appointment>> _stream = _watch();

  Stream<List<Appointment>> _watch() {
    final now = DateTime.now();
    return context.read<AppointmentsRepository>().watchRange(
          from: DateTime(now.year, now.month, now.day),
          to: now.add(const Duration(days: 30)),
        );
  }

  Future<void> _retry() async {
    setState(() => _stream = _watch());
  }

  Future<void> _openAppointment(Appointment? appointment) async {
    await context.push<bool>('/agenda/editar', extra: appointment);
    // A stream já reflete a escrita sozinha — não precisa recarregar nada
    // manualmente aqui.
  }

  Future<bool> _confirmDelete(Appointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir compromisso?'),
        content: Text(
          'Isso remove ${appointment.customerName ?? appointment.type.label} da agenda. '
          'Use isso quando o cliente desistiu do agendamento.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteAppointment(Appointment appointment) async {
    try {
      await context.read<AppointmentsRepository>().delete(appointment.id);
      // A stream já reflete a exclusão sozinha — sem precisar recarregar
      // nada manualmente aqui (mesma razão do comentário em watchRange).
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir o compromisso. Tenta de novo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAppointment(null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Appointment>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: 'Não foi possível carregar a agenda.',
              onRetry: _retry,
            );
          }
          final appointments = snapshot.data ?? [];
          if (appointments.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Icon(Icons.calendar_month_outlined, size: 48, color: AppColors.muted),
                SizedBox(height: 12),
                Text(
                  'Nada agendado nos próximos 30 dias.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: appointments.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final appointment = appointments[index];
              return Dismissible(
                key: ValueKey(appointment.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(appointment),
                onDismissed: (_) => _deleteAppointment(appointment),
                background: Container(
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                child: _AppointmentCard(
                  appointment: appointment,
                  onTap: () => _openAppointment(appointment),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment, required this.onTap});

  final Appointment appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = appointment.scheduledAt;
    final dateLabel = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    final timeLabel = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Text(dateLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(timeLabel, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.customerName ?? appointment.type.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(appointment.type.label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    if (appointment.addressText != null && appointment.addressText!.isNotEmpty)
                      Text(appointment.addressText!, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              _StatusChip(status: appointment.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AppointmentStatus.concluido => Colors.green,
      AppointmentStatus.cancelado => AppColors.danger,
      AppointmentStatus.confirmado => AppColors.primary,
      AppointmentStatus.agendado => AppColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ),
      ],
    );
  }
}
