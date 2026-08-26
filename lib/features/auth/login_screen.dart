import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Igual ao app Resenha: um indicador de biometria fica sempre visível
  // aqui na tela de login (mesmo que ainda não dê pra usar), em vez de só
  // aparecer depois de logar. Isso deixa claro, assim que o app abre, se
  // o aparelho suporta biometria — sem depender de nenhum outro passo.
  bool? _biometricAvailable;

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
                  _BiometricStatusIndicator(available: _biometricAvailable),
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

/// Indicador (não interativo) de disponibilidade de biometria, sempre
/// visível na tela de login — `null` enquanto ainda está checando,
/// `true`/`false` depois. Ativar a biometria de fato acontece depois do
/// primeiro login, no cartão do Dashboard; aqui é só a confirmação de que
/// o aparelho suporta, pra não parecer que "não tem nada de biometria".
class _BiometricStatusIndicator extends StatelessWidget {
  const _BiometricStatusIndicator({required this.available});

  final bool? available;

  @override
  Widget build(BuildContext context) {
    if (available == null) return const SizedBox(height: 20);

    return Center(
      child: Column(
        children: [
          Icon(
            Icons.fingerprint,
            size: 28,
            color: available! ? AppColors.primary : AppColors.muted,
          ),
          const SizedBox(height: 4),
          Text(
            available!
                ? 'Este aparelho suporta login por biometria'
                : 'Biometria indisponível neste aparelho',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
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
