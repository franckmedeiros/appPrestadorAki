import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
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
  ServiceCategory _category = ServiceCategory.eletricista;

  final _phoneMask = _MaskTextInputFormatter('(##) #####-####');
  final _cepMask = _MaskTextInputFormatter('#####-###');

  bool _loading = true;
  bool _isSaving = false;
  String? _error;

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
    super.dispose();
  }

  bool get _isProvider => context.read<AuthController>().role == AccountRole.provider;

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
        await context.read<ProviderDirectoryRepository>().upsertOwnListing(
              name: name,
              category: _category,
              city: _cityController.text.trim(),
              state: _stateController.text.trim().toUpperCase(),
            );
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
                  decoration: const InputDecoration(labelText: 'CEP (opcional)', hintText: '00000-000'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [_cepMask],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _streetController,
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

/// Máscara de texto minimalista (sem depender de nenhum pacote externo —
/// menos uma dependência do Gradle pra dar problema, ver o histórico de
/// build do compileSdk). `#` no padrão vira "próximo dígito digitado";
/// qualquer outro caractere do padrão (espaço, parênteses, traço, barra)
/// é inserido literalmente. Usada pro telefone e pro CEP.
class _MaskTextInputFormatter extends TextInputFormatter {
  _MaskTextInputFormatter(this.mask);

  final String mask;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    var digitIndex = 0;
    for (var i = 0; i < mask.length && digitIndex < digits.length; i++) {
      if (mask[i] == '#') {
        buffer.write(digits[digitIndex]);
        digitIndex++;
      } else {
        buffer.write(mask[i]);
      }
    }
    final text = buffer.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
