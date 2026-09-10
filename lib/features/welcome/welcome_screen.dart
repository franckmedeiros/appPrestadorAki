import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../widgets/brand_gradient_background.dart';
import '../../widgets/prestadoraki_mark.dart';

/// Tela de boas-vindas antes do login — primeira coisa que um prestador
/// sem sessão salva vê. Layout inspirado numa referência visual que o
/// Franck gostou (fundo em gradiente com formas suaves, logo central,
/// dois botões em pílula), adaptado para as cores da marca OP OutSourcing.
///
/// Também é o que a aba "Perfil" mostra pra quem ainda não tem conta (ver
/// UserProfileScreen) — antes ali aparecia um formulário de login
/// embutido (GuestProfilePanel); o Franck preferiu esta tela, com o
/// "Entrar" levando pra LoginScreen de verdade.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // O fundo (gradiente + círculos) é o mesmo widget usado pela
      // SplashScreen — ver BrandGradientBackground.
      body: BrandGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 3),
                // Marca oficial do app (mesmo desenho vetorial usado na
                // splash screen — ver PrestadorAkiMark) no lugar do ícone
                // genérico de chave/martelo que tinha antes aqui.
                const PrestadorAkiMark(size: 100),
                const SizedBox(height: 24),
                const Text(
                  'PrestadorAki',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Do primeiro orçamento até você chegar à porta do cliente — tudo em um só lugar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const Spacer(flex: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () => context.push('/login'),
                    child: const Text('Entrar', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () => context.push('/register'),
                    child: const Text('Criar conta', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 12),
                // Essa tela agora é só a porta de entrada do prestador
                // (buscar prestador nunca exige conta) — quem chegou aqui
                // sem querer volta direto pra busca.
                TextButton(
                  onPressed: () => context.go('/buscar'),
                  child: Text(
                    'Só quero buscar um prestador',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
