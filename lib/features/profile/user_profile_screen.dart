import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/provider_directory_repository.dart';
import 'edit_profile_screen.dart';

/// Aba "Meu perfil" — igual ao pedido do Franck ("colocar a opção de
/// usuário igual do Resenha, hoje eu não consigo mudar os dados do
/// usuário"): mostra os dados da conta logada (nome, e-mail, e pro lado
/// do prestador também categoria/cidade do perfil público), com botão
/// pra editar, atalho pra ativar/desativar a biometria, e sair da conta.
/// Existe nos dois lados do app (AppShell e ClientShell) — ver
/// app_router.dart.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Future<ProviderListing?>? _listingFuture;
  bool? _biometricAvailable;

  @override
  void initState() {
    super.initState();
    _loadListingIfProvider();
    _checkBiometricAvailability();
  }

  void _loadListingIfProvider() {
    final auth = context.read<AuthController>();
    if (auth.role == AccountRole.provider) {
      _listingFuture = context.read<ProviderDirectoryRepository>().get(auth.providerId);
    }
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await context.read<AuthController>().biometricAvailable;
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  Future<void> _editProfile() async {
    final auth = context.read<AuthController>();
    final listing = auth.role == AccountRole.provider ? await _listingFuture : null;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditProfileScreen(currentListing: listing)),
    );
    if (!mounted) return;
    setState(_loadListingIfProvider);
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
    final isProvider = auth.role == AccountRole.provider;

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
