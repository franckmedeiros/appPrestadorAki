import 'package:go_router/go_router.dart';
import '../core/auth_controller.dart';
import '../features/auth/biometric_unlock_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
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
const _authScreens = {'/welcome', '/login', '/register'};

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
      // Sempre a busca — não existe mais "home do prestador" separada da
      // "home do cliente" (conta unificada); quem também é prestador
      // encontra o Dashboard como mais uma aba, não como ponto de entrada.
      const home = '/buscar';

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
      GoRoute(path: '/unlock', builder: (context, state) => const BiometricUnlockScreen()),
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
            GoRoute(path: '/perfil', builder: (context, state) => const UserProfileScreen()),
          ]),
        ],
      ),
    ],
  );
}
