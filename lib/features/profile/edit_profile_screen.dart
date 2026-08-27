import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/models/service_category.dart';
import '../marketplace/provider_directory_repository.dart';

/// Formulário de edição dos dados do próprio usuário — igual ao pedido
/// do Franck ("no meu perfil, deveria ficar assim", com referência ao
/// app Resenha), depois ajustado por ele mesmo: sem data de nascimento
/// nem chave Pix — no lugar, e-mail (editável) e endereço. WhatsApp
/// continua pra todo mundo; categoria/cidade/UF de "área de atuação" só
/// pro prestador (são os mesmos campos preenchidos no cadastro, que
/// decidem em quais buscas ele aparece — ver
/// ProviderDirectoryRepository.upsertOwnListing). O endereço (CEP, rua e
/// número, bairro, cidade, UF) é um dado só da conta — nunca aparece no
/// perfil público do diretório.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.currentListing});

  /// Perfil público atual do prestador, se já existir — `null` pro
  /// cliente, ou pro prestador que ainda não tem entrada no diretório por
  /// algum motivo (não deveria acontecer, mas os campos abaixo cobrem
  /// esse caso partindo em branco).
  final ProviderListing? currentListing;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final _whatsappController = TextEditingController();
  final _cepController = TextEditingController();
  final _streetController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _addressCityController = TextEditingController();
  final _addressStateController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _streetFocusNode = FocusNode();
  ServiceCategory _category = ServiceCategory.eletricista;

  final _phoneMask = MaskTextInputFormatter('(##) #####-####');
  final _cepMask = MaskTextInputFormatter('#####-###');

  bool _loading = true;
  bool _isSaving = false;
  bool _lookingUpCep = false;
  String? _cepLookupError;
  String? _error;

  // Só existe pra prestador — reflete se a assinatura mensal (Google Play
  // Billing) está ativa agora (ver functions/src/subscription.ts):
  // 'active' com assinatura em dia, 'pending' quando ela não está ativa
  // (nunca chegou a assinar, cancelou, ou atrasou o pagamento além da
  // carência). Enquanto pendente, salvar aqui NÃO cria/atualiza a entrada
  // pública no diretório (ver _save abaixo) — a área de atuação fica salva
  // só em providers/{uid}, pronta pra quando a assinatura voltar a ativar
  // (a própria notificação da Play Store faz isso sozinha).
  String? _listingStatus;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _nameController = TextEditingController(text: auth.displayName);
    _emailController = TextEditingController(text: auth.currentUserEmail ?? '');
    final listing = widget.currentListing;
    _cityController.text = listing?.city ?? '';
    _stateController.text = listing?.state ?? '';
    if (listing != null) _category = listing.category;
    _loadOwnData();
  }

  Future<void> _loadOwnData() async {
    final data = await context.read<AuthController>().fetchOwnProfileData();
    if (!mounted) return;
    _cepController.text = data['addressZipCode'] as String? ?? '';
    _streetController.text = data['addressStreet'] as String? ?? '';
    _neighborhoodController.text = data['addressNeighborhood'] as String? ?? '';
    _addressCityController.text = data['addressCity'] as String? ?? '';
    _addressStateController.text = data['addressState'] as String? ?? '';
    _whatsappController.text = data['whatsapp'] as String? ?? '';
    _listingStatus = data['listingStatus'] as String?;
    // A área de atuação vem de providers/{uid} (sempre existe, mesmo
    // 'pending' — ver functions/src/subscription.ts), não só do
    // `widget.currentListing` (que só reflete o diretório PÚBLICO, vazio
    // pra quem ainda não foi ativado). Só sobrescreve o que já veio do
    // `currentListing` no initState se providers/{uid} de fato tiver o
    // campo — evita apagar um valor bom com um branco à toa.
    final category = data['category'] as String?;
    final city = data['city'] as String?;
    final state = data['state'] as String?;
    if (category != null) _category = serviceCategoryFromWire(category);
    if (city != null && city.isNotEmpty) _cityController.text = city;
    if (state != null && state.isNotEmpty) _stateController.text = state;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _whatsappController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _neighborhoodController.dispose();
    _addressCityController.dispose();
    _addressStateController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _streetFocusNode.dispose();
    super.dispose();
  }

  bool get _isProvider => context.read<AuthController>().isProvider;

  /// Busca o endereço automaticamente a partir do CEP digitado — via
  /// ViaCEP (não existe uma API pública e gratuita dos Correios pra
  /// isso; o ViaCEP é o serviço padrão usado por apps brasileiros pra
  /// esse tipo de busca, consultando a mesma base dos Correios). Só
  /// dispara quando o CEP fica completo (8 dígitos, ver o `onChanged` do
  /// campo); falha em silêncio numa mensagem pequena embaixo do campo —
  /// o usuário sempre pode preencher rua/bairro/cidade na mão.
  Future<void> _lookupCep(String cep) async {
    setState(() {
      _lookingUpCep = true;
      _cepLookupError = null;
    });
    try {
      final response = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _cepLookupError = 'Não foi possível buscar o CEP agora.');
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['erro'] == true) {
        setState(() => _cepLookupError = 'CEP não encontrado.');
        return;
      }
      final logradouro = data['logradouro'] as String?;
      setState(() {
        // Deixa a vírgula e o foco prontos pro usuário só completar com o
        // número da casa — o ViaCEP não devolve número nenhum.
        _streetController.text =
            (logradouro != null && logradouro.isNotEmpty) ? '$logradouro, ' : _streetController.text;
        _neighborhoodController.text = (data['bairro'] as String?) ?? _neighborhoodController.text;
        _addressCityController.text = (data['localidade'] as String?) ?? _addressCityController.text;
        _addressStateController.text = (data['uf'] as String?) ?? _addressStateController.text;
      });
      _streetController.selection =
          TextSelection.fromPosition(TextPosition(offset: _streetController.text.length));
      _streetFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cepLookupError = 'Não foi possível buscar o CEP agora.');
    } finally {
      if (mounted) setState(() => _lookingUpCep = false);
    }
  }

  /// Pede a senha atual antes de trocar o e-mail — o Firebase exige uma
  /// reautenticação recente pra esse tipo de operação sensível (senão
  /// lança `requires-recent-login`). Devolve `null` se o usuário cancelar.
  Future<String?> _promptCurrentPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirme sua senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pra trocar seu e-mail de login, digite sua senha atual.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Senha atual'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthController>();
    final newEmail = _emailController.text.trim();
    final emailChanged = newEmail != (auth.currentUserEmail ?? '');

    String? currentPassword;
    if (emailChanged) {
      currentPassword = await _promptCurrentPassword();
      if (!mounted) return;
      if (currentPassword == null || currentPassword.isEmpty) return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    if (emailChanged) {
      final emailOk = await auth.updateEmailAddress(newEmail, currentPassword!);
      if (!mounted) return;
      if (!emailOk) {
        setState(() {
          _isSaving = false;
          _error = auth.errorMessage ?? 'Não foi possível atualizar o e-mail.';
        });
        return;
      }
    }

    final name = _nameController.text.trim();
    final ok = await auth.updateOwnProfile(
      name: name,
      whatsapp: _whatsappController.text.trim(),
      addressZipCode: _cepController.text.trim(),
      addressStreet: _streetController.text.trim(),
      addressNeighborhood: _neighborhoodController.text.trim(),
      addressCity: _addressCityController.text.trim(),
      addressState: _addressStateController.text.trim().toUpperCase(),
    );

    if (ok && _isProvider) {
      try {
        // Guarda a área de atuação em providers/{uid} independente do
        // status de ativação — não se perde enquanto listingStatus segue
        // 'pending'.
        final businessInfoOk = await auth.updateProviderBusinessInfo(
          category: _category.wireValue,
          city: _cityController.text.trim(),
          state: _stateController.text.trim().toUpperCase(),
        );
        if (!businessInfoOk) {
          if (!mounted) return;
          setState(() {
            _isSaving = false;
            _error = auth.errorMessage ?? 'Dados salvos, mas não foi possível atualizar categoria/cidade.';
          });
          return;
        }
        // Só publica/atualiza a entrada pública do diretório (o que faz o
        // prestador aparecer na busca do cliente) se a assinatura estiver
        // ativa agora — ver functions/src/subscription.ts. Prestadores
        // antigos (sem esse campo ainda) continuam publicando normalmente.
        if (_listingStatus != 'pending') {
          await context.read<ProviderDirectoryRepository>().upsertOwnListing(
                name: name,
                category: _category,
                city: _cityController.text.trim(),
                state: _stateController.text.trim().toUpperCase(),
              );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _error = 'Dados salvos, mas não foi possível atualizar categoria/cidade. Tente de novo.';
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      // O `pop(emailChanged)` avisa a UserProfileScreen pra mostrar o
      // aviso sobre o link de confirmação — SnackBar não sobrevive bem
      // se disparado bem em cima de um pop desta própria tela.
      Navigator.of(context).pop(emailChanged);
    } else {
      setState(() => _error = auth.errorMessage ?? 'Não foi possível salvar as alterações.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isProvider = _isProvider;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: isProvider ? 'Nome ou razão social' : 'Seu nome',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Informe seu nome' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) =>
                      (value == null || !value.contains('@')) ? 'Informe um e-mail válido' : null,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Se você trocar o e-mail, vamos pedir sua senha atual e mandar um '
                  'link de confirmação pro e-mail novo.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _whatsappController,
                  decoration: const InputDecoration(
                    labelText: 'Telefone/WhatsApp (opcional)',
                    hintText: '(00) 00000-0000',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_phoneMask],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    return digits.length < 10 ? 'Telefone incompleto' : null;
                  },
                ),
                if (isProvider) ...[
                  const SizedBox(height: 20),
                  const Text('Área de atuação', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  if (_listingStatus == 'pending') ...[
                    const SizedBox(height: 8),
                    const Card(
                      color: Color(0xFFFFF4E5),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          '⏳ Sua assinatura mensal não está ativa no momento — assim que ela '
                          'for confirmada, você volta a aparecer nas buscas dos clientes.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ServiceCategory>(
                    initialValue: _category,
                    decoration:
                        const InputDecoration(labelText: 'Sua principal categoria de serviço'),
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
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? 'Informe a cidade'
                              : null,
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
                    'Cidade e categoria são o que faz você aparecer nas buscas '
                    'dos clientes no PrestadorAki.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
                const SizedBox(height: 20),
                const Text('Endereço', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                const Text(
                  'Fica só na sua conta — não aparece no seu perfil público.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cepController,
                  decoration: InputDecoration(
                    labelText: 'CEP (opcional)',
                    hintText: '00000-000',
                    suffixIcon: _lookingUpCep
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [_cepMask],
                  onChanged: (value) {
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length == 8) {
                      _lookupCep(digits);
                    } else if (_cepLookupError != null) {
                      setState(() => _cepLookupError = null);
                    }
                  },
                ),
                if (_cepLookupError != null) ...[
                  const SizedBox(height: 4),
                  Text(_cepLookupError!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _streetController,
                  focusNode: _streetFocusNode,
                  decoration: const InputDecoration(labelText: 'Rua e número (opcional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _neighborhoodController,
                  decoration: const InputDecoration(labelText: 'Bairro (opcional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _addressCityController,
                        decoration: const InputDecoration(labelText: 'Cidade (opcional)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _addressStateController,
                        maxLength: 2,
                        decoration: const InputDecoration(labelText: 'UF', counterText: ''),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Salvar alterações'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

