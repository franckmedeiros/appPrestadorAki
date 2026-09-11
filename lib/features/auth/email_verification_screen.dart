import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/decorative_header.dart';
import '../../widgets/gradient_pill_button.dart';

/// Tranca de e-mail confirmado.
///
/// O app já mandava o e-mail de confirmação desde sempre (ver
/// `AuthController.register` -> `sendEmailVerification`) e já sabia dizer
/// se a conta estava confirmada — só que nada disso era EXIGIDO: dava pra
/// usar o app inteiro sem nunca abrir o e-mail. Decisão do Franck: a
/// confirmação passa a ser obrigatória antes de usar qualquer coisa.
///
/// Quem manda pra cá é o `redirect` do go_router (ver app_router.dart),
/// então não há como contornar navegando — qualquer rota de conta logada
/// cai aqui enquanto o e-mail não estiver confirmado. Buscar prestador
/// continua livre pra quem não tem conta nenhuma; a tranca é só pra quem
/// entrou.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _conferindo = false;

  /// Segundos que faltam pra poder reenviar de novo.
  ///
  /// O Firebase limita reenvios seguidos (e responde com erro se a pessoa
  /// insistir), então em vez de deixar ela tomar um erro seco, o botão
  /// espera visivelmente. Também evita o reflexo de tocar várias vezes
  /// achando que não funcionou.
  int _esperaParaReenviar = 0;
  Timer? _contagem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _aoAbrir());
  }

  Future<void> _aoAbrir() async {
    // 1) Confere uma vez: quem confirmou pelo link em outro aparelho (bem
    //    comum — o e-mail costuma estar aberto no computador) já entra
    //    direto, sem precisar tocar em nada.
    await _jaConfirmei(silencioso: true);
    if (!mounted) return;

    // 2) Conta ANTIGA, criada antes desta trava existir: ninguém mandou
    //    link nenhum pra ela, então a pessoa cairia aqui lendo "enviamos
    //    um link" sem ter recebido coisa alguma. Manda agora, uma vez só
    //    (ver AuthController.emailVerificationEmailSent — o cadastro já
    //    marca a flag, então quem acabou de se cadastrar não recebe um
    //    segundo e-mail).
    final auth = context.read<AuthController>();
    if (auth.emailVerified || auth.emailVerificationEmailSent) return;
    await auth.sendEmailVerification();
    if (!mounted) return;
    if (auth.emailVerificationEmailSent) _iniciarEspera();
  }

  @override
  void dispose() {
    _contagem?.cancel();
    super.dispose();
  }

  void _iniciarEspera() {
    setState(() => _esperaParaReenviar = 60);
    _contagem?.cancel();
    _contagem = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _esperaParaReenviar--);
      if (_esperaParaReenviar <= 0) timer.cancel();
    });
  }

  Future<void> _reenviar() async {
    final auth = context.read<AuthController>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await auth.sendEmailVerification();
    if (!mounted) return;
    if (ok) _iniciarEspera();
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'E-mail reenviado. Confira também a caixa de spam.'
            : (auth.errorMessage ?? 'Não foi possível reenviar agora.')),
      ),
    );
  }

  /// Pergunta ao Firebase se o e-mail já foi confirmado.
  ///
  /// `reloadCurrentUser` é obrigatório: o SDK guarda `emailVerified` no
  /// token e NÃO percebe sozinho que a pessoa clicou no link — sem
  /// recarregar, a tela ficaria dizendo "ainda não confirmado" pra sempre,
  /// mesmo com tudo certo do outro lado.
  Future<void> _jaConfirmei({bool silencioso = false}) async {
    if (_conferindo) return;
    setState(() => _conferindo = true);
    final auth = context.read<AuthController>();
    await auth.reloadCurrentUser();
    if (!mounted) return;
    setState(() => _conferindo = false);
    // Confirmado: o `redirect` do go_router reage sozinho à mudança e
    // tira esta tela do caminho — não precisa navegar daqui.
    if (auth.emailVerified || silencioso) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ainda não recebemos a confirmação. Abra o link do e-mail e tente de novo.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final email = auth.currentUserEmail ?? 'seu e-mail';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DecorativeHeader(
              height: 170,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8),
                  Text(
                    'Confirme seu e-mail',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Falta só um passo pra liberar sua conta',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.1),
                        ),
                        child: const Icon(Icons.mark_email_unread_outlined,
                            color: AppColors.primary, size: 34),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Enviamos um link de confirmação para:',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Abra o e-mail, toque no link e volte aqui. Se não achar, '
                      'confira a caixa de spam ou lixo eletrônico.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    GradientPillButton(
                      label: 'Já confirmei',
                      icon: Icons.check,
                      isLoading: _conferindo,
                      onPressed: _conferindo ? null : _jaConfirmei,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: (auth.isBusy || _esperaParaReenviar > 0) ? null : _reenviar,
                      icon: const Icon(Icons.send_outlined, size: 18, color: AppColors.ink),
                      label: Text(
                        _esperaParaReenviar > 0
                            ? 'Reenviar em ${_esperaParaReenviar}s'
                            : 'Reenviar e-mail',
                        style: const TextStyle(color: AppColors.ink),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(color: AppColors.muted.withValues(alpha: 0.35)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Saída de emergência pra quem errou o e-mail no
                    // cadastro: sem isto, a conta ficaria presa nesta tela
                    // pra sempre, sem nenhum caminho de volta.
                    Center(
                      child: TextButton(
                        onPressed: () => context.read<AuthController>().logout(),
                        child: const Text(
                          'Usar outra conta',
                          style: TextStyle(color: AppColors.muted, fontSize: 13),
                        ),
                      ),
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
