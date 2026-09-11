import 'package:go_router/go_router.dart';
import '../core/auth_controller.dart';
import '../features/auth/biometric_unlock_screen.dart';
import '../features/auth/email_verification_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/customers/customer_form_screen.dart';
import '../features/customers/customers_list_screen.dart';
import '../features/agenda/agenda_screen.dart';
import '../features/agenda/appointment_form_screen.dart';
import '../features/customers/models/customer.dart';
import '../features/agenda/models/appointment.dart';
import '../features/budgets/budget_form_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/budgets/models/budget.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/jobs/jobs_kanban_screen.dart';
import '../features/marketplace/client_home_screen.dart';
import '../features/marketplace/models/provider_listing.dart';
import '../features/marketplace/my_favorites_screen.dart';
import '../features/marketplace/my_requests_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/marketplace/provider_public_profile_screen.dart';
import '../features/marketplace/request_quote_form_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/splash_screen.dart';
import '../features/welcome/welcome_screen.dart';
import '../widgets/unified_shell.dart';

// Telas de autenticação — cadastro/login continuam existindo pra quem
// quer entrar com conta (ex.: a partir do gate de favoritar/solicitar
// orçamento) — nunca são obrigatórias só pra buscar (ver ClientAuthGate).
const _authScreens = {'/welcome', '/login', '/register', '/esqueci-senha'};

// As MESMAS telas de login/cadastro/esqueci-senha, só que penduradas
// debaixo do branch "Perfil" do shell — então elas abrem DENTRO da casca
// do app, com a barra de navegação embaixo, em vez de cobrir a tela
// inteira. Pedido do Franck ("quando eu clicar em Entrar ou Criar Conta,
// ele precisa ficar dentro do espaço e não fora assim"): quem chega na
// aba "Perfil" sem conta vê a tela de boas-vindas ali dentro, e continuar
// dali não pode "sair" do app visualmente.
//
// As rotas de cima (/login, /register, ...) continuam existindo pra quem
// abre essas telas de fora do shell — hoje ninguém faz isso, mas são o
// destino natural de um link/atalho externo e não custam nada mantidas.
const _authScreensNaAba = {'/perfil/entrar', '/perfil/criar-conta', '/perfil/esqueci-senha'};

// Trava de e-mail confirmado (pedido do Franck: "quando insiro no
// cadastro o email e o telefone, preciso que seja feito a validação ...
// para ficar seguro o nosso app"). Fica FORA do shell de propósito: não
// é uma aba nem uma tela empilhada, é a única coisa que uma conta não
// confirmada consegue ver — com barra de navegação embaixo a pessoa
// simplesmente contornaria a trava tocando em outra aba.
//
// Só afeta quem ENTROU: o convidado continua buscando prestador e vendo
// perfil público sem conta nenhuma (ver o caso `unauthenticated` no
// redirect), que é o que sempre segurou a primeira impressão do app.
const _confirmarEmail = '/confirmar-email';

// Rotas que só fazem sentido pra quem tem a capacidade de prestador
// (`auth.isProvider`) — conta unificada (ver AuthController): não são mais
// "o outro lado do app", só telas extras habilitadas por cima da mesma
// conta de sempre. Um convidado ou uma conta sem essa capacidade que
// tentar acessar uma dessas é mandado pra busca (ver `redirect` abaixo).
const _providerOnlyRoutes = {
  '/dashboard',
  '/clientes',
  '/clientes/novo',
  '/clientes/editar',
  '/agenda',
  '/agenda/novo',
  '/agenda/editar',
  '/orcamentos',
  '/orcamentos/editar',
  '/servicos',
};

GoRouter buildAppRouter(AuthController authController) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authController,
    redirect: (context, state) {
      final status = authController.status;
      final isProvider = authController.isProvider;
      final location = state.matchedLocation;
      final isSplash = location == '/splash';
      final isUnlock = location == '/unlock';
      final isAuthScreen = _authScreens.contains(location);
      // Pra quem também é prestador (`isProvider`), a home é o Dashboard
      // — pedido do Franck: abrir o app já cai direto lá, em vez de
      // precisar tocar na aba. Cliente sem essa capacidade continua
      // caindo na busca, como sempre (`isProvider` é sempre `false` pra
      // quem não está autenticado, então o convidado nunca é afetado).
      final home = isProvider ? '/dashboard' : '/buscar';

      switch (status) {
        case AuthStatus.unknown:
          return isSplash ? null : '/splash';
        case AuthStatus.locked:
          return isUnlock ? null : '/unlock';
        case AuthStatus.unauthenticated:
          // Convidado: navega livre pelo lado do cliente (busca, perfil
          // público, e até favoritos/minhas-solicitações — essas duas só
          // mostram um convite pra criar conta em vez de esconder a aba
          // inteira). Só as rotas de prestador continuam exigindo login.
          if (isSplash) return home;
          if (_providerOnlyRoutes.contains(location)) return '/welcome';
          return null;
        case AuthStatus.authenticated:
          // A TRAVA, antes de qualquer outra regra: conta logada com
          // e-mail ainda não confirmado não passa daqui, venha de onde
          // vier (cadastro recém-feito, login normal, app reaberto com
          // sessão salva). Vale também pras contas criadas antes desta
          // regra existir — todas com `emailVerified == false` no
          // Firebase — que vão cair nesta tela na próxima abertura.
          //
          // Quem avisa o router quando o e-mail é confirmado é o
          // `notifyListeners` de `reloadCurrentUser` (ver
          // EmailVerificationScreen): o SDK não descobre sozinho que a
          // pessoa clicou no link.
          if (!authController.emailVerified) {
            return location == _confirmarEmail ? null : _confirmarEmail;
          }
          // Confirmou (ou entrou numa conta já confirmada): não faz mais
          // sentido ficar na tela da trava.
          if (location == _confirmarEmail) return home;
          // Entrou/criou conta a partir da aba "Perfil": fica na própria
          // aba (mostrando agora o perfil de verdade) em vez de ser
          // jogado pra `home` — a pessoa estava mexendo ali, não faz
          // sentido acordar noutra aba.
          if (_authScreensNaAba.contains(location)) return '/perfil';
          if (isSplash || isUnlock || isAuthScreen) return home;
          if (!isProvider && _providerOnlyRoutes.contains(location)) return home;
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/esqueci-senha', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/unlock', builder: (context, state) => const BiometricUnlockScreen()),
      GoRoute(path: _confirmarEmail, builder: (context, state) => const EmailVerificationScreen()),
      // Telas do lado do prestador que antes viviam em abas próprias
      // (AppShell antigo) — depois da conta unificada, são alcançadas a partir de
      // botões dentro do Dashboard (ver DashboardScreen), como rotas
      // empilhadas normais em vez de branches do shell.
      GoRoute(path: '/clientes', builder: (context, state) => const CustomersListScreen()),
      GoRoute(
        path: '/clientes/novo',
        builder: (context, state) => const CustomerFormScreen(),
      ),
      // `extra` carrega o Customer sendo editado (ver
      // CustomersListScreen._openCustomer) — sem id na URL de propósito,
      // mesmo padrão de '/clientes/novo', só que com dado inicial.
      GoRoute(
        path: '/clientes/editar',
        builder: (context, state) => CustomerFormScreen(customer: state.extra as Customer?),
      ),
      GoRoute(path: '/agenda', builder: (context, state) => const AgendaScreen()),
      GoRoute(
        path: '/agenda/novo',
        builder: (context, state) => const AppointmentFormScreen(),
      ),
      GoRoute(
        path: '/agenda/editar',
        builder: (context, state) => AppointmentFormScreen(appointment: state.extra as Appointment?),
      ),
      GoRoute(path: '/orcamentos', builder: (context, state) => const BudgetsScreen()),
      GoRoute(path: '/servicos', builder: (context, state) => const JobsKanbanScreen()),
      // `extra` carrega o Budget sendo editado, null pra criar um novo —
      // mesmo padrão de '/clientes/editar' e '/agenda/editar'.
      GoRoute(
        path: '/orcamentos/editar',
        builder: (context, state) => BudgetFormScreen(budget: state.extra as Budget?),
      ),
      // Central de notificações (sininho) — aberta pros dois lados da
      // conta (cliente e prestador usam o mesmo uid, ver DATA_MODEL.md),
      // por isso não entra em `_providerOnlyRoutes`.
      GoRoute(path: '/notificacoes', builder: (context, state) => const NotificationsScreen()),
      // Perfil público de um prestador do marketplace — aberto pra
      // qualquer um, sem precisar de conta (ver mudança de ideia acima).
      GoRoute(
        path: '/prestador/:id',
        builder: (context, state) =>
            ProviderPublicProfileScreen(listingId: state.pathParameters['id']!),
      ),
      // Formulário de pedido de orçamento — recebe o ProviderListing já
      // carregado via `extra` (evita ler o Firestore de novo). A tela em
      // si pede conta na hora de enviar (ClientAuthGate), não pra abrir.
      GoRoute(
        path: '/solicitar/:id',
        builder: (context, state) =>
            RequestQuoteFormScreen(listing: state.extra as ProviderListing),
      ),
      // Casca única do app (ver UnifiedShell) — 5 branches fixos; a barra
      // só mostra "Dashboard" pra quem tem `isProvider == true` (ver
      // UnifiedShell), mas o branch em si sempre existe aqui.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            UnifiedShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/buscar', builder: (context, state) => const ClientHomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/favoritos', builder: (context, state) => const MyFavoritesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/minhas-solicitacoes', builder: (context, state) => const MyRequestsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/perfil',
              builder: (context, state) => const UserProfileScreen(),
              // Sub-rotas do próprio branch (ver `_authScreensNaAba`
              // acima): empilham DENTRO da aba, mantendo a barra de
              // navegação visível. São as mesmas telas de '/login',
              // '/register' e '/esqueci-senha', só que alcançadas por
              // dentro — quem manda pra cá é a tela de boas-vindas que a
              // aba mostra pra quem ainda não tem conta (ver
              // UserProfileScreen/WelcomeScreen).
              routes: [
                GoRoute(path: 'entrar', builder: (context, state) => const LoginScreen()),
                GoRoute(path: 'criar-conta', builder: (context, state) => const RegisterScreen()),
                GoRoute(
                  path: 'esqueci-senha',
                  builder: (context, state) => const ForgotPasswordScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
}
