import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/validators.dart';
import '../../widgets/botao_com_seta.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/marca_app.dart';
import '../../widgets/password_requirements_hint.dart';
import 'terms_acceptance_checkbox.dart';
import '../../widgets/mask_text_input_formatter.dart';

/// Cadastro (decisão combinada com o Franck): toda conta nasce como
/// cliente — a capacidade de prestador não entra mais por aqui, porque
/// depende de confirmar uma assinatura mensal (Google Play Billing), o
/// que não cabe bem no meio do cadastro (o `in_app_purchase` só consegue
/// atrelar a compra a um uid do Firebase depois que a conta já existe).
/// Quem quiser virar prestador faz isso depois, em "Meu perfil" → "Também
/// quero oferecer serviços" (ver UserProfileScreen/ProviderPaywallScreen).
///
/// Visual refeito a partir da entrega do Figma (out/2026), igual ao da
/// tela de Login: fundo creme, sem o cabeçalho em faixa e sem o cartão
/// branco que subia por cima dele. Os campos são os mesmos de sempre
/// (nome, e-mail, telefone, senha, biometria).
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

  /// Aceite dos Termos de Uso — obrigatório pra concluir o cadastro
  /// (Guideline 1.2). Começa falso, e o botão "Criar conta" fica
  /// desabilitado até virar verdadeiro.
  bool _aceitouOsTermos = false;

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
    // Deu errado: a mensagem já aparece no corpo da tela (ver
    // `auth.errorMessage` no build), não há mais nada a fazer aqui.
    if (!ok) return;

    if (_useBiometrics) {
      await auth.setBiometricEnabled(true);
    }
    if (!mounted) return;

    // Confirmação e navegação EXPLÍCITAS. Antes esta tela não fazia nem
    // uma coisa nem outra: contava com o `redirect` do go_router perceber
    // que o status virou `authenticated` e tirar a pessoa daqui sozinho.
    // Na prática o Franck viu a tela ficar parada depois de "Criar conta"
    // — sem erro e sem sucesso — mesmo com a conta criada certinho no
    // banco. Navegar na mão aqui não depende de nada disso, e o
    // `redirect` continua valendo como rede de segurança (levaria pro
    // mesmo lugar).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Conta criada! Confirme seu e-mail pelo link que enviamos.'),
        duration: Duration(seconds: 5),
      ),
    );
    context.go('/perfil');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppMetrics.margemLateral,
          ),
          child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      TopoDeEntrada(
                        etiqueta: 'CRIAR CONTA',
                        aoVoltar: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 16),
                      const Center(child: MedalhaoDaMarca(diametro: 150)),
                      const SizedBox(height: 24),
                      const TituloDeEntrada('Criar conta'),
                      const SizedBox(height: 10),
                      const Text(
                        'Leva menos de um minuto',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: AppColors.borda, height: 1),
                      const SizedBox(height: 24),
                      LabeledTextField(
                        label: 'Nome completo',
                        controller: _nameController,
                        hintText: 'Digite seu nome completo',
                        suffixIcon: const Icon(Icons.person_outline,
                            color: AppColors.muted, size: 20),
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
                        suffixIcon: const Icon(Icons.mail_outline,
                            color: AppColors.muted, size: 20),
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            validateEmail(value),
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
                        suffixIcon: const Icon(Icons.phone_outlined,
                            color: AppColors.muted, size: 20),
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
                        hintText: 'Senha forte',
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        validator: validateStrongPassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: AppColors.muted,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      PasswordRequirementsHint(controller: _passwordController),
                      if (_biometricAvailable == true) ...[
                        const SizedBox(height: 18),
                        _BiometricCheckbox(
                          value: _useBiometrics,
                          onChanged: (value) => setState(() => _useBiometrics = value),
                        ),
                      ],
                      const SizedBox(height: 18),
                      TermsAcceptanceCheckbox(
                        value: _aceitouOsTermos,
                        onChanged: (v) => setState(() => _aceitouOsTermos = v),
                      ),
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(auth.errorMessage!, style: const TextStyle(color: AppColors.danger)),
                      ],
                      const SizedBox(height: 24),
                      BotaoComSeta(
                        rotulo: 'Criar conta',
                        carregando: auth.isBusy,
                        aoTocar: (auth.isBusy || !_aceitouOsTermos)
                            ? null
                            : () => _submit(auth),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).maybePop(),
                          behavior: HitTestBehavior.opaque,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              'Já tenho conta, entrar',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
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
      borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
          border: Border.all(
            color: value ? AppColors.primary : AppColors.borda,
          ),
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
