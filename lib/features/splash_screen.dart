import 'package:flutter/material.dart';
import '../widgets/brand_gradient_background.dart';
import '../widgets/prestadoraki_mark.dart';

/// Mostrada só durante o AuthController.bootstrap() (leitura do secure
/// storage, com duração mínima garantida — ver bootstrap()). O redirect
/// do go_router tira o usuário daqui assim que o status deixa de ser
/// AuthStatus.unknown.
///
/// O fundo é o mesmo widget da tela de boas-vindas
/// (BrandGradientBackground), a pedido do Franck: antes eram dois
/// gradientes diferentes (aqui, duas paradas e sem os círculos), e dava
/// pra ver o fundo mudando na passagem de uma tela pra outra.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: BrandGradientBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrestadorAkiMark(size: 140),
              SizedBox(height: 24),
              Text(
                'PrestadorAki',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Encontre. Contrate. Acompanhe.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 40),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
