import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/biometric_service.dart';
import '../marketplace/favorites_repository.dart';

/// Mostrada quando `AuthStatus.locked` — já existe uma sessão salva, mas o
/// usuário ativou o cadeado biométrico (a opção é oferecida no cadastro,
/// ver RegisterScreen, ou depois pelo cartão do Dashboard do lado do
/// prestador). Só aparece depois do bootstrap, nunca no primeiro login.
class BiometricUnlockScreen extends StatefulWidget {
  const BiometricUnlockScreen({super.key});

  @override
  State<BiometricUnlockScreen> createState() => _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends State<BiometricUnlockScreen> {
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Chama o prompt biométrico automaticamente ao abrir a tela — o
    // usuário ainda pode tentar de novo pelo botão se cancelar sem querer.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    final result = await auth.unlockWithBiometrics();
    if (!mounted) return;
    if (result == BiometricResult.success) {
      // "quando abrir o sistema, se tiver biometria, já carregar os
      // favoritos" — dispara em segundo plano, sem esperar: a aba
      // Favoritos (ver FavoritesRepository.warmUp) já encontra o
      // resultado pronto quando o usuário abrir ela, em vez de mostrar um
      // spinner na hora. Vale pra qualquer conta agora (não é mais
      // exclusivo de "cliente" — um prestador também pode ter favoritos).
      context.read<FavoritesRepository>().warmUp();
    }
    setState(() {
      _checking = false;
      if (result != BiometricResult.success) _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.fingerprint, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 24),
                const Text(
                  'PrestadorAki está travado',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use sua biometria para continuar.',
                  style: TextStyle(color: Colors.white70),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _checking ? null : _unlock,
                    child: _checking
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Text('Tentar novamente'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: auth.isBusy ? null : () => context.read<AuthController>().useLoginInstead(),
                  child: const Text('Entrar com e-mail e senha', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
