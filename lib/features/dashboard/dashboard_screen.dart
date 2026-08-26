import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/app_list_card.dart';
import '../agenda/appointments_repository.dart';
import '../agenda/models/appointment.dart';

/// Dashboard do prestador. O card de "Orçamentos abertos" ainda é estático
/// — o endpoint /providers/dashboard (contrato de API, seção 5) não existe
/// (só entra junto com o módulo de Orçamentos). Já "Compromissos hoje" usa
/// o endpoint /appointments de verdade, reaproveitando o mesmo repositório
/// da aba Agenda.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Em vez de um AlertDialog de uma vez só (fácil de perder, e que só
  // aparece se o timing do postFrameCallback bater certinho), a oferta de
  // biometria vira um cartão fixo no topo do dashboard — sempre visível
  // enquanto a condição for verdadeira, igual ao botão de biometria
  // persistente da tela de login do app Resenha. Nada de mágico com timing:
  // é só um Card que aparece ou não no build(), dependendo do estado atual.
  bool? _biometricAvailable;
  bool _dismissedThisSession = false;
  late Future<List<Appointment>> _todayFuture;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    _todayFuture = _loadToday();
  }

  Future<List<Appointment>> _loadToday() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return context.read<AppointmentsRepository>().list(from: startOfDay, to: endOfDay);
  }

  Future<void> _checkBiometricAvailability() async {
    final auth = context.read<AuthController>();
    final available = await auth.biometricAvailable;
    debugPrint('[Biometria] biometricAvailable=$available (dashboard)');
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  Future<void> _enableBiometrics() async {
    await context.read<AuthController>().setBiometricEnabled(true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final showBiometricOffer =
        _biometricAvailable == true && !auth.biometricEnabled && !_dismissedThisSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PrestadorAki'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () => context.read<AuthController>().logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Olá 👋',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('Aqui está o resumo do seu dia.', style: TextStyle(color: AppColors.muted)),
          if (showBiometricOffer) ...[
            const SizedBox(height: 16),
            _BiometricOfferCard(
              onEnable: _enableBiometrics,
              onDismiss: () => setState(() => _dismissedThisSession = true),
            ),
          ],
          const SizedBox(height: 20),
          FutureBuilder<List<Appointment>>(
            future: _todayFuture,
            builder: (context, snapshot) {
              final today = snapshot.data;
              return Row(
                children: [
                  const Expanded(
                    child: _StatCard(
                      icon: Icons.description_outlined,
                      label: 'Orçamentos abertos',
                      value: '—',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.event_available_outlined,
                      label: 'Compromissos hoje',
                      value: today == null ? '—' : '${today.length}',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Compromissos de hoje',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Appointment>>(
            future: _todayFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final today = snapshot.data ?? [];
              if (today.isEmpty) {
                return const _EmptyState(
                  icon: Icons.event_note_outlined,
                  message:
                      'Nada agendado ainda. Vá para a aba Agenda para marcar uma visita técnica ou serviço.',
                );
              }
              return Column(
                children: today
                    .map(
                      (appointment) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TodayAppointmentTile(appointment: appointment),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TodayAppointmentTile extends StatelessWidget {
  const _TodayAppointmentTile({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final date = appointment.scheduledAt;
    final timeLabel = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return AppListCard(
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(timeLabel,
            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      title: appointment.customerName ?? appointment.type.label,
      subtitle: appointment.type.label,
    );
  }
}

/// Cartão fixo (não um dialog que passa rápido) oferecendo ativar a
/// biometria — fica visível no topo do dashboard sempre que o aparelho
/// suporta e o prestador ainda não ativou, até ele ativar ou fechar o
/// cartão. Mesma ideia do botão de biometria sempre visível na tela de
/// login do app Resenha: melhor um elemento fixo na tela do que um modal
/// que pode passar despercebido.
class _BiometricOfferCard extends StatelessWidget {
  const _BiometricOfferCard({required this.onEnable, required this.onDismiss});

  final VoidCallback onEnable;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fingerprint, color: AppColors.primary, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Entrar com biometria',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Use digital ou reconhecimento facial pra abrir o app mais rápido da próxima vez.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton(onPressed: onEnable, child: const Text('Ativar')),
                      TextButton(onPressed: onDismiss, child: const Text('Agora não')),
                    ],
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
