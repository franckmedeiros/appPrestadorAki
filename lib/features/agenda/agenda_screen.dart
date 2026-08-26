import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import 'appointments_repository.dart';
import 'models/appointment.dart';

/// Tela de agenda — lista os compromissos dos próximos 30 dias (endpoint
/// GET /appointments?from=&to=), com um botão pra criar um novo. Consulta
/// diária (dia a dia) ficará mais rica quando a UI de calendário de verdade
/// for desenhada; por ora é uma lista cronológica simples.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late Future<List<Appointment>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Appointment>> _load() {
    final now = DateTime.now();
    return context.read<AppointmentsRepository>().list(
          from: DateTime(now.year, now.month, now.day),
          to: now.add(const Duration(days: 30)),
        );
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await context.push<bool>('/agenda/novo');
          if (created == true) _reload();
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Appointment>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final message = snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : 'Não foi possível carregar a agenda.';
              return _ErrorState(message: message, onRetry: _reload);
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
              itemBuilder: (context, index) => _AppointmentCard(appointment: appointments[index]),
            );
          },
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final date = appointment.scheduledAt;
    final dateLabel = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    final timeLabel = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Card(
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
