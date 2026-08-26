import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/prestadoraki_mark.dart';

/// Mostrada só durante o AuthController.bootstrap() (leitura do secure
/// storage, com duração mínima garantida — ver bootstrap()). O redirect
/// do go_router tira o usuário daqui assim que o status deixa de ser
/// AuthStatus.unknown.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: const Center(
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
