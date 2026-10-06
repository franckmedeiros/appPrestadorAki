import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../widgets/marca_app.dart';

/// Mostrada só durante o AuthController.bootstrap() (leitura do secure
/// storage, com duração mínima garantida — ver bootstrap()). O redirect
/// do go_router tira o usuário daqui assim que o status deixa de ser
/// AuthStatus.unknown.
///
/// Usa o MESMO medalhão e o mesmo fundo creme da tela de boas-vindas, a
/// pedido do Franck lá atrás: antes eram dois fundos diferentes e dava
/// pra ver o fundo mudando na passagem de uma tela pra outra. Agora o
/// medalhão fica parado no mesmo lugar e só o resto da tela aparece em
/// volta dele — a troca some.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MedalhaoDaMarca(),
            SizedBox(height: 32),
            MarcaEscrita(fontSize: 26),
            SizedBox(height: 10),
            Text(
              'Encontre. Contrate. Acompanhe.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            SizedBox(height: 40),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
