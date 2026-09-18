import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import 'blocked_users_controller.dart';

/// Lista de quem a conta logada bloqueou, com a opção de desbloquear.
///
/// Bloquear sem poder desbloquear seria uma armadilha: a pessoa clica uma
/// vez, some com o conteúdo de alguém pra sempre e não tem como voltar
/// atrás. Esta tela é a metade que fecha o par — e é também o que a Apple
/// espera encontrar quando procura o controle de bloqueio (Guideline 1.2).
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  @override
  void initState() {
    super.initState();
    // Depois do primeiro frame: `ensureLoaded` notifica ouvintes, e
    // notificar durante o build da árvore dispara erro do Flutter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BlockedUsersController>().ensureLoaded();
    });
  }

  Future<void> _desbloquear(String uid, String nome) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Desbloquear $nome?'),
        content: const Text('Você volta a ver as avaliações e os comentários dessa pessoa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    try {
      await context.read<BlockedUsersController>().desbloquear(uid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível desbloquear. $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BlockedUsersController>();
    final bloqueados = controller.bloqueados.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Usuários bloqueados')),
      body: bloqueados.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 70),
                Icon(Icons.block, size: 44, color: AppColors.muted),
                SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Você não bloqueou ninguém.\n\nPara bloquear, toque nos três pontinhos '
                    'de uma avaliação e escolha "Bloquear este usuário".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bloqueados.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final entrada = bloqueados[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.background,
                      child: Icon(Icons.person_outline, color: AppColors.muted),
                    ),
                    title: Text(entrada.value),
                    trailing: TextButton(
                      onPressed: () => _desbloquear(entrada.key, entrada.value),
                      child: const Text('Desbloquear'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
