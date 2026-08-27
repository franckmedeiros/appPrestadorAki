import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/testing_flags.dart';
import '../marketplace/client_auth_gate.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/models/service_category.dart';
import '../marketplace/provider_directory_repository.dart';
import 'edit_profile_screen.dart';
import 'provider_paywall_screen.dart';

/// Aba "Meu perfil" — igual ao pedido do Franck ("colocar a opção de
/// usuário igual do Resenha, hoje eu não consigo mudar os dados do
/// usuário"): mostra os dados da conta logada (nome, e-mail, e pro lado
/// do prestador também categoria/cidade do perfil público), com botão
/// pra editar, atalho pra ativar/desativar a biometria, e sair da conta.
/// Uma das 5 abas do shell único do app (ver UnifiedShell/app_router.dart).
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
    if (auth.isProvider) {
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

  /// "Também quero oferecer serviços" — abre o mesmo tipo de formulário do
  /// cadastro (categoria/cidade/UF) pra uma conta que já é só cliente virar
  /// prestador também (ver AuthController.becomeProvider). A tela toda
  /// reage sozinha depois (auth.isProvider vira true e o Provider notifica
  /// quem estiver observando) — só precisa recarregar os dados próprios.
  Future<void> _becomeProvider() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _BecomeProviderSheet(),
    );
    if (result == true && mounted) setState(_reloadOwnData);
  }

  Future<void> _editProfile() async {
    final auth = context.read<AuthController>();
    final listing = auth.isProvider ? await _listingFuture : null;
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
    final isProvider = auth.isProvider;

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
          // Categoria/cidade (quando prestador) vêm de `_ownDataFuture`
          // (providers/{uid}, o documento PRÓPRIO do dono da conta) — não
          // de `_listingFuture` (providerDirectory, o diretório PÚBLICO).
          // Enquanto a assinatura não estiver ativa, providerDirectory
          // nem chega a existir (ver DATA_MODEL.md, "Gate de pagamento"),
          // então usar o diretório público aqui faria a própria pessoa ver
          // "Não informado" pros dados que ela mesma já preencheu — mesmo
          // que "Editar perfil" mostre tudo certinho, porque lê a mesma
          // fonte (`_ownDataFuture`) que este bloco agora também usa.
          FutureBuilder<Map<String, dynamic>>(
            future: _ownDataFuture,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <String, dynamic>{};
              final whatsapp = data['whatsapp'] as String?;
              final category = data['category'] as String?;
              final city = data['city'] as String?;
              final state = data['state'] as String?;
              final cityLabel = (city != null && city.isNotEmpty)
                  ? ((state != null && state.isNotEmpty) ? '$city/$state' : city)
                  : null;
              return Column(
                children: [
                  if (isProvider) ...[
                    _InfoTile(
                      icon: Icons.handyman_outlined,
                      label: 'Categoria',
                      value: (category != null && category.isNotEmpty)
                          ? serviceCategoryFromWire(category).label
                          : 'Não informado',
                    ),
                    _InfoTile(
                      icon: Icons.location_city_outlined,
                      label: 'Cidade',
                      value: cityLabel ?? 'Não informado',
                    ),
                  ],
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
          if (!isProvider) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _becomeProvider,
              icon: const Icon(Icons.handyman_outlined),
              label: const Text('Também quero oferecer serviços'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
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

/// Formulário curto (categoria/cidade/UF) pra uma conta que já é cliente
/// virar também prestador — mesmo tipo de dado pedido no cadastro
/// (RegisterScreen), só que chamado a partir do "Meu perfil" em vez do
/// cadastro inicial. Só coleta os dados aqui; quem de fato cria
/// `providers/{uid}` é a Cloud Function `confirmarAssinaturaPrestador`,
/// depois que a assinatura mensal (Google Play Billing) for confirmada
/// na ProviderPaywallScreen — ver `_submit` abaixo.
class _BecomeProviderSheet extends StatefulWidget {
  const _BecomeProviderSheet();

  @override
  State<_BecomeProviderSheet> createState() => _BecomeProviderSheetState();
}

class _BecomeProviderSheetState extends State<_BecomeProviderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  ServiceCategory _category = ServiceCategory.eletricista;

  @override
  void dispose() {
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = _stateController.text.trim().toUpperCase();
    if (kBypassProviderSubscriptionGate) {
      // TEMPORÁRIO (ver lib/core/testing_flags.dart) — pula o paywall e
      // vira prestador de graça, só pra testar a busca/listagem antes do
      // Play Billing estar configurado de verdade.
      final ok = await context.read<AuthController>().becomeProvider(
            category: _category.wireValue,
            city: _cityController.text.trim(),
            state: state.isEmpty ? null : state,
          );
      if (ok && mounted) Navigator.pop(context, true);
      return;
    }
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProviderPaywallScreen(
          category: _category.wireValue,
          city: _cityController.text.trim(),
          state: state.isEmpty ? null : state,
        ),
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Também quero oferecer serviços',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sua conta continua a mesma — isso só adiciona a área de prestador.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<ServiceCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Sua principal categoria de serviço'),
                items: ServiceCategory.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                    .toList(),
                onChanged: (value) => setState(() => _category = value ?? _category),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Informe a cidade' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      maxLength: 2,
                      decoration: const InputDecoration(labelText: 'UF', counterText: ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Na próxima tela você confirma a assinatura mensal — assim que ela for '
                'aprovada, você já passa a aparecer nas buscas dos clientes.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Continuar para assinatura'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
