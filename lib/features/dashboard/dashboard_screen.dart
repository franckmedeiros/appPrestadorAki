import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/app_list_card.dart';
import '../../widgets/biometric_offer_card.dart';
import '../../widgets/cabecalho_de_tela.dart';
import '../../widgets/notification_bell.dart';
import '../agenda/appointments_repository.dart';
import '../agenda/models/appointment.dart';
import '../budgets/budgets_repository.dart';
import '../jobs/job_details_sheet.dart';
import '../jobs/job_status_chip.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/models/job.dart';

/// Aba "Dashboard" — só existe pra quem tem a capacidade de prestador
/// (ver UnifiedShell/AuthController.isProvider). Um resumo do dia +
/// atalhos pras telas que antes eram abas próprias (Clientes/Agenda/
/// Orçamentos), que agora só existem a partir daqui.
///
/// "Compromissos de hoje" mostra a agenda do dia de verdade (mesmo
/// repositório da aba Agenda, já ordenado por data/hora). O selo no
/// atalho "Orçamentos" conta os pedidos de cliente pelo marketplace que
/// ainda estão "pendente" (ver `BudgetsRepository.watchPending`) — o
/// antigo atalho "Pedidos" foi removido: esses pedidos já nascem como
/// orçamento (ver `Budget`/`BudgetStatus`), não existe mais um "Pedido"
/// separado no meio do caminho.
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

  /// Dica do dia dispensada — só nesta sessão do app, de propósito. Não
  /// vale a pena gravar isso no banco nem no aparelho: é conteúdo leve,
  /// e reaparecer na próxima abertura é justamente o comportamento útil
  /// de uma dica.
  bool _dispensouDicaDoDia = false;
  // Antes era um Future recarregado só uma vez em initState — igual ao
  // bug já corrigido em Agenda/Clientes (ver AppointmentsRepository.
  // watchRange e CustomersRepository.watchAll): como o Dashboard vive
  // dentro de um StatefulShellRoute (UnifiedShell), essa aba nunca é
  // reconstruída ao trocar de aba, então um compromisso criado depois
  // (na Agenda, ou aceitando um orçamento) nunca aparecia aqui sem
  // fechar e abrir o app de novo. Com stream, atualiza sozinho.
  late Stream<List<Appointment>> _todayStream;
  late Future<Map<String, dynamic>?> _listingStatusFuture;
  // Mesmo motivo do _todayStream acima: watchPending() já era uma
  // stream de verdade, mas `.first` a transformava num Future só lido
  // uma vez em initState — o selo de "Orçamentos" também ficava
  // parado no valor de quando o Dashboard abriu pela primeira vez.
  late Stream<int> _pendingRequestsStream;
  // Guardo a lista inteira (não só a contagem) porque o card de
  // "Compromissos de hoje" agora também precisa saber, pra cada
  // compromisso, se existe um Job ligado a ele (pra mostrar a etapa e
  // deixar tocar pra mudar — pedido do Franck).
  late Stream<List<Job>> _jobsStream;
  late Stream<int> _activeJobsStream;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    _todayStream = _watchToday();
    _listingStatusFuture = _loadListingStatus();
    _pendingRequestsStream = _watchPendingRequests();
    // "Serviços ativos" = tudo que ainda não chegou em "concluído" — no
    // lugar do antigo atalho "Pedidos" (pedido do Franck), agora mostra
    // quantos serviços o prestador tem em andamento no Kanban.
    _jobsStream = context.read<JobsRepository>().watchAll();
    _activeJobsStream =
        _jobsStream.map((jobs) => jobs.where((job) => job.status != JobStatus.concluido).length);
  }

  Stream<List<Appointment>> _watchToday() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return context.read<AppointmentsRepository>().watchRange(from: startOfDay, to: endOfDay);
  }

  void _retryToday() {
    setState(() => _todayStream = _watchToday());
  }

  Stream<int> _watchPendingRequests() {
    // "Orçamentos abertos" = pedidos que o cliente fez (botão "Solicitar
    // orçamento" na busca) e que este prestador ainda não terminou de
    // preencher/enviar (status `pendente` — ver `BudgetStatus`).
    return context.read<BudgetsRepository>().watchPending().map((pending) => pending.length);
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
            // O cabeçalho em faixa laranja saiu. A saudação continua —
            // ela é do Franck e faz diferença pra quem abre o app todo
            // dia — mas agora é texto no corpo da tela, logo abaixo do
            // título, em vez de duas linhas espremidas dentro de uma
            // barra colorida.
            const SafeArea(
              bottom: false,
              child: CabecalhoDeTela(
                titulo: 'Gerenciamento',
                area: AreaDoApp.prestador,
                acao: NotificationBell(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.margemLateral,
                0,
                AppMetrics.margemLateral,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Text(
                      'Olá, ${auth.displayName.split(' ').first}! 👋',
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Aqui você organiza seus serviços e acompanha seu dia a dia.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FutureBuilder<Map<String, dynamic>?>(
                      future: _listingStatusFuture,
                      builder: (context, snapshot) {
                        if (snapshot.data?['listingStatus'] != 'pending') return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.warningSuave,
                              borderRadius: BorderRadius.circular(
                                AppMetrics.raioDeCartao,
                              ),
                            ),
                            child: const Text(
                              '⏳ Sua assinatura mensal não está ativa no momento — assim que ela '
                              'for confirmada, você volta a aparecer nas buscas dos clientes.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    TituloDeBloco(
                      'Compromissos de hoje',
                      rotuloDaAcao: 'Ver agenda',
                      aoTocarNaAcao: () => context.push('/agenda'),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<Appointment>>(
                      stream: _todayStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        // Antes esse erro ficava mascarado: sem checar
                        // `hasError`, uma falha ao carregar caía direto no
                        // "sem compromisso hoje" (mesmo bug já corrigido em
                        // MyRequestsScreen) — por isso o retry explícito aqui.
                        if (snapshot.hasError) {
                          return _TodayErrorState(onRetry: _retryToday);
                        }
                        // Já vem ordenado por data/hora — mesmo orderBy('scheduledAt')
                        // de AppointmentsRepository.list() usado pela aba Agenda.
                        final today = snapshot.data ?? [];
                        if (today.isEmpty) {
                          return _TodayEmptyState(onGoToAgenda: () => context.push('/agenda'));
                        }
                        return StreamBuilder<List<Job>>(
                          stream: _jobsStream,
                          builder: (context, jobsSnapshot) {
                            // Um compromisso só tem Job (e, portanto, etapa/selo/toque)
                            // quando nasceu do aceite final de um orçamento vindo do
                            // marketplace (ver Job.appointmentId) — visita/serviço
                            // criado à mão na Agenda continua sem nada disso.
                            final jobsByAppointmentId = <String, Job>{
                              for (final job in jobsSnapshot.data ?? const <Job>[])
                                if (job.appointmentId != null) job.appointmentId!: job,
                            };
                            // Pedido do Franck: "quando concluído os
                            // serviços, pode saindo do Compromisso hoje" —
                            // uma vez que o Job ligado já foi marcado como
                            // concluído (pagamento confirmado, serviço
                            // encerrado), o compromisso não precisa mais
                            // aparecer aqui — quem quiser revisitar um
                            // serviço antigo já concluído continua achando
                            // ele em "Serviços" (Kanban) ou na própria
                            // Agenda, só some deste atalho do Dashboard.
                            final visibleToday = today
                                .where((appointment) =>
                                    jobsByAppointmentId[appointment.id]?.status != JobStatus.concluido)
                                .toList();
                            if (visibleToday.isEmpty) {
                              return _TodayEmptyState(onGoToAgenda: () => context.push('/agenda'));
                            }
                            return _TodayAppointmentsList(
                              appointments: visibleToday,
                              jobsByAppointmentId: jobsByAppointmentId,
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    // Sem a linha "Acesse rapidamente as principais
                    // funções" que ficava embaixo: ela explicava o que os
                    // seis cartões logo abaixo já explicam sozinhos.
                    const TituloDeBloco('Atalhos'),
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
                        StreamBuilder<int>(
                          stream: _pendingRequestsStream,
                          builder: (context, snapshot) => _ShortcutCard(
                            icon: Icons.description_outlined,
                            label: 'Orçamentos',
                            subtitle: 'Crie e gerencie',
                            onTap: () => context.push('/orcamentos'),
                            badgeCount: snapshot.data,
                          ),
                        ),
                        StreamBuilder<int>(
                          stream: _activeJobsStream,
                          builder: (context, snapshot) => _ShortcutCard(
                            icon: Icons.build_outlined,
                            label: 'Serviços',
                            subtitle: 'Em execução',
                            onTap: () => context.push('/servicos'),
                            badgeCount: snapshot.data,
                          ),
                        ),
                        // Avaliações leva pro PRÓPRIO perfil público — é
                        // lá que as estrelas e os comentários dos clientes
                        // moram (ver ProviderPublicProfileScreen). Não
                        // existe uma tela separada só de avaliações, e
                        // criar uma duplicaria o que já está no perfil.
                        // Bônus: o prestador vê exatamente o que o cliente
                        // vê ao abrir o card dele na busca.
                        _ShortcutCard(
                          icon: Icons.star_outline_rounded,
                          label: 'Avaliações',
                          subtitle: 'O que dizem de você',
                          onTap: () => context.push('/prestador/${auth.providerId}'),
                        ),
                        // Financeiro não tem tela de lançamento: os
                        // números saem dos serviços que ele já movimenta
                        // no Kanban (ver FinanceiroScreen).
                        _ShortcutCard(
                          icon: Icons.bar_chart_rounded,
                          label: 'Financeiro',
                          subtitle: 'Quanto entrou',
                          onTap: () => context.push('/financeiro'),
                        ),
                        // Monta uma imagem pronta pra ele postar no
                        // Instagram/WhatsApp com as fotos que já estão no
                        // perfil dele (ver CardDivulgacaoScreen). Fica no
                        // Dashboard, junto do resto do trabalho, e não no
                        // Perfil: postar é tarefa de quem está tocando o
                        // negócio, não configuração de conta.
                        _ShortcutCard(
                          icon: Icons.campaign_outlined,
                          label: 'Divulgar',
                          subtitle: 'Poste seu trabalho',
                          onTap: () => context.push('/divulgar'),
                        ),
                      ],
                    ),
                    if (!_dispensouDicaDoDia) ...[
                      const SizedBox(height: 16),
                      _DicaDoDia(onDismiss: () => setState(() => _dispensouDicaDoDia = true)),
                    ],
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
          ],
        ),
      ),
    );
  }
}

/// Lista de "Compromissos de hoje" com altura própria e rolagem interna —
/// pedido do Franck: com muitos compromissos no dia (ele chegou a citar
/// uns 10 clientes), a lista não pode mais "empurrar" a seção Atalhos pra
/// baixo da tela; ela cresce só até um limite e passa a rolar sozinha
/// dali pra frente. Com poucos itens (cabem nos `_maxHeight`), o
/// `ListView` com `shrinkWrap: true` simplesmente ocupa só o espaço que
/// precisa — o `ConstrainedBox` só entra em ação quando o conteúdo
/// passaria do limite.
class _TodayAppointmentsList extends StatelessWidget {
  const _TodayAppointmentsList({required this.appointments, required this.jobsByAppointmentId});

  final List<Appointment> appointments;
  final Map<String, Job> jobsByAppointmentId;

  static const _maxHeight = 260.0;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      shrinkWrap: true,
      itemCount: appointments.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final appointment = appointments[index];
        return _TodayAppointmentTile(
          appointment: appointment,
          job: jobsByAppointmentId[appointment.id],
        );
      },
    );
    final bounded = ConstrainedBox(constraints: const BoxConstraints(maxHeight: _maxHeight), child: list);
    // Sombreado de "tem mais embaixo" só quando a lista provavelmente vai
    // mesmo precisar rolar (estimativa: mais de 3 cards não cabem nos
    // 260px) — sem isso, uns 2 compromissos ficariam com uma sombra
    // decorativa sem função nenhuma.
    if (appointments.length <= 3) return bounded;
    return Stack(
      children: [
        bounded,
        Positioned(
          left: 0,
          right: 4,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.background.withValues(alpha: 0), AppColors.background],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayAppointmentTile extends StatelessWidget {
  const _TodayAppointmentTile({required this.appointment, this.job});

  final Appointment appointment;

  /// Serviço (Kanban) ligado a este compromisso, se houver — só existe
  /// quando o compromisso nasceu do aceite final de um orçamento vindo
  /// do marketplace (ver `Job.appointmentId`). Com ele, o card ganha um
  /// selo de etapa e passa a abrir o mesmo painel de ações do Kanban ao
  /// tocar; sem ele, o card continua igual a antes (só informativo).
  final Job? job;

  @override
  Widget build(BuildContext context) {
    final date = appointment.scheduledAt;
    final timeLabel = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final job = this.job;
    final endereco = appointment.addressText?.trim();
    return AppListCard(
      // A hora num bloco laranja CLARO com o número em laranja — era um
      // bloco laranja chapado com a hora em branco. Numa lista de dez
      // compromissos, dez blocos chapados competiam entre si e com o
      // nome do cliente, que é o que a pessoa procura ao bater o olho.
      leading: Container(
        width: 72,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.primarySuave,
          borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
        ),
        alignment: Alignment.center,
        child: Text(
          timeLabel,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: appointment.customerName ?? appointment.type.label,
      subtitle: appointment.type.label,
      footer: (job != null || (endereco != null && endereco.isNotEmpty))
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (job != null) JobStatusChip(status: job.status),
                if (endereco != null && endereco.isNotEmpty) ...[
                  if (job != null) const SizedBox(height: 8),
                  Text(
                    endereco,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
      // Com serviço (Kanban) ligado, o toque abre o painel de ações do
      // Job (comportamento de sempre). Sem Job — compromisso "solto" da
      // agenda, sem orçamento de marketplace por trás — pedido do Franck:
      // "se eu clicar na agenda em Compromisso de hoje, ela abrir a
      // agenda que estou clicando", ou seja, o mesmo formulário de edição
      // que abre ao tocar nesse compromisso dentro da própria aba Agenda
      // (ver AgendaScreen._openAppointment).
      onTap: job != null
          ? () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (context) => JobDetailsSheet(job: job),
              )
          : () => context.push('/agenda/editar', extra: appointment),
    );
  }
}


/// Cartão de "Dica do dia" (mockup aprovado pelo Franck).
///
/// Texto fixo, e isso é de propósito: é orientação de uso, o tipo de
/// coisa que o app pode afirmar sem medir nada. Diferente dos selos do
/// mockup do card de busca ("Verificado", "Responde rápido"), que
/// prometiam fatos sobre o prestador que não temos como sustentar.
class _DicaDoDia extends StatelessWidget {
  const _DicaDoDia({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.primarySuave,
        borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lightbulb_outline, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dica do dia',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
                SizedBox(height: 2),
                Text(
                  'Mantenha sua agenda atualizada',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  'Isso evita dois clientes no mesmo horário — o app só '
                  'consegue bloquear o conflito se a agenda estiver em dia.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            tooltip: 'Dispensar',
          ),
        ],
      ),
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

  /// Número mostrado num selo no canto do card — usado nos atalhos
  /// "Orçamentos" (pedidos pendentes) e "Serviços" (em execução). `null`
  /// ou zero não mostra selo nenhum.
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    // Cada atalho tinha uma cor própria no quadradinho do ícone — azul
    // pra Agenda, verde pro Financeiro, roxo pro Divulgar. Seis cores
    // numa tela só é o que mais dava ar de protótipo aqui: virava um
    // mosaico, e nenhuma delas queria dizer nada (verde não é "dinheiro"
    // em lugar nenhum do app). No desenho novo o ícone é desenhado
    // direto no cartão, sem quadrado atrás, todos no laranja da marca —
    // quem separa um atalho do outro é o nome, que é o que a pessoa lê
    // de qualquer jeito.
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
        child: Padding(
          padding: const EdgeInsets.all(AppMetrics.paddingDeCartao),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: AppColors.primary, size: 24),
                  const Spacer(),
                  if (badgeCount != null && badgeCount! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySuave,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.2,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado de erro de "Compromissos de hoje" — mesmo padrão de
/// `_ErrorState` em AgendaScreen/CustomersListScreen (ícone + mensagem +
/// botão "Tentar de novo"), só que aqui reconstrói o `Future` guardado
/// no State (ver `_DashboardScreenState._retryToday`) em vez de recriar
/// uma Stream.
class _TodayErrorState extends StatelessWidget {
  const _TodayErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 36, color: AppColors.danger),
          const SizedBox(height: 8),
          const Text('Não foi possível carregar os compromissos de hoje.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Tentar de novo')),
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
        borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
        border: Border.all(color: AppColors.borda),
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

