import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';

/// Tela de boas-vindas antes do login — primeira coisa que um prestador
/// sem sessão salva vê. Layout inspirado numa referência visual que o
/// Franck gostou (fundo em gradiente com formas suaves, ícone central,
/// dois botões em pílula), adaptado para as cores da marca OP OutSourcing.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryDark, AppColors.primary, AppColors.ink],
              ),
            ),
          ),
          const _DecorativeBlob(top: -60, left: -60, size: 220),
          const _DecorativeBlob(top: 120, right: -80, size: 260),
          const _DecorativeBlob(bottom: 40, left: -70, size: 200),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.handyman_rounded, color: Colors.white, size: 48),
                  ),
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
        ],
      ),
    );
  }
}

class _DecorativeBlob extends StatelessWidget {
  const _DecorativeBlob({this.top, this.left, this.right, this.bottom, required this.size});

  final double? top;
  final double? left;
  final double? right;
  final double? bottom;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}
