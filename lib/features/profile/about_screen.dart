import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';

/// "Sobre o app" — pedido do Franck: "seria interessante ter em algum
/// lugar no app os dados da empresa responsável pelo produto e o
/// whats/email". Tela própria (em vez de só um texto solto), acessível
/// tanto pro cliente quanto pro prestador a partir do menu de perfil (ver
/// UserProfileScreen) — informação institucional/suporte, não depende de
/// estar logado como um tipo de conta específico.
///
/// WhatsApp/e-mail de suporte ficam fixos aqui no código (não vêm do
/// Firestore) por serem dados institucionais da empresa, não do
/// prestador/cliente logado — mesma decisão de manter o catálogo de
/// categorias como asset estático em vez de coleção editável, pela mesma
/// razão: muda raríssimo, e mudar aqui é só uma nova versão do app.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _nomeEmpresa = 'OPOutSourcing Brasil';

  /// Formato local (DDD + número, sem "55") — mesmo padrão já usado nos
  /// campos de WhatsApp do resto do app (ver EditProfileScreen).
  static const String _whatsappLocal = '(16) 98844-9751';

  static const String _email = 'opoutsourcingbr@gmail.com';

  Future<void> _abrirWhatsapp(BuildContext context) async {
    final digits = _whatsappLocal.replaceAll(RegExp(r'[^0-9]'), '');
    final comCodigoDoPais = digits.startsWith('55') ? digits : '55$digits';
    final uri = Uri.parse('https://wa.me/$comCodigoDoPais');
    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
      );
    }
  }

  Future<void> _abrirEmail(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: _email);
    final abriu = await launchUrl(uri);
    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir um app de e-mail.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sobre o app')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/brand/logo_opoutsourcing.jpg',
                width: 96,
                height: 96,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'PrestadorAki',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          const Text(
            'Um produto de $_nomeEmpresa',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          const SizedBox(height: 28),
          const _SectionLabel('Fale conosco'),
          const SizedBox(height: 10),
          _ContactTile(
            icon: Icons.chat_outlined,
            label: 'WhatsApp',
            value: _whatsappLocal,
            onTap: () => _abrirWhatsapp(context),
          ),
          const SizedBox(height: 10),
          _ContactTile(
            icon: Icons.email_outlined,
            label: 'E-mail',
            value: _email,
            onTap: () => _abrirEmail(context),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.muted.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
