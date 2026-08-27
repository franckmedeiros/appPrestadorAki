import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/app_list_card.dart';
import '../../widgets/biometric_offer_card.dart';
import '../agenda/appointments_repository.dart';
import '../agenda/models/appointment.dart';

/// Aba "Dashboard" — só existe pra quem tem a capacidade de prestador
/// (ver UnifiedShell/AuthController.isProvider). Primeiro rascunho
/// combinado com o Franck: um resumo do dia + atalhos pras telas que
/// antes eram abas próprias (Clientes/Agenda/Orçamentos/Pedidos), que
/// agora só existem a partir daqui — o layout definitivo ainda precisa de
/// uma revisão em conjunto (ver combinado no chat).
///
/// O card de "Orçamentos abertos" ainda é estático — o endpoint
/// /providers/dashboard (contrato de API, seção 5) não existe (só entra
/// junto com o módulo de Orçamentos). Já "Compromissos hoje" usa o
/// endpoint /appointments de verdade, reaproveitando o mesmo repositório
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
  late Future<Map<String, dynamic>?> _listingStatusFuture;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    _todayFuture = _loadToday();
    _listingStatusFuture = _loadListingStatus();
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

  Future<Map<String, dynamic>?> _loadListingStatus() async {
    // Leitura leve só pro aviso de ativação pendente abaixo — não vale a
    // pena um método próprio no AuthController só pra isso (ver
    // EditProfileScreen, que também lê listingStatus a partir do mesmo
    // fetchOwnProfileData).
    final data = await context.read<AuthController>().fetchOwnProfileData();
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final showBiometricOffer =
        _biometricAvailable == true && !auth.biometricEnabled && !_dismissedThisSession;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Olá 👋',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('Aqui está o resumo do seu dia.', style: TextStyle(color: AppColors.muted)),
          FutureBuilder<Map<String, dynamic>?>(
            future: _listingStatusFuture,
            builder: (context, snapshot) {
              if (snapshot.data?['listingStatus'] != 'pending') return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Card(
                  color: const Color(0xFFFFF4E5),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '⏳ Seu cadastro de prestador ainda está em análise — assim que for '
                      'ativado, você passa a aparecer nas buscas dos clientes.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Atalhos',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _ShortcutCard(
                icon: Icons.people_outline,
                label: 'Clientes',
                onTap: () => context.push('/clientes'),
              ),
              _ShortcutCard(
                icon: Icons.calendar_month_outlined,
                label: 'Agenda',
                onTap: () => context.push('/agenda'),
              ),
              _ShortcutCard(
                icon: Icons.description_outlined,
                label: 'Orçamentos',
                onTap: () => context.push('/orcamentos'),
              ),
              _ShortcutCard(
                icon: Icons.inbox_outlined,
                label: 'Pedidos',
                onTap: () => context.push('/pedidos'),
              ),
            ],
          ),
          if (showBiometricOffer) ...[
            const SizedBox(height: 16),
            BiometricOfferCard(
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

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
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
