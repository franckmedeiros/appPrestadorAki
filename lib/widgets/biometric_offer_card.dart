import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Cartão fixo (não um dialog que passa rápido) oferecendo ativar a
/// biometria — fica visível no topo da tela sempre que o aparelho
/// suporta e o usuário ainda não ativou, até ele ativar ou fechar o
/// cartão. Compartilhado entre DashboardScreen (prestador) e
/// ClientHomeScreen (cliente) — antes só existia do lado do prestador,
/// deixando o cliente sem nenhum jeito de ativar biometria fora do
/// cadastro (ver RegisterScreen). Um cartão fixo em vez de um AlertDialog
/// de uma vez só evita duas armadilhas: (1) é fácil de perder se o
/// timing do postFrameCallback bater errado, e (2) com o go_router
/// redirecionando sozinho assim que o login termina, um dialog aberto na
/// tela de login corre risco de ser derrubado pela navegação antes que a
/// pessoa consiga ler — um cartão na tela de destino não tem esse
/// problema. Mesma ideia do botão de biometria persistente do app
/// Resenha.
class BiometricOfferCard extends StatelessWidget {
  const BiometricOfferCard({super.key, required this.onEnable, required this.onDismiss});

  final VoidCallback onEnable;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fingerprint, color: AppColors.primary, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Entrar com biometria',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Use digital ou reconhecimento facial pra abrir o app mais rápido da próxima vez.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton(onPressed: onEnable, child: const Text('Ativar')),
                      TextButton(onPressed: onDismiss, child: const Text('Agora não')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
