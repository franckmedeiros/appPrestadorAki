import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../marketplace/client_auth_gate.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/models/service_category.dart';
import '../marketplace/provider_directory_repository.dart';
import 'edit_profile_screen.dart';

/// Aba "Meu perfil" — igual ao pedido do Franck ("colocar a opção de
/// usuário igual do Resenha, hoje eu não consigo mudar os dados do
/// usuário"): mostra os dados da conta logada (nome, e-mail, e pro lado
/// do prestador também categoria/cidade do perfil público), com botão
/// pra editar, atalho pra ativar/desativar a biometria, e sair da conta.
/// Existe nos dois lados do app (AppShell e ClientShell) — ver
/// app_router.dart.
///
/// No lado do prestador essa rota é "só de conta" (ver
/// `_providerOnlyRoutes` no router) — nunca é vista por um convidado. Já
/// no lado do cliente (`/perfil`), a busca é sempre livre, então um
/// convidado (ex.: acabou de sair da conta) chega aqui sem sessão — nesse
/// caso mostramos o mesmo convite de login/cadastro usado em
/// Favoritos/Minhas solicitações (ClientAuthGate), em vez de uma tela de
/// perfil vazia sem nenhum jeito óbvio de voltar a entrar.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Future<ProviderListing?>? _listingFuture;
  late Future<Map<String, dynamic>> _ownDataFuture;
  bool? _biometricAvailable;

  @override
  void initState() {
    super.initState();
    _loadListingIfProvider();
    _ownDataFuture = _fetchOwnData();
    _checkBiometricAvailability();
  }

  void _loadListingIfProvider() {
    final auth = context.read<AuthController>();
    if (auth.role == AccountRole.provider) {
      _listingFuture = context.read<ProviderDirectoryRepository>().get(auth.providerId);
    }
  }

  /// `fetchOwnProfileData` exige sessão (lê `providers/{uid}` ou
  /// `clients/{uid}` do próprio usuário) — sem isso daria erro pra um
  /// convidado. `build()` só chama esse future quando `isAuthenticated`,
  /// mas ele é montado aqui no `initState` (antes de sabermos se a tela
  /// vai de fato precisar dele), então a checagem fica aqui também.
  Future<Map<String, dynamic>> _fetchOwnData() {
    final auth = context.read<AuthController>();
    if (auth.status != AuthStatus.authenticated) return Future.value(const <String, dynamic>{});
    return auth.fetchOwnProfileData();
  }

  void _reloadOwnData() {
    _loadListingIfProvider();
    _ownDataFuture = _fetchOwnData();
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await context.read<AuthController>().biometricAvailable;
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  Future<void> _signIn() async {
    if (await ensureClientAccount(context) && mounted) setState(_reloadOwnData);
  }

  Future<void> _editProfile() async {
    final auth = context.read<AuthController>();
    final listing = auth.role == AccountRole.provider ? await _listingFuture : null;
    if (!mounted) return;
    final emailChanged = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(currentListing: listing)),
    );
    if (!mounted) return;
    setState(_reloadOwnData);
    if (emailChanged == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Enviamos um link de confirmação pro e-mail novo. Seu e-mail de '
          'login só muda depois que você confirmar pelo link.',
        ),
        duration: Duration(seconds: 6),
      ));
    }
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<AuthController>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isAuthenticated = auth.status == AuthStatus.authenticated;
    final isProvider = auth.role == AccountRole.provider;

    if (!isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meu perfil')),
        body: ClientSignInPrompt(
          icon: Icons.person_outline,
          message: 'Entre ou crie uma conta para ver e editar seus dados.',
          onPressed: _signIn,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.person, size: 42, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              auth.displayName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              _currentEmail(context),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
          if (isProvider)
            FutureBuilder<ProviderListing?>(
              future: _listingFuture,
              builder: (context, snapshot) {
                final listing = snapshot.data;
                return Column(
                  children: [
                    _InfoTile(
                      icon: Icons.handyman_outlined,
                      label: 'Categoria',
                      value: listing?.category.label ?? 'Não informado',
                    ),
                    _InfoTile(
                      icon: Icons.location_city_outlined,
                      label: 'Cidade',
                      value: listing != null && listing.city.isNotEmpty
                          ? listing.locationLabel
                          : 'Não informado',
                    ),
                  ],
                );
              },
            ),
          FutureBuilder<Map<String, dynamic>>(
            future: _ownDataFuture,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <String, dynamic>{};
              final whatsapp = data['whatsapp'] as String?;
              return Column(
                children: [
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Telefone/WhatsApp',
                    value: (whatsapp != null && whatsapp.isNotEmpty) ? whatsapp : 'Não informado',
                  ),
                  _InfoTile(
                    icon: Icons.home_outlined,
                    label: 'Endereço',
                    value: _formatAddress(data),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _editProfile,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar perfil'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (_biometricAvailable == true) ...[
            const SizedBox(height: 24),
            const Text('Segurança', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Card(
              child: SwitchListTile(
                value: auth.biometricEnabled,
                onChanged: (value) => context.read<AuthController>().setBiometricEnabled(value),
                title: const Text('Entrar com biometria'),
                subtitle: const Text(
                  'Digital ou reconhecimento facial, em vez de digitar a senha toda vez.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout, color: AppColors.danger),
            label: const Text('Sair da conta', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  String _currentEmail(BuildContext context) => context.read<AuthController>().currentUserEmail ?? '';

  String _formatAddress(Map<String, dynamic> data) {
    final street = data['addressStreet'] as String?;
    final neighborhood = data['addressNeighborhood'] as String?;
    final city = data['addressCity'] as String?;
    final state = data['addressState'] as String?;
    final zipCode = data['addressZipCode'] as String?;
    final cityState = (city != null && city.isNotEmpty)
        ? ((state != null && state.isNotEmpty) ? '$city/$state' : city)
        : null;
    final parts = <String>[
      if (street != null && street.isNotEmpty) street,
      if (neighborhood != null && neighborhood.isNotEmpty) neighborhood,
      if (cityState != null) cityState,
      if (zipCode != null && zipCode.isNotEmpty) 'CEP $zipCode',
    ];
    return parts.isEmpty ? 'Não informado' : parts.join(' - ');
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE4EE)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
