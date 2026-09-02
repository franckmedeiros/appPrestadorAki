import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/decorative_header.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/mask_text_input_formatter.dart';

/// Cadastro (decisão combinada com o Franck): toda conta nasce como
/// cliente — a capacidade de prestador não entra mais por aqui, porque
/// depende de confirmar uma assinatura mensal (Google Play Billing), o
/// que não cabe bem no meio do cadastro (o `in_app_purchase` só consegue
/// atrelar a compra a um uid do Firebase depois que a conta já existe).
/// Quem quiser virar prestador faz isso depois, em "Meu perfil" → "Também
/// quero oferecer serviços" (ver UserProfileScreen/ProviderPaywallScreen).
///
/// Layout reestilizado igual ao app Resenha (mesmo cabeçalho em gradiente
/// + cartão branco da LoginScreen) — só a aparência mudou, os campos
/// continuam os mesmos de sempre (nome, e-mail, senha, biometria).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneMask = MaskTextInputFormatter('(##) #####-####');
  bool _obscurePassword = true;

  // Mesma ideia da LoginScreen/DashboardScreen: oferece biometria já no
  // cadastro, em vez de só depois do primeiro login — assim quem já sabe
  // que quer usar biometria nem precisa passar pelo cartão de oferta do
  // Dashboard depois. Continua funcionando pra qualquer conta.
  bool? _biometricAvailable;
  bool _useBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await context.read<AuthController>().biometricAvailable;
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await auth.register(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text,
      phone: _phoneController.text.trim(),
    );
    if (ok && _useBiometrics) {
      await auth.setBiometricEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecorativeHeader(
              height: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Criar conta',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Leva menos de um minuto',
                    style: TextStyle(fontSize: 13.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LabeledTextField(
                        label: 'Nome completo',
                        controller: _nameController,
                        hintText: 'Digite seu nome completo',
                        prefixIcon: Icons.person_outline,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Informe seu nome' : null,
                      ),
                      const SizedBox(height: 18),
                      LabeledTextField(
                        label: 'E-mail',
                        controller: _emailController,
                        hintText: 'seuemail@exemplo.com',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.mail_outline,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            (value == null || !value.contains('@')) ? 'Informe um e-mail válido' : null,
                      ),
                      const SizedBox(height: 18),
                      // Pedido do Franck: obrigar o telefone no cadastro —
                      // é o que permite, na hora de um pedido de orçamento
                      // pelo marketplace, casar o cliente com um cadastro
                      // de cliente já existente do prestador por telefone
                      // em vez de por nome (ver
                      // CustomersRepository.findOrCreateForClient).
                      LabeledTextField(
                        label: 'Telefone',
                        controller: _phoneController,
                        hintText: '(00) 00000-0000',
                        keyboardType: TextInputType.phone,
                        prefixIcon: Icons.phone_outlined,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [_phoneMask],
                        validator: (value) {
                          final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                          return digits.length < 10 ? 'Informe um telefone válido' : null;
                        },
                      ),
                      const SizedBox(height: 18),
                      LabeledTextField(
                        label: 'Senha',
                        controller: _passwordController,
                        hintText: 'Mínimo de 8 caracteres',
                        obscureText: _obscurePassword,
                        prefixIcon: Icons.lock_outline,
                        textInputAction: TextInputAction.done,
                        validator: (value) =>
                            (value == null || value.length < 8) ? 'Mínimo de 8 caracteres' : null,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: AppColors.muted,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      if (_biometricAvailable == true) ...[
                        const SizedBox(height: 18),
                        _BiometricCheckbox(
                          value: _useBiometrics,
                          onChanged: (value) => setState(() => _useBiometrics = value),
                        ),
                      ],
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(auth.errorMessage!, style: const TextStyle(color: AppColors.danger)),
                      ],
                      const SizedBox(height: 24),
                      GradientPillButton(
                        label: 'Criar conta',
                        isLoading: auth.isBusy,
                        onPressed: auth.isBusy ? null : () => _submit(auth),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).maybePop(),
                          child: const Text(
                            'Já tenho conta, entrar',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão de "usar biometria" — mesma informação do checkbox antigo, só
/// que estilizado como um cartão discreto pra combinar com o resto do
/// formulário reestilizado.
class _BiometricCheckbox extends StatelessWidget {
  const _BiometricCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: value ? 0.4 : 0.12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Usar biometria pra entrar mais rápido',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(
                      'Digital ou reconhecimento facial, na próxima vez que abrir o app. '
                      'Dá pra ativar depois também, quando quiser.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
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
