import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/biometric_service.dart';
import '../../core/validators.dart';
import '../../widgets/botao_com_seta.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/marca_app.dart';

/// Entrar na conta.
///
/// Redesenhada a partir da entrega do Figma (out/2026). Antes era um
/// cabeçalho laranja com um cartão branco subindo por cima dele — o
/// desenho que veio do app Resenha. Saiu por dois motivos: o cartão
/// branco sobre fundo branco não separava nada (era enfeite com custo de
/// 24px de deslocamento vertical), e o cabeçalho colorido empurrava os
/// campos pra baixo justo numa tela em que a pessoa já sabe o que vai
/// fazer e só quer digitar.
///
/// A lógica de login e biometria é a mesma de sempre — só a aparência
/// mudou.
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

  // Um botão de biometria de verdade (não só um indicador passivo) fica
  // sempre visível aqui — toca pra destravar direto, sem digitar
  // e-mail/senha. Fica apagado, com o motivo escrito embaixo, quando o
  // aparelho não suporta ou ainda não há sessão salva pra destravar.
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
    // Sucesso navega sozinho (o redirect do go_router reage à mudança de
    // status); só precisa avisar quando NÃO deu certo.
    if (result != BiometricResult.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
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
    final ok = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    // Deu errado: a mensagem já aparece no corpo da tela
    // (`auth.errorMessage` no build).
    if (!ok || !mounted) return;
    // Navegação EXPLÍCITA (antes esta tela só contava com o `redirect` do
    // go_router reagir à mudança de status) — mesmo motivo do
    // RegisterScreen: no cadastro isso deixou a tela parada, sem erro nem
    // sucesso, com a conta já criada. O redirect continua valendo como
    // rede de segurança.
    context.go('/perfil');
  }

  /// Esta tela é usada por dois caminhos: a rota de topo '/login' (tela
  /// cheia) e a sub-rota '/perfil/entrar' (dentro da aba "Perfil", com a
  /// barra de navegação embaixo — ver app_router.dart). Os links daqui
  /// pra "Cadastre-se"/"Esqueci minha senha" precisam seguir o mesmo
  /// caminho de quem abriu esta tela, senão quem entrou pela aba seria
  /// jogado pra fora da casca do app no meio do fluxo.
  bool get _dentroDaAbaPerfil =>
      GoRouterState.of(context).matchedLocation.startsWith('/perfil');

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canPop = context.canPop();
    final naAba = _dentroDaAbaPerfil;

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
                  etiqueta: 'LOGIN',
                  aoVoltar: canPop ? () => context.pop() : null,
                ),
                const SizedBox(height: 20),
                const Center(child: MedalhaoDaMarca(diametro: 180)),
                const SizedBox(height: 28),
                const TituloDeEntrada('Bem-vindo de volta'),
                const SizedBox(height: 10),
                const Text(
                  'Entre para continuar gerenciando seus atendimentos',
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
                  label: 'E-mail',
                  controller: _emailController,
                  hintText: 'seuemail@exemplo.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: validateEmail,
                  suffixIcon: const Icon(
                    Icons.mail_outline,
                    color: AppColors.muted,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 16),
                LabeledTextField(
                  label: 'Senha',
                  controller: _passwordController,
                  hintText: '••••••••',
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  validator: validateLoginPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.muted,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                  ),
                ),
                const SizedBox(height: 4),
                // Centralizado, e não encostado na direita como antes:
                // no desenho novo ele é a única coisa entre o campo e o
                // botão, e alinhado à direita ficava órfão.
                Center(
                  child: TextButton(
                    onPressed: () => context.push(
                      naAba ? '/perfil/esqueci-senha' : '/esqueci-senha',
                    ),
                    child: const Text('Esqueci minha senha'),
                  ),
                ),
                if (auth.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    auth.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: 12),
                BotaoComSeta(
                  rotulo: 'Entrar',
                  carregando: auth.isBusy,
                  aoTocar: auth.isBusy ? null : () => _submit(auth),
                ),
                const SizedBox(height: 24),
                _SecaoDeBiometria(
                  disponivel: _biometricAvailable,
                  pronta:
                      _biometricAvailable == true &&
                      auth.biometricEnabled &&
                      auth.hasCachedSession,
                  carregando: _unlockingBiometrics,
                  aoTocar: () => _unlockWithBiometrics(auth),
                ),
                const SizedBox(height: 28),
                Center(
                  child: GestureDetector(
                    onTap: () => context.push(
                      naAba ? '/perfil/criar-conta' : '/register',
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Não tem conta? Cadastre-se',
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

/// O separador "ou" e o botão de biometria.
///
/// O botão é um quadrado arredondado, não um círculo: no desenho novo
/// todo alvo de toque do app tem o mesmo canto de 8, e um círculo solto
/// no meio da tela puxava o olho mais do que ele merece — biometria é
/// atalho, não a ação principal.
class _SecaoDeBiometria extends StatelessWidget {
  const _SecaoDeBiometria({
    required this.disponivel,
    required this.pronta,
    required this.carregando,
    required this.aoTocar,
  });

  final bool? disponivel;
  final bool pronta;
  final bool carregando;
  final VoidCallback aoTocar;

  String get _legenda {
    if (disponivel == null) return '';
    if (disponivel == false) return 'Biometria indisponível neste aparelho';
    if (!pronta) return 'Faça login uma vez para ativar a biometria';
    return 'Digital ou reconhecimento facial';
  }

  @override
  Widget build(BuildContext context) {
    if (disponivel == null) return const SizedBox.shrink();

    return Column(
      children: [
        const Row(
          children: [
            Expanded(child: Divider(color: AppColors.borda, height: 1)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'ou',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            Expanded(child: Divider(color: AppColors.borda, height: 1)),
          ],
        ),
        const SizedBox(height: 18),
        Opacity(
          opacity: pronta ? 1 : 0.45,
          child: Column(
            children: [
              Material(
                color: AppColors.primarySuave,
                borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    AppMetrics.raioDeControle,
                  ),
                  onTap: (carregando || !pronta) ? null : aoTocar,
                  child: SizedBox(
                    width: AppMetrics.alturaDeControle,
                    height: AppMetrics.alturaDeControle,
                    child: carregando
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(
                            Icons.fingerprint,
                            color: AppColors.primary,
                            size: 28,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _legenda,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
