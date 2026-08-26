import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Mostrada só durante o AuthController.bootstrap() (leitura do secure
/// storage). O redirect do go_router tira o usuário daqui assim que o
/// status deixa de ser AuthStatus.unknown.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
