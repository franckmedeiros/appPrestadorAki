import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/app_list_card.dart';
import '../../widgets/biometric_offer_card.dart';
import '../../widgets/decorative_header.dart';
import '../../widgets/notification_bell.dart';
import '../agenda/appointments_repository.dart';
import '../agenda/models/appointment.dart';
import '../marketplace/models/service_request.dart';
import '../marketplace/service_requests_repository.dart';

/// Aba "Dashboard" — só existe pra quem tem a capacidade de prestador
/// (ver UnifiedShell/AuthController.isProvider). Um resumo do dia +
/// atalhos pras telas que antes eram abas próprias (Clientes/Agenda/
/// Orçamentos/Pedidos), que agora só existem a partir daqui. Visual
/// desenhado a partir de um mockup que o Franck mandou (cabeçalho
/// decorativo, cartão de saudação flutuante, cards de atalho com
/// subtítulo e seta).
///
/// "Compromissos de hoje" mostra a agenda do dia de verdade (mesmo
/// repositório da aba Agenda, já ordenado por data/hora). O selo no
/// atalho "Orçamentos" conta os pedidos do marketplace
/// (ServiceRequestsRepository) com status "aguardando_prestador" —
/// pedidos que o cliente fez pelo botão "Solicitar orçamento" e que este
/// prestador ainda não respondeu.
String _firstName(String displayNameOrEmail) {
  if (displayNameOrEmail.contains('@')) return displayNameOrEmail;
  final parts = displayNameOrEmail.trim().split(RegExp(r'\s+'));
  return parts.isEmpty || parts.first.isEmpty ? displayNameOrEmail : parts.first;
}

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
  late Future<int> _pendingRequestsFuture;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    _todayFuture = _loadToday();
    _listingStatusFuture = _loadListingStatus();
    _pendingRequestsFuture = _loadPendingRequests();
  }

  Future<List<Appointment>> _loadToday() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return context.read<AppointmentsRepository>().list(from: startOfDay, to: endOfDay);
  }

  Future<int> _loadPendingRequests() async {
    // "Orçamentos abertos" = pedidos que o cliente fez (botão "Solicitar
    // orçamento" na busca) e que ainda não foram respondidos por este
    // prestador. Usa o mesmo repositório da tela de Pedidos
    // (incoming_requests_screen.dart) — sem endpoint próprio, é filtro em
    // memória mesmo, a lista de pedidos de um prestador não costuma ser
    // grande o bastante pra justificar um endpoint agregado.
    final requests = await context.read<ServiceRequestsRepository>().listForProvider();
    return requests.where((r) => r.status == ServiceRequestStatus.aguardandoPrestador).length;
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
    // Leitura leve só pro aviso de assinatura inativa abaixo (ver
    // functions/src/subscription.ts) — não vale a pena um método próprio
    // no AuthController só pra isso (ver EditProfileScreen, que também lê
    // listingStatus a partir do mesmo fetchOwnProfileData).
    final data = await context.read<AuthController>().fetchOwnProfileData();
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final showBiometricOffer =
        _biometricAvailable == true && !auth.biometricEnabled && !_dismissedThisSession;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecorativeHeader(
              height: 150,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 44),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dashboard',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: const NotificationBell(),
                  ),
                ],
              ),
            ),
            // Todo o resto sobe junto (cartão de saudação + seções abaixo)
            // pra não sobrar um vão em branco onde o cartão "deveria" estar
            // - só o cartão flutua sobre o cabeçalho, não os itens depois
            // dele (ver mesma ideia em UserProfileScreen, só que lá era um
            // painel único, não vários cards soltos como aqui).
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GreetingCard(name: _firstName(auth.displayName)),
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
                                '⏳ Sua assinatura mensal não está ativa no momento — assim que ela '
                                'for confirmada, você volta a aparecer nas buscas dos clientes.',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Compromissos de hoje',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        InkWell(
                          onTap: () => context.push('/agenda'),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Ver agenda', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                                Icon(Icons.chevron_right, color: AppColors.primary, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                        // Já vem ordenado por data/hora — mesmo orderBy('scheduledAt')
                        // de AppointmentsRepository.list() usado pela aba Agenda.
                        final today = snapshot.data ?? [];
                        if (today.isEmpty) {
                          return _TodayEmptyState(onGoToAgenda: () => context.push('/agenda'));
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
                    const SizedBox(height: 24),
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
                      childAspectRatio: 1.05,
                      children: [
                        _ShortcutCard(
                          icon: Icons.people_outline,
                          label: 'Clientes',
                          subtitle: 'Gerencie seus clientes',
                          onTap: () => context.push('/clientes'),
                        ),
                        _ShortcutCard(
                          icon: Icons.calendar_month_outlined,
                          label: 'Agenda',
                          subtitle: 'Veja visitas e serviços',
                          onTap: () => context.push('/agenda'),
                        ),
                        FutureBuilder<int>(
                          future: _pendingRequestsFuture,
                          builder: (context, snapshot) => _ShortcutCard(
                            icon: Icons.description_outlined,
                            label: 'Orçamentos',
                            subtitle: 'Crie e gerencie seus orçamentos',
                            onTap: () => context.push('/orcamentos'),
                            badgeCount: snapshot.data,
                          ),
                        ),
                        _ShortcutCard(
                          icon: Icons.inbox_outlined,
                          label: 'Pedidos',
                          subtitle: 'Acompanhe seus pedidos',
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
                  ],
                ),
              ),
            ),
          ],
        ),
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


class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  /// Número mostrado num selo no canto do card — hoje só usado no atalho
  /// "Orçamentos" (pedidos pendentes, ver _loadPendingRequests). `null` ou
  /// zero não mostra selo nenhum.
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: AppColors.primary, size: 22),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.25),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (badgeCount != null && badgeCount! > 0)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

/// Cartão de saudação flutuante — sobreposto à borda do cabeçalho
/// decorativo (ver Transform.translate em build()), com o nome de quem
/// está logado e uma decoração ilustrativa simples à direita (ícones em
/// vez de uma ilustração de verdade, que o app ainda não tem).
class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('👋', style: TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Olá, $name! 👋',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Aqui está o resumo do seu dia.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _GreetingDecoration(),
        ],
      ),
    );
  }
}

/// Decoração ilustrativa simples (página + selo de check) só pra dar um
/// toque visual ao cartão de saudação, no lugar da ilustração de verdade
/// do mockup - não temos esse asset no app.
class _GreetingDecoration extends StatelessWidget {
  const _GreetingDecoration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.eco_outlined, size: 18, color: AppColors.success),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio de "Compromissos de hoje" - ícone em círculo, texto em
/// negrito e uma frase com "Agenda" clicável no meio, igual ao mockup.
/// StatefulWidget só pra poder descartar o TapGestureRecognizer direito
/// (RichText/TextSpan não tem um jeito mais simples de misturar texto
/// tocável no meio de uma frase corrida).
class _TodayEmptyState extends StatefulWidget {
  const _TodayEmptyState({required this.onGoToAgenda});

  final VoidCallback onGoToAgenda;

  @override
  State<_TodayEmptyState> createState() => _TodayEmptyStateState();
}

class _TodayEmptyStateState extends State<_TodayEmptyState> {
  late final TapGestureRecognizer _agendaTapRecognizer;

  @override
  void initState() {
    super.initState();
    _agendaTapRecognizer = TapGestureRecognizer()..onTap = widget.onGoToAgenda;
  }

  @override
  void dispose() {
    _agendaTapRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.calendar_month_outlined, color: AppColors.primary, size: 26),
          ),
          const SizedBox(height: 14),
          const Text(
            'Nada agendado ainda.',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4),
              children: [
                const TextSpan(text: 'Vá para a aba '),
                TextSpan(
                  text: 'Agenda',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                  recognizer: _agendaTapRecognizer,
                ),
                const TextSpan(text: ' para marcar uma visita técnica ou serviço.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

