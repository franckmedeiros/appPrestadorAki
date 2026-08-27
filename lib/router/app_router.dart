import 'package:go_router/go_router.dart';
import '../core/auth_controller.dart';
import '../features/auth/biometric_unlock_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/customers/customer_form_screen.dart';
import '../features/customers/customers_list_screen.dart';
import '../features/agenda/agenda_screen.dart';
import '../features/agenda/appointment_form_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/marketplace/client_home_screen.dart';
import '../features/marketplace/incoming_requests_screen.dart';
import '../features/marketplace/models/provider_listing.dart';
import '../features/marketplace/my_favorites_screen.dart';
import '../features/marketplace/my_requests_screen.dart';
import '../features/marketplace/provider_public_profile_screen.dart';
import '../features/marketplace/request_quote_form_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/splash_screen.dart';
import '../features/welcome/welcome_screen.dart';
import '../widgets/app_shell.dart';
import '../widgets/client_shell.dart';

// Telas de autenticação — hoje só existem pra abrir a "área do prestador"
// (cadastro é obrigatório pra prestador desde o início). O cliente também
// pode passar por aqui (ex.: link "Já tenho conta" dentro do gate de
// favoritar/solicitar orçamento), mas nunca é obrigado a isso só pra
// buscar — ver ClientAuthGate.
const _authScreens = {'/welcome', '/login', '/register'};

// Rotas que só fazem sentido pro lado do prestador — exigem conta desde
// sempre (isso não mudou com o pivot). Um convidado ou um cliente logado
// que tentar acessar uma dessas é mandado pra tela de entrada certa.
const _providerOnlyRoutes = {
  '/dashboard',
  '/clientes',
  '/clientes/novo',
  '/agenda',
  '/agenda/novo',
  '/orcamentos',
  '/pedidos',
  '/meu-perfil',
};

// Rotas do shell do lado do cliente. Depois da mudança de ideia, NENHUMA
// delas exige login pra ser visitada — busca é sempre livre, e
// favoritos/minhas-solicitações mostram elas mesmas um convite pra criar
// conta quando quem está olhando ainda é um convidado (ver
// ClientAuthGate/MyFavoritesScreen/MyRequestsScreen). Esse conjunto só
// serve aqui pra mandar de volta um PRESTADOR logado que tentar entrar
// nelas (ver `redirect` abaixo).
const _clientShellRoutes = {'/buscar', '/favoritos', '/minhas-solicitacoes', '/perfil'};

GoRouter buildAppRouter(AuthController authController) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authController,
    redirect: (context, state) {
      final status = authController.status;
      final role = authController.role;
      final location = state.matchedLocation;
      final isSplash = location == '/splash';
      final isUnlock = location == '/unlock';
      final isAuthScreen = _authScreens.contains(location);
      final home = role == AccountRole.provider ? '/dashboard' : '/buscar';

      switch (status) {
        case AuthStatus.unknown:
          return isSplash ? null : '/splash';
        case AuthStatus.locked:
          return isUnlock ? null : '/unlock';
        case AuthStatus.unauthenticated:
          // Convidado: navega livre pelo lado do cliente (busca, perfil
          // público, e até favoritos/minhas-solicitações — essas duas só
          // mostram um convite pra criar conta em vez de esconder a aba
          // inteira). Só o lado do prestador continua exigindo login.
          if (isSplash) return '/buscar';
          if (_providerOnlyRoutes.contains(location)) return '/welcome';
          return null;
        case AuthStatus.authenticated:
          if (isSplash || isUnlock || isAuthScreen) return home;
          if (role == AccountRole.client && _providerOnlyRoutes.contains(location)) return home;
          if (role == AccountRole.provider && _clientShellRoutes.contains(location)) return home;
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/unlock', builder: (context, state) => const BiometricUnlockScreen()),
      GoRoute(
        path: '/clientes/novo',
        builder: (context, state) => const CustomerFormScreen(),
      ),
      GoRoute(
        path: '/agenda/novo',
        builder: (context, state) => const AppointmentFormScreen(),
      ),
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/clientes', builder: (context, state) => const CustomersListScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/agenda', builder: (context, state) => const AgendaScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/orcamentos', builder: (context, state) => const BudgetsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/pedidos', builder: (context, state) => const IncomingRequestsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/meu-perfil', builder: (context, state) => const UserProfileScreen()),
          ]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ClientShell(navigationShell: navigationShell),
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
            GoRoute(path: '/perfil', builder: (context, state) => const UserProfileScreen()),
          ]),
        ],
      ),
    ],
  );
}
