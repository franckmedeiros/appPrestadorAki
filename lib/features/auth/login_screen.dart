import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/biometric_service.dart';
import '../../widgets/decorative_header.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/labeled_text_field.dart';

/// Layout reestilizado igual ao app Resenha (cabeçalho em gradiente +
/// cartão branco arredondado por cima, ver widgets/decorative_header.dart)
/// — a lógica de login/biometria continua exatamente a mesma de antes,
/// só a aparência mudou.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Igual ao app Resenha: um botão de biometria de verdade (não só um
  // indicador passivo) fica sempre visível aqui na tela de login — toca
  // pra tentar destravar direto, sem precisar digitar e-mail/senha. Fica
  // desabilitado (cinza, com o motivo escrito embaixo) quando o aparelho
  // não suporta ou ainda não tem sessão salva pra destravar.
  bool? _biometricAvailable;
  bool _unlockingBiometrics = false;

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

  Future<void> _unlockWithBiometrics(AuthController auth) async {
    setState(() => _unlockingBiometrics = true);
    final result = await auth.unlockWithBiometrics();
    if (!mounted) return;
    setState(() => _unlockingBiometrics = false);
    // Sucesso navega sozinho (redirect do go_router reage à mudança de
    // status); só precisa avisar quando NÃO deu certo.
    if (result != BiometricResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    // Sucesso navega sozinho: o redirect do go_router reage à mudança de
    // status no AuthController (ver app_router.dart).
    await auth.login(_emailController.text.trim(), _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canPop = context.canPop();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecorativeHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canPop) ...[
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                    ),
                    const SizedBox(height: 14),
                  ] else
                    const SizedBox(height: 8),
                  const Text(
                    'Bem-vindo de volta!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Entre para continuar gerenciando seus atendimentos',
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
                      LabeledTextField(
                        label: 'Senha',
                        controller: _passwordController,
                        hintText: '••••••••',
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
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(auth.errorMessage!, style: const TextStyle(color: AppColors.danger)),
                      ],
                      const SizedBox(height: 24),
                      GradientPillButton(
                        label: 'Entrar',
                        isLoading: auth.isBusy,
                        onPressed: auth.isBusy ? null : () => _submit(auth),
                      ),
                      const SizedBox(height: 28),
                      _BiometricSection(
                        available: _biometricAvailable,
                        ready: _biometricAvailable == true && auth.biometricEnabled && auth.hasCachedSession,
                        loading: _unlockingBiometrics,
                        onTap: () => _unlockWithBiometrics(auth),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Não tem conta? ', style: TextStyle(color: AppColors.muted)),
                          GestureDetector(
                            onTap: () => context.push('/register'),
                            child: const Text(
                              'Cadastre-se',
                              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
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

/// Divisor "ou entre com biometria" + círculo tocável — mesmo desenho do
/// app Resenha, adaptado pra reagir ao estado real de biometria do
/// PrestadorAki (aparelho suporta / já foi ativada / tem sessão salva).
class _BiometricSection extends StatelessWidget {
  const _BiometricSection({
    required this.available,
    required this.ready,
    required this.loading,
    required this.onTap,
  });

  final bool? available;
  final bool ready;
  final bool loading;
  final VoidCallback onTap;

  String get _helperText {
    if (available == null) return '';
    if (available == false) return 'Biometria indisponível neste aparelho';
    if (!ready) return 'Faça login uma vez para ativar a biometria';
    return 'Digital ou reconhecimento facial';
  }

  @override
  Widget build(BuildContext context) {
    if (available == null) return const SizedBox.shrink();

    return Column(
      children: [
        const Row(
          children: [
            Expanded(child: Divider(color: Color(0xFFE4DAD6))),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('ou entre com biometria', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
            Expanded(child: Divider(color: Color(0xFFE4DAD6))),
          ],
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: (loading || !ready) ? null : onTap,
          child: Opacity(
            opacity: ready ? 1 : 0.4,
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.08),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                  ),
                  child: loading
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
                        )
                      : const Icon(Icons.fingerprint, color: AppColors.primary, size: 34),
                ),
                const SizedBox(height: 8),
                Text(_helperText, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
