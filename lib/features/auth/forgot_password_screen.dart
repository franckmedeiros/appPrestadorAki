import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/validators.dart';
import '../../widgets/marca_app.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/labeled_text_field.dart';

/// Tela "Esqueci minha senha" (pedido do Franck: "colocar o esqueci a
/// senha ... como o app vai pra nivel nacional, deve ter segurança
/// grande") — só pede o e-mail e dispara
/// `AuthController.sendPasswordResetEmail`, que por sua vez chama o
/// `sendPasswordResetEmail` do Firebase Auth.
///
/// Importante: a mensagem de confirmação é SEMPRE a mesma genérica,
/// exista ou não conta com aquele e-mail (anti-enumeração — ver
/// `AuthController.sendPasswordResetEmail`, que já trata o erro
/// `user-not-found` como sucesso silencioso). Isso evita que alguém use
/// esse formulário pra descobrir quais e-mails têm conta no app.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await auth.sendPasswordResetEmail(_emailController.text.trim());
    if (!mounted) return;
    // `ok` só vem false em erro de conexão/servidor (ver
    // AuthController.sendPasswordResetEmail) — mesmo e-mail inexistente
    // retorna true, de propósito, pra não revelar se a conta existe.
    if (ok) {
      setState(() => _sent = true);
    }
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.margemLateral,
                12,
                AppMetrics.margemLateral,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TopoDeEntrada(
                    etiqueta: 'SENHA',
                    aoVoltar: canPop ? () => context.pop() : null,
                  ),
                  const SizedBox(height: 24),
                  const TituloDeEntrada('Recuperar senha'),
                  const SizedBox(height: 10),
                  const Text(
                    'Informe o e-mail da sua conta para receber o link de redefinição de senha',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: AppColors.borda, height: 1),
                ],
              ),
            ),
            // O cartão branco que subia 24px por cima do cabeçalho saiu:
            // branco sobre branco não separava nada, e o deslocamento
            // vertical era só custo. O corpo agora é o próprio fundo
            // creme da tela.
            Transform.translate(
              offset: Offset.zero,
              child: Container(
                decoration: const BoxDecoration(color: AppColors.background),
                padding: const EdgeInsets.fromLTRB(
                  AppMetrics.margemLateral,
                  8,
                  AppMetrics.margemLateral,
                  24,
                ),
                child: _sent
                    ? _SentConfirmation(email: _emailController.text.trim())
                    : Form(
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
                              textInputAction: TextInputAction.done,
                              validator: validateEmail,
                            ),
                            if (auth.errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(auth.errorMessage!, style: const TextStyle(color: AppColors.danger)),
                            ],
                            const SizedBox(height: 24),
                            GradientPillButton(
                              label: 'Enviar link de redefinição',
                              isLoading: auth.isBusy,
                              onPressed: auth.isBusy ? null : () => _submit(auth),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Lembrou a senha? ', style: TextStyle(color: AppColors.muted)),
                                GestureDetector(
                                  onTap: () => context.pop(),
                                  child: const Text(
                                    'Entrar',
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

/// Mensagem mostrada depois do envio — sempre a mesma, exista ou não a
/// conta (ver nota anti-enumeração acima).
class _SentConfirmation extends StatelessWidget {
  const _SentConfirmation({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mark_email_read_outlined, color: AppColors.success),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Se houver uma conta cadastrada com o e-mail "$email", '
                  'enviamos um link para redefinir a senha. Verifique também '
                  'a caixa de spam.',
                  style: const TextStyle(color: AppColors.ink, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        GradientPillButton(
          label: 'Voltar para o login',
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}
