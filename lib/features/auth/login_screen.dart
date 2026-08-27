import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/biometric_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Logo(),
                  const SizedBox(height: 32),
                  Text(
                    'Entrar',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    validator: (value) =>
                        (value == null || !value.contains('@')) ? 'Informe um e-mail válido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                    validator: (value) =>
                        (value == null || value.length < 8) ? 'Mínimo de 8 caracteres' : null,
                  ),
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      auth.errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: auth.isBusy ? null : () => _submit(auth),
                    child: auth.isBusy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 20),
                  _BiometricButton(
                    available: _biometricAvailable,
                    ready: _biometricAvailable == true &&
                        auth.biometricEnabled &&
                        auth.hasCachedSession,
                    loading: _unlockingBiometrics,
                    onTap: () => _unlockWithBiometrics(auth),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Ainda não tenho conta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão de biometria — igual ao app Resenha: um círculo com o ícone de
/// digital, sempre visível na tela de login, com o texto embaixo
/// explicando o estado atual. Só fica tocável (`ready`) quando o aparelho
/// suporta, a biometria já foi ativada antes e existe uma sessão salva
/// pra destravar — nos outros casos fica desabilitado (opacidade menor),
/// mas continua visível, deixando claro o que falta pra poder usar.
class _BiometricButton extends StatelessWidget {
  const _BiometricButton({
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
    if (available == null) return const SizedBox(height: 20);

    return Center(
      child: GestureDetector(
        onTap: (loading || !ready) ? null : onTap,
        child: Opacity(
          opacity: ready ? 1 : 0.4,
          child: Column(
            children: [
              const Text('ou entre com biometria',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 12),
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
              Text(_helperText, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.handyman_rounded, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 12),
        const Text(
          'PrestadorAki',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink),
        ),
        const Text(
          'Tecnologia que conecta.',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      ],
    );
  }
}
